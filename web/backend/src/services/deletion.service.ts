import { ApiError } from '../lib/errors';
import { env } from '../config/env';
import { fbDb, fbStorage, Timestamp } from '../config/firebase';
import { deleteAuthUser, getAuthUserOrNull } from './identity.service';

/**
 * Account deletion — the most dangerous action the API offers, so it is
 * built to be hard to trigger accidentally and safe to RETRY after a
 * partial failure. Two paths exist:
 *
 *   1. ADMIN DELETE (`deleteAccount`) — immediate, for the admin console.
 *      Unchanged behavior: refuse self-deletion, verify the typed
 *      confirmation email (case-insensitive), delete Firebase Auth, then
 *      Firestore cleanup in risk order (supplier listings DEACTIVATED
 *      first — `products/{id}.isActive = false`, never deleted so
 *      historical orders keep resolving their snapshots — then
 *      `users/{uid}`, then its `cart/` and `wishlist/` subcollections.
 *      `orders/` documents are never deleted (financial history).
 *
 *   2. SELF-SERVICE PURGE (`purgeDueDeletions` / `purgeSelfService`) —
 *      the 7-day-grace flow started from the mobile app. The sweep picks
 *      up `deletionRequests/{uid}` whose `purgeAt` has elapsed and runs
 *      the same cascade plus review scrubbing, order anonymization, IC
 *      document removal and the Supabase `room_designs` delete.
 *
 * Retry safety is the shared invariant: Auth deletion treats "already
 * gone" as success and every Firestore step is idempotent, so while the
 * profile/request documents exist, re-running a half-finished delete is
 * always safe ("profile doc exists ⇒ retry is safe"). `purged` is only
 * written after EVERY step finished; a throw mid-way records `partial`
 * (with a short `lastError`) and the next sweep retries.
 */
export interface DeleteResult {
  uid: string;
  email: string;
  authDeleted: boolean;
  profileDeleted: boolean;
  cartItemsDeleted: number;
  wishlistItemsDeleted: number;
  productsDeactivated: number;
}

const BATCH_LIMIT = 400;

/** Days between the email confirmation and the irreversible purge. */
export const GRACE_DAYS = 7;

export async function deleteAccount(uid: string, confirmEmail: string, actorUid: string): Promise<DeleteResult> {
  if (uid === actorUid) {
    throw new ApiError(400, 'SELF_DELETE', 'You cannot delete your own admin account.');
  }

  const db = fbDb();
  const profileRef = db.collection('users').doc(uid);
  const profileSnap = await profileRef.get();
  const authUser = await getAuthUserOrNull(uid);

  const targetEmail =
    (profileSnap.exists ? (profileSnap.get('email') as string | undefined) : undefined) || authUser?.email || '';
  if (!targetEmail && !profileSnap.exists) {
    throw new ApiError(404, 'USER_NOT_FOUND', `No account found for uid ${uid}.`);
  }
  if (!targetEmail) {
    throw new ApiError(404, 'USER_NOT_FOUND', `Account for uid ${uid} has no email address to confirm against.`);
  }
  if (targetEmail.trim().toLowerCase() !== confirmEmail.trim().toLowerCase()) {
    throw new ApiError(
      400,
      'CONFIRM_MISMATCH',
      'The confirmation email does not match the account you are trying to delete.'
    );
  }

  // ── Step 3: Firebase Auth ────────────────────────────────────────────────
  const authDeleted = await deleteAuthUser(uid);

  // ── Step 4: Firestore cleanup (any failure → PARTIAL_DELETE) ─────────────
  // Order matters: deactivate supplier listings FIRST (marketplace
  // integrity), then the profile (source of truth for role/email), then
  // the harmless per-user subcollections. A retry therefore always still
  // finds the profile while anything important remains to do.
  try {
    const role = profileSnap.exists ? (profileSnap.get('role') as string | undefined) : undefined;
    let productsDeactivated = 0;
    if (role === 'supplier') {
      productsDeactivated = (await deactivateSupplierProducts(db, uid)).length;
    }

    let profileDeleted = false;
    if (profileSnap.exists) {
      await profileRef.delete();
      profileDeleted = true;
    }

    const cartItemsDeleted = await deleteSubcollection(db, uid, 'cart');
    const wishlistItemsDeleted = await deleteSubcollection(db, uid, 'wishlist');

    return {
      uid,
      email: targetEmail,
      authDeleted,
      profileDeleted,
      cartItemsDeleted,
      wishlistItemsDeleted,
      productsDeactivated,
    };
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new ApiError(
      500,
      'PARTIAL_DELETE',
      `The Firebase Auth account for ${targetEmail} was deleted, but Firestore cleanup failed: ${detail}. ` +
        'Run Delete again to finish the cleanup — while the profile document exists, retrying is fully safe. ' +
        'If a retry reports USER_NOT_FOUND, only orphaned cart/wishlist documents can remain (all listings were deactivated first).',
      { authDeleted }
    );
  }
}

/** Deletes every doc in `users/{uid}/{sub}` — returns how many were removed. */
async function deleteSubcollection(
  db: ReturnType<typeof fbDb>,
  uid: string,
  sub: 'cart' | 'wishlist'
): Promise<number> {
  let total = 0;
  for (;;) {
    const snap = await db.collection('users').doc(uid).collection(sub).limit(BATCH_LIMIT).get();
    if (snap.empty) return total;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      total += 1;
    }
    await batch.commit();
    if (snap.size < BATCH_LIMIT) return total;
  }
}

/**
 * Deactivates (never deletes) a supplier's listings — order snapshots keep
 * resolving their product references. Returns the ids it touched: the FULL
 * matched set (including listings that were already inactive), so a retry
 * and a grace-period cancel can always restore exactly this account's
 * products. Batches stay under Firestore's 500-op limit.
 */
export async function deactivateSupplierProducts(
  db: ReturnType<typeof fbDb>,
  uid: string
): Promise<string[]> {
  const productIds = new Set<string>();
  const [bySupplierId, byNestedSupplier] = await Promise.all([
    db.collection('products').where('supplierId', '==', uid).select('supplierId').get(),
    db.collection('products').where('supplier.id', '==', uid).select('supplier').get(),
  ]);
  for (const doc of bySupplierId.docs) productIds.add(doc.id);
  for (const doc of byNestedSupplier.docs) productIds.add(doc.id);

  const ids = [...productIds];
  for (let i = 0; i < ids.length; i += BATCH_LIMIT) {
    const chunk = ids.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const id of chunk) {
      batch.update(db.collection('products').doc(id), { isActive: false });
    }
    await batch.commit();
  }
  return ids;
}

// ── Self-service purge (7-day grace → sweep) ───────────────────────────────

/** Lifecycle of a `deletionRequests/{uid}` document (self-service flow). */
export type DeletionRequestStatus =
  | 'pending_email'
  | 'grace'
  | 'partial'
  | 'purged'
  | 'cancelled';

export interface DeletionRequestDoc {
  uid: string;
  email: string;
  role: string;
  status: DeletionRequestStatus;
  requestedAt?: unknown;
  emailConfirmedAt?: unknown;
  graceUntil?: unknown;
  purgeAt?: unknown;
  purgedAt?: unknown;
  /** Supplier listings switched off at confirmation — restored on cancel. */
  deactivatedProductIds?: string[];
  lastError?: string;
}

export interface PurgeSummary {
  purged: number;
  partial: number;
  errors: number;
}

export type DeletionAuditEvent =
  | 'requested'
  | 'email_confirmed'
  | 'cancelled'
  | 'purge_started'
  | 'purged'
  | 'partial_delete';

export interface DeletionAuditEntry {
  uid: string;
  role: string;
  event: DeletionAuditEvent;
  at: Date;
  ip?: string;
  userAgent?: string;
  dataTypes?: string[];
  counts?: Record<string, number | string>;
  metadata?: Record<string, unknown>;
}

/** Append-only row in `deletion_audit_logs` — one per lifecycle event. */
export async function writeDeletionAudit(
  db: ReturnType<typeof fbDb>,
  entry: DeletionAuditEntry
): Promise<void> {
  await db.collection('deletion_audit_logs').add({
    uid: entry.uid,
    role: entry.role,
    event: entry.event,
    at: Timestamp.fromDate(entry.at),
    ip: entry.ip ?? '',
    userAgent: entry.userAgent ?? '',
    dataTypes: entry.dataTypes ?? [],
    counts: entry.counts ?? {},
    metadata: entry.metadata ?? {},
  });
}

/**
 * Collaborators the purge needs — injectable so tests run against a fake
 * Firestore / fetch without touching live Firebase or Supabase.
 */
export interface PurgeDeps {
  db: () => ReturnType<typeof fbDb>;
  /** Firebase Auth delete (idempotent: missing account ⇒ false, not a throw). */
  deleteAuth: (uid: string) => Promise<boolean>;
  /** Deletes Storage `verification/{uid}/*` — returns the file count. */
  deleteVerificationFiles: (uid: string) => Promise<number>;
  fetchImpl: typeof fetch;
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  now: () => Date;
  log: (message: string) => void;
}

function defaultPurgeDeps(): PurgeDeps {
  return {
    db: fbDb,
    deleteAuth: deleteAuthUser,
    deleteVerificationFiles: deleteVerificationStorageFiles,
    fetchImpl: (input, init) => fetch(input, init),
    supabaseUrl: env.supabaseUrl,
    supabaseServiceRoleKey: env.supabaseServiceRoleKey,
    now: () => new Date(),
    log: (message) => console.log(message),
  };
}

/**
 * Deletes Storage `verification/{uid}/*` (IC images / supporting documents).
 * Deliberately wrapped in try/catch: a missing bucket or a transient Storage
 * error must not sink the whole purge — the files are unreadable by clients
 * anyway (deny-all security rules) once the account is gone, and the failure
 * is logged with a count of 0.
 */
async function deleteVerificationStorageFiles(uid: string): Promise<number> {
  try {
    const [files] = await fbStorage().getFiles({ prefix: `verification/${uid}/` });
    let count = 0;
    for (const file of files) {
      await file.delete({ ignoreNotFound: true });
      count += 1;
    }
    return count;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.log(`[deletion] verification file cleanup failed for ${uid}: ${message}`);
    return 0;
  }
}

/** Firestore `Timestamp` | Date | ISO string → Date (null when unusable). */
function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === 'string' && value.length > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

/** Module-level guard: only one sweep may run at a time (see below). */
let sweeping = false;

/**
 * Purges every `deletionRequests/{uid}` whose grace period elapsed
 * (`status in ('grace','partial') && purgeAt <= now`). Safe to call from
 * anywhere: a module-level guard makes overlapping runs no-ops, so the
 * 15-minute interval in index.ts and the fire-and-forget kick from
 * `GET /api/account/deletion-status` never double-process a request.
 *
 * The status filter runs as two single-field queries with the `purgeAt`
 * comparison applied here — `status in … AND purgeAt <= …` would need a
 * composite index that may not exist; both populations are tiny anyway.
 */
export async function purgeDueDeletions(overrides: Partial<PurgeDeps> = {}): Promise<PurgeSummary> {
  if (sweeping) return { purged: 0, partial: 0, errors: 0 };
  sweeping = true;
  try {
    const deps: PurgeDeps = { ...defaultPurgeDeps(), ...overrides };
    const db = deps.db();
    const now = deps.now();

    const due: DeletionRequestDoc[] = [];
    for (const status of ['grace', 'partial'] as const) {
      const snap = await db.collection('deletionRequests').where('status', '==', status).get();
      for (const doc of snap.docs) {
        const data = doc.data() as DeletionRequestDoc;
        const purgeAt = toDate(data.purgeAt);
        if (purgeAt === null || purgeAt.getTime() > now.getTime()) continue;
        due.push({ ...data, uid: doc.id });
      }
    }

    const summary: PurgeSummary = { purged: 0, partial: 0, errors: 0 };
    for (const request of due) {
      try {
        const outcome = await purgeSelfService(request, overrides);
        if (outcome === 'purged') summary.purged += 1;
        else summary.partial += 1;
      } catch (err) {
        // Even the `partial` bookkeeping failed (Firestore unavailable?) —
        // counted here and left entirely for the next sweep.
        summary.errors += 1;
        const message = err instanceof Error ? err.message : String(err);
        deps.log(`[deletion] purge failed for ${request.uid}: ${message}`);
      }
    }
    return summary;
  } finally {
    sweeping = false;
  }
}

/**
 * One request's full cascade. EVERY STEP IS IDEMPOTENT — that is what makes
 * `partial → next sweep → retry` safe:
 *   • Auth delete treats "already gone" as success;
 *   • product deactivation re-writes the same `isActive: false`;
 *   • review scrub and order anonymization overwrite the same values;
 *   • document deletes on missing docs are no-ops;
 *   • the request is marked `purged` only after every step finished.
 * Auth is deleted first and the profile last-ish, so a retry can always
 * still find the request + profile while anything remains to do.
 *
 * Order: audit `purge_started` → Auth → products → reviews → orders →
 * IC application/Storage → Supabase → profile + cart/wishlist → request
 * `purged` → audit `purged`. Any throw → `partial` + `lastError` + audit
 * `partial_delete` (or a rethrow when even that bookkeeping fails).
 */
export async function purgeSelfService(
  request: DeletionRequestDoc,
  overrides: Partial<PurgeDeps> = {}
): Promise<'purged' | 'partial'> {
  const deps: PurgeDeps = { ...defaultPurgeDeps(), ...overrides };
  const db = deps.db();
  const uid = request.uid;
  const role = request.role === 'supplier' ? 'supplier' : 'homeowner';
  const counts: Record<string, number | string> = {};
  const metadata: Record<string, unknown> = {};
  const dataTypes: string[] = [];

  try {
    await writeDeletionAudit(db, { uid, role, event: 'purge_started', at: deps.now() });

    // 1. Firebase Auth (idempotent) — the account must stop working before
    //    any data moves.
    await deps.deleteAuth(uid);
    dataTypes.push('firebase_auth');

    // 2. Supplier listings: DEACTIVATED, never deleted (order snapshots).
    let ownedProductIds: string[] = [];
    if (role === 'supplier') {
      ownedProductIds = await deactivateSupplierProducts(db, uid);
      counts.productsDeactivated = ownedProductIds.length;
      dataTypes.push('products_deactivated');
    }

    // 3. The user's orders — one bounded query, reused by the review scrub
    //    below and (homeowners only) anonymized in place afterwards.
    const ordersSnap = await db.collection('orders').where('customerId', '==', uid).get();
    const orderedProductIds = new Set<string>();
    for (const doc of ordersSnap.docs) {
      const items = (doc.get('items') as Array<{ productId?: unknown }> | undefined) ?? [];
      for (const item of items) {
        if (typeof item?.productId === 'string' && item.productId.length > 0) {
          orderedProductIds.add(item.productId);
        }
      }
    }

    // 4. Review scrub — rating/text kept, identity removed. Firestore
    //    cannot query across subcollections, so the product set is BOUNDED:
    //    products this user ordered + products this user sells. Reviews as
    //    a buyer elsewhere always sit on ordered products; a supplier's
    //    own-product scans catch self-reviews. KNOWN LIMITATION (accepted):
    //    a review left on a product they neither ordered nor sell is not
    //    reachable cheaply and is not scrubbed.
    const reviewProductIds = new Set<string>([...orderedProductIds, ...ownedProductIds]);
    let reviewsScrubbed = 0;
    for (const productId of reviewProductIds) {
      const reviews = await db
        .collection('products')
        .doc(productId)
        .collection('reviews')
        .where('userId', '==', uid)
        .get();
      if (reviews.empty) continue;
      const batch = db.batch();
      for (const doc of reviews.docs) {
        batch.update(doc.ref, { userName: 'Deleted user', userId: '' });
        reviewsScrubbed += 1;
      }
      await batch.commit();
    }
    if (reviewsScrubbed > 0) {
      counts.reviewsScrubbed = reviewsScrubbed;
      dataTypes.push('reviews_scrubbed');
    }

    // 5. Orders ANONYMIZED in place, NEVER deleted (financial history).
    //    Plan matrix: homeowner rows only — a supplier's own purchase
    //    history is out of scope for this purge.
    if (role === 'homeowner' && !ordersSnap.empty) {
      const docs = ordersSnap.docs;
      let anonymized = 0;
      for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
        const chunk = docs.slice(i, i + BATCH_LIMIT);
        const batch = db.batch();
        for (const doc of chunk) {
          batch.update(doc.ref, {
            customerName: 'Deleted Customer',
            customerEmail: 'deleted@removed.invalid',
            customerPhone: '',
          });
          anonymized += 1;
        }
        await batch.commit();
      }
      counts.ordersAnonymized = anonymized;
      dataTypes.push('orders_anonymized');
    }

    // 6. Supplier IC application + Storage documents (PII). Deleting the
    //    application doc is idempotent; Storage failures are swallowed and
    //    counted as 0 by the default implementation (see its doc comment).
    if (role === 'supplier') {
      await db.collection('verification_applications').doc(uid).delete();
      counts.verificationFiles = await deps.deleteVerificationFiles(uid);
      dataTypes.push('verification_application', 'verification_files');
    }

    // 7. Supabase `room_designs` — service-role key, server-side only.
    //    Without the key: skipped AND recorded as skipped (audit shows the
    //    gap); `room_designs` then stays out of dataTypes.
    const supabaseBase = deps.supabaseUrl.replace(/\/+$/, '');
    if (supabaseBase.length > 0 && deps.supabaseServiceRoleKey.trim().length > 0) {
      const url = `${supabaseBase}/rest/v1/room_designs?user_id=eq.${encodeURIComponent(uid)}`;
      const headers = {
        Authorization: `Bearer ${deps.supabaseServiceRoleKey}`,
        apikey: deps.supabaseServiceRoleKey,
      };
      // Cheap count first (one small SELECT); fall back to 'deleted'.
      let roomDesigns: number | string = 'deleted';
      try {
        const got = await deps.fetchImpl(`${url}&select=id`, { headers });
        if (got.ok) roomDesigns = ((await got.json()) as unknown[]).length;
      } catch {
        roomDesigns = 'deleted';
      }
      const del = await deps.fetchImpl(url, { method: 'DELETE', headers });
      if (!del.ok) {
        // Thrown → `partial` → retried next sweep; the DELETE itself is
        // idempotent (deleting already-deleted rows just matches nothing).
        throw new Error(`Supabase room_designs delete failed (HTTP ${del.status})`);
      }
      counts.roomDesigns = roomDesigns;
      dataTypes.push('room_designs');
    } else {
      metadata.roomDesigns = 'skipped (no service key)';
    }

    // 8. Profile + per-user subcollections (profile last among the doc
    //    deletes so retries can still find it while data remains).
    await db.collection('users').doc(uid).delete();
    counts.cartItems = await deleteSubcollection(db, uid, 'cart');
    counts.wishlistItems = await deleteSubcollection(db, uid, 'wishlist');
    dataTypes.push('users_profile', 'cart', 'wishlist');

    // 9. The request becomes the tombstone, then the final audit entry.
    await db
      .collection('deletionRequests')
      .doc(uid)
      .set({ status: 'purged', purgedAt: Timestamp.fromDate(deps.now()) }, { merge: true });
    await writeDeletionAudit(db, {
      uid,
      role,
      event: 'purged',
      at: deps.now(),
      dataTypes,
      counts,
      metadata,
    });
    return 'purged';
  } catch (err) {
    const lastError = (err instanceof Error ? err.message : String(err)).slice(0, 300);
    deps.log(`[deletion] purge failed for ${uid}: ${lastError}`);
    try {
      await db
        .collection('deletionRequests')
        .doc(uid)
        .set({ status: 'partial', lastError }, { merge: true });
      await writeDeletionAudit(db, {
        uid,
        role,
        event: 'partial_delete',
        at: deps.now(),
        dataTypes,
        counts,
        metadata: { ...metadata, error: lastError },
      });
    } catch (markErr) {
      const message = markErr instanceof Error ? markErr.message : String(markErr);
      deps.log(`[deletion] could not record partial failure for ${uid}: ${message}`);
      // Even the partial bookkeeping failed — surface it so the sweep counts
      // an error; the next run starts from scratch (all steps idempotent).
      throw err;
    }
    return 'partial';
  }
}
