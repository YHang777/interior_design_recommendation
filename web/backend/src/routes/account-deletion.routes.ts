import { Router, type Request, type Response, type RequestHandler } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { authenticate } from '../middleware/authenticate';
import { requireUser } from '../middleware/types';
import { env } from '../config/env';
import { fbDb, FieldValue, Timestamp } from '../config/firebase';
import {
  DEFAULT_TOKEN_TTL_SECONDS,
  createVerificationToken,
  verifyVerificationToken,
} from '../lib/verification-token';
import {
  VerificationEmailException,
  VerificationMailer,
} from '../lib/verification-mailer';
import { getAuthUserOrNull } from '../services/identity.service';
import {
  GRACE_DAYS,
  deactivateSupplierProducts,
  purgeDueDeletions,
  writeDeletionAudit,
  type DeletionAuditEntry,
  type PurgeSummary,
} from '../services/deletion.service';

/**
 * Self-service account deletion — the server half of the profile
 * "Delete Account" flow (customer AND supplier). Frozen HTTP contract
 * (the Flutter client is built against exactly this table):
 *
 *   POST /api/account/deletion-request        {confirmEmail}
 *        → 200 {status:'pending_email', expiresAt}
 *        → 400 CONFIRM_MISMATCH · 409 {status, graceUntil?} ·
 *          502 send failed · 503 not configured
 *   POST /api/account/deletion-request/cancel {}
 *        → 200 {status:'cancelled'} · 404 no active request
 *   GET  /api/account/deletion-status
 *        → 200 {status:'none'|'pending_email'|'grace'|'cancelled'|'purged',
 *               graceUntil?, purgeAt?}        (ISO-8601 strings)
 *   GET  /account/delete/confirm?token=…      public, token IS the auth
 *        → 200 styled HTML (scheduled / invalid / already deleted /
 *          request cancelled)
 *
 * State machine: `pending_email` (24h email token) → `grace` (7 days,
 * recoverable by signing in and cancelling) → `purged` (sweep). `cancelled`
 * on recovery, `partial` when a purge step failed (next sweep retries —
 * see deletion.service for why every step is idempotent).
 *
 * Every stage appends to `deletion_audit_logs`. The admin
 * `DELETE /api/users/:uid` path is untouched — this file is self-service
 * only.
 */

/** Collaborators the routes need — injectable so tests can fake them. */
export interface AccountDeletionDeps {
  tokenSecret: string;
  mailer: Pick<VerificationMailer, 'isConfigured' | 'sendDeletionEmail'>;
  /**
   * Auth step. Defaults to the real Firebase ID-token check; tests swap it
   * out so they never need a live credential.
   */
  authorize: RequestHandler;
  db: () => ReturnType<typeof fbDb>;
  /** Auth-record email for `confirmEmail` matching (profile email wins). */
  getAuthEmail: (uid: string) => Promise<string | null>;
  /** Overridable so the status route's fire-and-forget kick is testable. */
  sweep?: () => Promise<PurgeSummary>;
  now?: () => Date;
  log?: (message: string) => void;
}

/** What the public confirm page needs (narrower than the API router). */
type ConfirmDeps = Pick<AccountDeletionDeps, 'tokenSecret' | 'db' | 'now' | 'log'>;

export function defaultAccountDeletionDeps(): AccountDeletionDeps {
  return {
    tokenSecret: env.verifyTokenSecret,
    mailer: new VerificationMailer({
      apiKey: env.brevoApiKey,
      senderEmail: env.brevoSenderEmail,
      senderName: env.brevoSenderName,
      publicBaseUrl: env.publicBaseUrl,
    }),
    authorize: authenticate,
    db: fbDb,
    getAuthEmail: async (uid: string) => (await getAuthUserOrNull(uid))?.email ?? null,
    sweep: purgeDueDeletions,
    log: (message) => console.log(message),
  };
}

const requestBodySchema = z.object({
  confirmEmail: z.string().trim().min(1).max(320),
});
/** The plan fixes the cancel body as `{}` — validates and strips extras. */
const cancelBodySchema = z.object({});

/** Enough config to START a deletion (HMAC secret + Brevo) — 503 otherwise. */
function sendConfigured(deps: AccountDeletionDeps): boolean {
  return deps.tokenSecret.trim().length > 0 && deps.mailer.isConfigured;
}

// ── `/api/account` router ──────────────────────────────────────────────────

export function createAccountDeletionRouter(deps: AccountDeletionDeps): Router {
  const router = Router();

  router.post(
    '/deletion-request',
    deps.authorize,
    validateBody(requestBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      await handleRequest(req, res, deps);
    })
  );

  router.post(
    '/deletion-request/cancel',
    deps.authorize,
    validateBody(cancelBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      await handleCancel(req, res, deps);
    })
  );

  router.get(
    '/deletion-status',
    deps.authorize,
    asyncHandler(async (req: Request, res: Response) => {
      await handleStatus(req, res, deps);
    })
  );

  return router;
}

/**
 * POST /deletion-request — opens the flow. Gate: `confirmEmail` must match
 * the account email case-insensitively (same rule as the admin
 * `deleteAccount`). An existing pending/grace request is a 409 (recovery or
 * waiting for the email link first); `purged`/`cancelled` start fresh.
 *
 * Mail failure → 502 AND the just-written request is ROLLED BACK, so the
 * user can retry immediately instead of hitting a 409 for a request whose
 * email never arrived. If even the rollback fails, the request stays
 * `pending_email` — cancelling it from the app re-opens the path (logged).
 */
async function handleRequest(req: Request, res: Response, deps: AccountDeletionDeps): Promise<void> {
  if (!sendConfigured(deps)) {
    res.status(503).json({ error: 'Account deletion is not configured.' });
    return;
  }
  const user = requireUser(req);
  const { confirmEmail } = requestBodySchema.parse(req.body ?? {});
  const db = deps.db();

  const profileSnap = await db.collection('users').doc(user.uid).get();
  const profile = profileSnap.exists ? profileSnap.data() : undefined;
  const authEmail = await deps.getAuthEmail(user.uid);
  const accountEmail =
    (typeof profile?.email === 'string' && profile.email.length > 0 ? profile.email : '') ||
    authEmail ||
    '';
  if (!accountEmail) {
    throw new ApiError(404, 'USER_NOT_FOUND', 'We could not find your account.');
  }
  if (confirmEmail.trim().toLowerCase() !== accountEmail.trim().toLowerCase()) {
    throw new ApiError(
      400,
      'CONFIRM_MISMATCH',
      'That email does not match the account you are trying to delete.'
    );
  }

  const requestRef = db.collection('deletionRequests').doc(user.uid);
  const existing = await requestRef.get();
  if (existing.exists) {
    const status = existing.get('status');
    if (status === 'pending_email' || status === 'grace') {
      const graceUntil = toIso(existing.get('graceUntil'));
      res.status(409).json({
        status,
        ...(status === 'grace' && graceUntil !== null ? { graceUntil } : {}),
      });
      return;
    }
  }

  const role = typeof profile?.role === 'string' && profile.role.length > 0 ? profile.role : 'homeowner';
  const now = nowOf(deps);
  const expiresAt = new Date(now.getTime() + DEFAULT_TOKEN_TTL_SECONDS * 1000);
  const token = createVerificationToken({
    uid: user.uid,
    email: accountEmail,
    secret: deps.tokenSecret,
    clock: () => now,
    purpose: 'account_delete',
  });

  await requestRef.set({
    uid: user.uid,
    email: accountEmail,
    role,
    status: 'pending_email',
    requestedAt: Timestamp.fromDate(now),
    deactivatedProductIds: [],
  });

  try {
    await deps.mailer.sendDeletionEmail({
      email: accountEmail,
      token,
      baseUrlOverride: requestBaseUrl(req),
    });
  } catch (err) {
    if (err instanceof VerificationEmailException) {
      deps.log?.(`[deletion] send failed: ${err.message}`);
      try {
        await requestRef.delete();
      } catch (rollbackErr) {
        deps.log?.(
          `[deletion] rollback failed for ${user.uid}: ${
            rollbackErr instanceof Error ? rollbackErr.message : String(rollbackErr)
          }`
        );
      }
      res.status(502).json({ error: 'Could not send the confirmation email. Please try again.' });
      return;
    }
    throw err;
  }

  await auditBestEffort(
    db,
    {
      uid: user.uid,
      role,
      event: 'requested',
      at: now,
      ip: clientIp(req),
      userAgent: userAgentOf(req),
      dataTypes: [],
      counts: {},
      metadata: { expiresAt: expiresAt.toISOString() },
    },
    deps
  );

  res.status(200).json({ status: 'pending_email', expiresAt: expiresAt.toISOString() });
}

/**
 * POST /deletion-request/cancel — recovers a pending (email not yet
 * confirmed) or grace-period request. Recovery runs BEFORE the status flip:
 * if restoring listings failed, the request is still `grace` and the user
 * can retry; the other order could cancel the request while listings stay
 * switched off with no way back.
 */
async function handleCancel(req: Request, res: Response, deps: AccountDeletionDeps): Promise<void> {
  const user = requireUser(req);
  const db = deps.db();
  const requestRef = db.collection('deletionRequests').doc(user.uid);
  const snap = await requestRef.get();
  const status = snap.exists ? (snap.get('status') as string | undefined) : undefined;
  if (!snap.exists || (status !== 'pending_email' && status !== 'grace')) {
    throw new ApiError(404, 'NOT_FOUND', 'There is no active deletion request to cancel.');
  }

  const now = nowOf(deps);
  const rawRole = snap.get('role');
  const role = typeof rawRole === 'string' && rawRole.length > 0 ? rawRole : 'homeowner';
  let productsRestored = 0;

  if (status === 'grace') {
    const ids = (snap.get('deactivatedProductIds') as string[] | undefined) ?? [];
    for (let i = 0; i < ids.length; i += RESTORE_BATCH) {
      const chunk = ids.slice(i, i + RESTORE_BATCH);
      const batch = db.batch();
      for (const id of chunk) {
        batch.update(db.collection('products').doc(id), { isActive: true });
      }
      await batch.commit();
      productsRestored += chunk.length;
    }

    // Drop the cheap-login mirror; a missing field is a no-op.
    const profileRef = db.collection('users').doc(user.uid);
    const profile = await profileRef.get();
    if (profile.exists) {
      await profileRef.update({ deletion: FieldValue.delete() });
    }
  }

  await requestRef.update({ status: 'cancelled' });
  await auditBestEffort(
    db,
    {
      uid: user.uid,
      role,
      event: 'cancelled',
      at: now,
      ip: clientIp(req),
      userAgent: userAgentOf(req),
      dataTypes: [],
      counts: { productsRestored },
      metadata: { previousStatus: status },
    },
    deps
  );

  res.status(200).json({ status: 'cancelled' });
}

/**
 * GET /deletion-status — cheap enough for the profile screen to poll.
 *
 * Also kicks a fire-and-forget `purgeDueDeletions()` (NEVER awaited): the
 * Render free tier sleeps, so the 15-minute interval in index.ts can lag
 * hours past `purgeAt`; this covers the user who just signed in to recover.
 * The sweep guards itself against overlap, so this is always safe.
 *
 * `partial` is passed through as-is (the plan's Firestore shape allows it);
 * missing doc → `none`. Timestamps surface as ISO-8601 strings.
 */
async function handleStatus(req: Request, res: Response, deps: AccountDeletionDeps): Promise<void> {
  const user = requireUser(req);

  const sweep = deps.sweep ?? purgeDueDeletions;
  void sweep()
    .then((r) => {
      if (r.purged > 0 || r.partial > 0 || r.errors > 0) {
        deps.log?.(`[deletion sweep] purged=${r.purged} partial=${r.partial} errors=${r.errors}`);
      }
    })
    .catch((err: unknown) => {
      deps.log?.(`[deletion sweep] failed: ${err instanceof Error ? err.message : String(err)}`);
    });

  const db = deps.db();
  const snap = await db.collection('deletionRequests').doc(user.uid).get();
  if (!snap.exists) {
    res.status(200).json({ status: 'none' });
    return;
  }

  const rawStatus = snap.get('status');
  const known =
    rawStatus === 'pending_email' ||
    rawStatus === 'grace' ||
    rawStatus === 'cancelled' ||
    rawStatus === 'purged' ||
    rawStatus === 'partial';
  const graceUntil = toIso(snap.get('graceUntil'));
  const purgeAt = toIso(snap.get('purgeAt'));
  res.status(200).json({
    status: known ? rawStatus : 'none',
    ...(graceUntil !== null ? { graceUntil } : {}),
    ...(purgeAt !== null ? { purgeAt } : {}),
  });
}

// ── `/account/delete` router (public — the token IS the authentication) ────

export function createDeletionConfirmRouter(deps: ConfirmDeps): Router {
  const router = Router();
  router.get('/confirm', (req, res) => void handleConfirm(req, res, deps));
  return router;
}

/**
 * GET /account/delete/confirm?token=… → styled HTML (same `renderPage`
 * language as /verify-email/confirm — this page IS "our website").
 *
 * Purpose guard both ways: only `account_delete` tokens land here, and
 * `verify-email/confirm` refuses anything but `email_verify`. Idempotent:
 * an already-grace request re-renders the success page; `purged`/`partial`
 * render "already deleted"; `cancelled` explains how to start over. Never
 * interpolate server exception text into the HTML — only into logs.
 */
async function handleConfirm(req: Request, res: Response, deps: ConfirmDeps): Promise<void> {
  const rawToken = req.query.token;
  const token = typeof rawToken === 'string' ? rawToken : undefined;
  const payload = token === undefined ? null : verifyVerificationToken(token, deps.tokenSecret);
  if (payload === null || payload.purpose !== 'account_delete') {
    renderInvalid(res);
    return;
  }

  try {
    const db = deps.db();
    const requestRef = db.collection('deletionRequests').doc(payload.uid);
    const snap = await requestRef.get();
    if (!snap.exists) {
      renderPage(res, {
        success: false,
        title: 'Deletion request not found',
        message:
          'We could not find a pending deletion request for this link. ' +
          'Please request account deletion again from the app.',
      });
      return;
    }

    const rawEmail = snap.get('email');
    const requestEmail = typeof rawEmail === 'string' ? rawEmail : '';
    if (requestEmail.trim().toLowerCase() !== payload.email.trim().toLowerCase()) {
      // Token/email pair must match the stored request — a token minted for
      // a different address never advances the state machine.
      renderInvalid(res);
      return;
    }

    const status = snap.get('status');
    if (status === 'grace') {
      renderGrace(res, toDate(snap.get('graceUntil')));
      return;
    }
    if (status === 'purged' || status === 'partial') {
      renderPage(res, {
        success: true,
        title: 'Account deleted',
        message: 'This account has already been deleted. There is nothing left to recover.',
      });
      return;
    }
    if (status === 'cancelled') {
      renderPage(res, {
        success: true,
        title: 'Request cancelled',
        message:
          'This deletion request was cancelled. Open the Intellar app if ' +
          'you want to start over.',
      });
      return;
    }
    if (status !== 'pending_email') {
      renderInvalid(res);
      return;
    }

    const now = nowOf(deps);
    const graceUntil = new Date(now.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
    const rawRole = snap.get('role');
    const role = typeof rawRole === 'string' && rawRole.length > 0 ? rawRole : 'homeowner';

    // Deactivate FIRST (ids computed from the live products), then the
    // request becomes the commit record carrying `deactivatedProductIds`,
    // then the cheap-login mirror. A failure before the request update
    // leaves `pending_email` (retry re-runs everything — idempotent); a
    // failure after it leaves a fully consistent `grace`.
    let deactivatedProductIds: string[] = [];
    if (role === 'supplier') {
      deactivatedProductIds = await deactivateSupplierProducts(db, payload.uid);
    }

    await requestRef.update({
      status: 'grace',
      emailConfirmedAt: Timestamp.fromDate(now),
      graceUntil: Timestamp.fromDate(graceUntil),
      purgeAt: Timestamp.fromDate(graceUntil),
      deactivatedProductIds,
    });

    const profileRef = db.collection('users').doc(payload.uid);
    const profile = await profileRef.get();
    if (profile.exists) {
      await profileRef.update({
        deletion: { status: 'grace', purgeAt: Timestamp.fromDate(graceUntil) },
      });
    }

    await auditBestEffort(
      db,
      {
        uid: payload.uid,
        role,
        event: 'email_confirmed',
        at: now,
        ip: clientIp(req),
        userAgent: userAgentOf(req),
        dataTypes: [],
        counts: { productsDeactivated: deactivatedProductIds.length },
        metadata: { graceUntil: graceUntil.toISOString(), purgeAt: graceUntil.toISOString() },
      },
      deps
    );

    renderGrace(res, graceUntil);
  } catch (err) {
    deps.log?.(
      `[deletion] confirm failed for ${payload.uid}: ${err instanceof Error ? err.message : String(err)}`
    );
    renderPage(res, {
      success: false,
      title: 'Could not confirm deletion',
      message: "We couldn't confirm your deletion right now. Please open this link again in a few minutes.",
    });
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

const RESTORE_BATCH = 400;

function nowOf(deps: { now?: () => Date }): Date {
  return deps.now ? deps.now() : new Date();
}

/** First `X-Forwarded-For` hop, else the socket address (audit trail). */
function clientIp(req: Request): string {
  const forwarded = req.headers['x-forwarded-for'];
  const first = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  if (first && first.trim().length > 0) return first.split(',')[0].trim();
  return req.ip ?? '';
}

function userAgentOf(req: Request): string {
  const ua = req.headers['user-agent'];
  return (Array.isArray(ua) ? ua[0] : ua) ?? '';
}

/** Public base URL derived from the request (same rule as /verify-email). */
function requestBaseUrl(req: Request): string | undefined {
  const host = req.headers.host;
  const forwarded = req.headers['x-forwarded-proto'];
  const forwardedProto = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  const scheme =
    forwardedProto && forwardedProto.trim().length > 0
      ? forwardedProto.split(',')[0].trim()
      : 'https';
  return host && host.length > 0 ? `${scheme}://${host}` : undefined;
}

/** Firestore `Timestamp` | Date | ISO string → ISO-8601, or null. */
function toIso(value: unknown): string | null {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string' && value.length > 0) return value;
  return null;
}

/** Firestore `Timestamp` | Date | ISO string → Date, or null. */
function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.length > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

/**
 * Route-side audit writes are best-effort ON PURPOSE: by the time we write
 * one, the state transition has already happened, and a failed audit insert
 * must not turn it into an error response (the user would retry and hit a
 * 404 / duplicate page). The failure is logged. Sweep-side audits are NOT
 * wrapped — the partial/retry machinery in deletion.service covers them.
 */
async function auditBestEffort(
  db: ReturnType<typeof fbDb>,
  entry: DeletionAuditEntry,
  deps: { log?: (message: string) => void }
): Promise<void> {
  try {
    await writeDeletionAudit(db, entry);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    deps.log?.(`[deletion] audit write failed (${entry.event} ${entry.uid}): ${message}`);
  }
}

// ── HTML pages (inline CSS — these pages ARE "our website") ────────────────

function renderInvalid(res: Response): void {
  renderPage(res, {
    success: false,
    title: 'Deletion link invalid',
    message:
      'This link is invalid or has expired. Please request account ' +
      'deletion again from the app.',
  });
}

function renderGrace(res: Response, graceUntil: Date | null): void {
  renderPage(res, {
    success: true,
    title: 'Deletion scheduled',
    message:
      'You have 7 days to recover. After that your account and personal ' +
      'data are permanently deleted — your order history is kept as ' +
      'anonymized records.',
    note:
      graceUntil === null
        ? 'Sign in to the Intellar app during this window and cancel the deletion to recover your account.'
        : `Sign in to the Intellar app before ${graceUntil.toDateString()} and ` +
          'cancel the deletion to recover your account.',
  });
}

function renderPage(
  res: Response,
  {
    success,
    title,
    message,
    note,
  }: { success: boolean; title: string; message: string; note?: string }
): void {
  const icon = success ? '✔' : '✖';
  const iconClass = success ? 'ok' : 'bad';
  res
    .status(200)
    .type('html')
    .send(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} — Intellar</title>
<style>
  body{font-family:Segoe UI,Roboto,sans-serif;background:#f7f5f2;display:flex;
    align-items:center;justify-content:center;min-height:100vh;margin:0}
  .card{background:#fff;border-radius:16px;padding:40px;max-width:420px;
    text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08)}
  .icon{width:64px;height:64px;border-radius:50%;display:inline-flex;
    align-items:center;justify-content:center;font-size:32px;margin-bottom:16px}
  .ok{background:#e7f6ec;color:#1f9d55}.bad{background:#fdeaea;color:#d64545}
  h1{font-size:22px;margin:0 0 8px;color:#222}
  p{color:#555;font-size:15px;line-height:1.5}
  .note{background:#f0f4ff;border-radius:8px;padding:12px;font-size:13px;color:#334}
</style>
</head>
<body>
<div class="card">
  <div class="icon ${iconClass}">${icon}</div>
  <h1>${title}</h1>
  <p>${message}</p>
${note === undefined ? '' : `  <p class="note">${note}</p>`}
</div>
</body>
</html>`);
}
