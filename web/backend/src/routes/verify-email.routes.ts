import { Router, type Request, type Response } from 'express';
import {
  createVerificationToken,
  verifyVerificationToken,
} from '../lib/verification-token';
import {
  VerificationEmailException,
  type VerificationMailer,
} from '../lib/verification-mailer';

/**
 * `/verify-email` routes — port of `server/lib/verify_handlers.dart` on the
 * Dart server that used to own `interior-design-recommendation.onrender.com`.
 * Paths and response shapes are unchanged, so the Flutter app
 * (`VerificationEmailDatasource`) and links already in inboxes keep working:
 *
 *   POST /verify-email/send    {email, uid} → {sent: true}
 *   GET  /verify-email/confirm?token=…      → styled HTML page
 *
 * NOTE: `send` is intentionally unauthenticated (same as the Dart server —
 * demo-grade, effectively an open relay against the Brevo quota). The
 * verification token itself is unforgeable without the server secret, so the
 * confirm step is safe.
 */

/** Collaborators the routes need — injectable so tests can fake them. */
export interface VerifyEmailDeps {
  tokenSecret: string;
  mailer: Pick<VerificationMailer, 'isConfigured' | 'sendVerificationEmail'>;
  isFirebaseConfigured: () => boolean;
  setEmailVerified: (uid: string) => Promise<void>;
  log?: (message: string) => void;
}

export function createVerifyEmailRouter(deps: VerifyEmailDeps): Router {
  const router = Router();

  router.post('/send', (req, res) => void handleSend(req, res, deps));
  router.get('/confirm', (req, res) => void handleConfirm(req, res, deps));

  return router;
}

/** Enough config to SEND (HMAC secret + Brevo) — 503 otherwise. */
function sendConfigured(deps: VerifyEmailDeps): boolean {
  return deps.tokenSecret.trim().length > 0 && deps.mailer.isConfigured;
}

async function handleSend(
  req: Request,
  res: Response,
  deps: VerifyEmailDeps
): Promise<void> {
  if (!sendConfigured(deps)) {
    res
      .status(503)
      .json({ error: 'Email verification is not configured.' });
    return;
  }

  const body: unknown = req.body;
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    res.status(400).json({ error: 'Invalid JSON body.' });
    return;
  }
  const { email, uid } = body as Record<string, unknown>;
  if (typeof email !== 'string' || email.length === 0 || typeof uid !== 'string' || uid.length === 0) {
    res.status(400).json({ error: 'email and uid are required.' });
    return;
  }

  const token = createVerificationToken({
    uid,
    email,
    secret: deps.tokenSecret,
  });

  // Derive the public base URL from the request itself so the email link
  // always points at the server that actually handled the request, even when
  // PUBLIC_BASE_URL is missing or stale on the host (Render, etc.).
  const host = req.headers.host;
  // Behind a reverse proxy (Render's load balancer), the original scheme is
  // forwarded in X-Forwarded-Proto; fall back to https for production hosts.
  const forwarded = req.headers['x-forwarded-proto'];
  const forwardedProto = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  const scheme = forwardedProto && forwardedProto.trim().length > 0
    ? forwardedProto.split(',')[0].trim()
    : 'https';
  const requestBaseUrl = host && host.length > 0 ? `${scheme}://${host}` : undefined;

  try {
    await deps.mailer.sendVerificationEmail({
      email,
      token,
      baseUrlOverride: requestBaseUrl,
    });
  } catch (err) {
    if (err instanceof VerificationEmailException) {
      deps.log?.(`[verify] send failed: ${err.message}`);
      res.status(502).json({
        error: 'Could not send the verification email. Please try again.',
      });
      return;
    }
    throw err;
  }
  res.status(200).json({ sent: true });
}

/**
 * GET /verify-email/confirm?token=… → styled HTML page ("our website").
 *
 * The token is stateless: a valid link is idempotent and can be retried;
 * an invalid/expired one never reaches Firebase. Never interpolate server
 * exception text into the HTML — only into logs.
 */
async function handleConfirm(
  req: Request,
  res: Response,
  deps: VerifyEmailDeps
): Promise<void> {
  const rawToken = req.query.token;
  const token = typeof rawToken === 'string' ? rawToken : undefined;
  const payload =
    token === undefined
      ? null
      : verifyVerificationToken(token, deps.tokenSecret);
  if (payload === null) {
    renderPage(res, {
      success: false,
      title: 'Verification failed',
      message:
        'This link is invalid or has expired. Please resend the ' +
        'verification email from the app and try again.',
    });
    return;
  }

  if (!deps.isFirebaseConfigured()) {
    deps.log?.('[verify] confirm refused — service account not configured');
    renderPage(res, {
      success: false,
      title: 'Verification unavailable',
      message:
        'Verification is temporarily unavailable. Please try again ' +
        'in a few minutes.',
    });
    return;
  }

  try {
    await deps.setEmailVerified(payload.uid);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    deps.log?.(`[verify] confirm failed for ${payload.uid}: ${message}`);
    renderPage(res, {
      success: false,
      title: 'Verification unavailable',
      message:
        "We couldn't verify your email right now. Please try this " +
        'link again in a few minutes, or resend the verification email ' +
        'from the app.',
    });
    return;
  }
  renderPage(res, {
    success: true,
    title: 'Email Verified!',
    message: `${payload.email} is now verified.`,
    note:
      'Return to the Intellar app, tap "I\'ve Verified", and ' +
      'log in.',
  });
}

// ── HTML page (inline CSS — this page IS "our website") ──────────────────

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
