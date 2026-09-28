import { ApiError } from '../lib/errors';
import { fbDb, FieldValue } from '../config/firebase';
import type { VerificationStatus } from '../types/models';

/**
 * Supplier verification (approve / reject / return to pending).
 *
 * MUTATES these Firestore fields — both of which already exist in the
 * Flutter app's schema (no new fields are introduced):
 *
 *   1. users/{uid}.verificationStatus  — the app's AppUser.verificationStatus
 *      ('verified' | 'pending' | 'rejected'), written at registration by
 *      lib/features/auth/data/repositories/auth_repository_impl.dart.
 *
 *   2. products/{id}.supplier.verificationStatus — the EMBEDDED supplier
 *      snapshot on each of the supplier's listings. The buyer marketplace's
 *      "Verified sellers only" filter (default ON) reads
 *      `p.supplier.isVerified` from this embedded copy
 *      (lib/features/customer/marketplace/.../marketplace_providers.dart),
 *      so BOTH must be updated for an approval/rejection to be visible
 *      in the app.
 *
 * Product lookup matches both the top-level `supplierId` field and the
 * nested `supplier.id` (legacy docs written before the top-level field
 * existed — see Product.resolvedSupplierId).
 */
export interface VerificationResult {
  uid: string;
  verificationStatus: VerificationStatus;
  productsSynced: number;
}

const BATCH_LIMIT = 400; // Firestore batch cap is 500 — leave headroom.

export async function setSupplierVerification(
  uid: string,
  status: VerificationStatus
): Promise<VerificationResult> {
  const db = fbDb();
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    throw new ApiError(404, 'USER_NOT_FOUND', `No profile document for uid ${uid}.`);
  }
  const role = userSnap.get('role');
  if (role !== 'supplier') {
    throw new ApiError(
      400,
      'NOT_SUPPLIER',
      'Verification status applies only to supplier accounts (users/{uid}.role == "supplier").'
    );
  }

  // 1. The canonical profile field.
  await userRef.update({
    verificationStatus: status,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // 2. The embedded snapshot on every product the supplier owns.
  const productIds = new Set<string>();
  const [bySupplierId, byNestedSupplier] = await Promise.all([
    db.collection('products').where('supplierId', '==', uid).select('supplierId').get(),
    db.collection('products').where('supplier.id', '==', uid).select('supplier').get(),
  ]);
  for (const doc of bySupplierId.docs) productIds.add(doc.id);
  for (const doc of byNestedSupplier.docs) productIds.add(doc.id);

  let productsSynced = 0;
  const ids = [...productIds];
  for (let i = 0; i < ids.length; i += BATCH_LIMIT) {
    const chunk = ids.slice(i, i + BATCH_LIMIT);
    const snaps = await Promise.all(chunk.map((id) => db.collection('products').doc(id).get()));
    const batch = db.batch();
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const existing = (snap.get('supplier') as Record<string, unknown> | undefined) ?? {};
      batch.update(snap.ref, {
        supplier: { ...existing, id: (existing.id as string) || uid, verificationStatus: status },
      });
      productsSynced += 1;
    }
    await batch.commit();
  }

  return { uid, verificationStatus: status, productsSynced };
}
