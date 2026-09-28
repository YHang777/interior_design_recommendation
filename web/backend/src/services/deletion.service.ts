import { ApiError } from '../lib/errors';
import { fbDb } from '../config/firebase';
import { deleteAuthUser, getAuthUserOrNull } from './identity.service';

/**
 * Account deletion — the most dangerous admin action, so it is built to be
 * hard to trigger accidentally and safe to RETRY after a partial failure.
 *
 * Order of operations:
 *   1. Verify the typed confirmation email matches the target account
 *      (case-insensitive) — callers must pass it from the UI's
 *      type-to-confirm dialog.
 *   2. Refuse self-deletion.
 *   3. Delete the Firebase Auth account (`auth.deleteUser`).
 *   4. Firestore cleanup in risk order: supplier listings DEACTIVATED
 *      (`products/{id}.isActive = false`, never deleted so historical
 *      orders keep resolving their snapshots), then `users/{uid}` itself,
 *      then its `cart/` and `wishlist/` subcollections. `orders/`
 *      documents are never deleted (financial history).
 *
 * If step 3 succeeds but step 4 fails, a PARTIAL_DELETE error is thrown
 * that says exactly what happened. Re-running the same DELETE is safe:
 * a missing Auth record is treated as "already deleted" and the Firestore
 * cleanup is retried.
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
      productsDeactivated = await deactivateSupplierProducts(db, uid);
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

/** Deactivates (never deletes) a supplier's listings. Returns count. */
async function deactivateSupplierProducts(db: ReturnType<typeof fbDb>, uid: string): Promise<number> {
  const productIds = new Set<string>();
  const [bySupplierId, byNestedSupplier] = await Promise.all([
    db.collection('products').where('supplierId', '==', uid).select('supplierId').get(),
    db.collection('products').where('supplier.id', '==', uid).select('supplier').get(),
  ]);
  for (const doc of bySupplierId.docs) productIds.add(doc.id);
  for (const doc of byNestedSupplier.docs) productIds.add(doc.id);

  const ids = [...productIds];
  let count = 0;
  for (let i = 0; i < ids.length; i += BATCH_LIMIT) {
    const chunk = ids.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const id of chunk) {
      batch.update(db.collection('products').doc(id), { isActive: false });
      count += 1;
    }
    await batch.commit();
  }
  return count;
}
