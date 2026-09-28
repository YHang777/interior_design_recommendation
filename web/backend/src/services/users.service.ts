import type { UserRecord } from 'firebase-admin/auth';
import type { QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors';
import { fbAuth, fbDb, Timestamp } from '../config/firebase';
import type { AdminStats, AdminUserDetail, AdminUserRow, UserRole, VerificationStatus } from '../types/models';

/**
 * Read side of the admin API: merges Firebase Auth accounts with the
 * `users/{uid}` Firestore profiles and attaches cheap product/order counts
 * computed from single field-masked collection scans.
 */

export interface ListUsersQuery {
  role: 'all' | 'homeowner' | 'supplier';
  status?: VerificationStatus;
  q?: string;
  limit: number;
  offset: number;
}

export interface ListUsersResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminUserRow[];
}

/** Every Firebase Auth account, paged through `listUsers`. */
async function loadAuthRecords(): Promise<Map<string, UserRecord>> {
  const map = new Map<string, UserRecord>();
  let pageToken: string | undefined;
  do {
    const page = await fbAuth().listUsers(1000, pageToken);
    for (const u of page.users) map.set(u.uid, u);
    pageToken = page.pageToken;
  } while (pageToken);
  return map;
}

/** Every `users/{uid}` profile document. */
async function loadProfiles(): Promise<Map<string, QueryDocumentSnapshot>> {
  const snap = await fbDb().collection('users').get();
  const map = new Map<string, QueryDocumentSnapshot>();
  for (const doc of snap.docs) map.set(doc.id, doc);
  return map;
}

/**
 * Product & order counts keyed by uid, from ONE scan each (field-masked).
 * - products: top-level `supplierId`, falling back to nested `supplier.id`
 *   for legacy documents (matches `Product.resolvedSupplierId` in the app).
 * - orders: each order counts ONCE per distinct user involved (customer
 *   via `customerId`, suppliers via `supplierIds` entries).
 */
async function loadCounts(): Promise<{ productCounts: Map<string, number>; orderCounts: Map<string, number> }> {
  const productCounts = new Map<string, number>();
  const orderCounts = new Map<string, number>();

  const [prodSnap, orderSnap] = await Promise.all([
    fbDb().collection('products').select('supplierId', 'supplier').get(),
    fbDb().collection('orders').select('customerId', 'supplierIds').get(),
  ]);

  for (const doc of prodSnap.docs) {
    const sid =
      (doc.get('supplierId') as string | undefined) ||
      ((doc.get('supplier') as { id?: string } | undefined)?.id ?? '');
    if (sid) productCounts.set(sid, (productCounts.get(sid) ?? 0) + 1);
  }
  for (const doc of orderSnap.docs) {
    const involved = new Set<string>();
    const cid = (doc.get('customerId') as string | undefined) ?? '';
    if (cid) involved.add(cid);
    for (const sid of (doc.get('supplierIds') as string[] | undefined) ?? []) {
      if (sid) involved.add(sid);
    }
    for (const uid of involved) orderCounts.set(uid, (orderCounts.get(uid) ?? 0) + 1);
  }
  return { productCounts, orderCounts };
}

function toIso(value: unknown): string | null {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string') return value;
  return null;
}

function normalizeRole(raw: unknown): UserRole {
  const role = typeof raw === 'string' ? raw.toLowerCase() : '';
  if (role === 'supplier') return 'supplier';
  if (role === 'homeowner') return 'homeowner';
  return 'unknown';
}

function normalizeStatus(raw: unknown): VerificationStatus | 'unknown' {
  const s = typeof raw === 'string' ? raw.toLowerCase() : '';
  if (s === 'verified' || s === 'pending' || s === 'rejected') return s;
  return 'unknown';
}

/** Merge one Auth record (optional) with one profile doc (optional). */
function buildRow(
  uid: string,
  auth: UserRecord | undefined,
  profile: QueryDocumentSnapshot | undefined,
  productCounts: Map<string, number>,
  orderCounts: Map<string, number>
): AdminUserRow {
  const data = profile?.data() ?? {};
  return {
    uid,
    email: (data.email as string) || auth?.email || '',
    name: (data.name as string) || auth?.displayName || '',
    role: profile ? normalizeRole(data.role) : 'unknown',
    verificationStatus: profile ? normalizeStatus(data.verificationStatus) : 'unknown',
    phone: (data.phone as string) || '',
    businessName: (data.businessName as string) || '',
    businessPhone: (data.businessPhone as string) || '',
    createdAt: toIso(data.createdAt) ?? toIso(auth?.metadata.creationTime) ?? null,
    authCreatedAt: toIso(auth?.metadata.creationTime) ?? null,
    lastSignInAt: toIso(auth?.metadata.lastSignInTime) ?? null,
    emailVerified: auth?.emailVerified ?? false,
    disabled: auth?.disabled ?? false,
    profileExists: Boolean(profile),
    productCount: productCounts.get(uid) ?? 0,
    orderCount: orderCounts.get(uid) ?? 0,
  };
}

export async function listUsers(query: ListUsersQuery): Promise<ListUsersResult> {
  const [authRecords, profiles, { productCounts, orderCounts }] = await Promise.all([
    loadAuthRecords(),
    loadProfiles(),
    loadCounts(),
  ]);

  const rows: AdminUserRow[] = [];
  const seen = new Set<string>();
  for (const [uid, profile] of profiles) {
    rows.push(buildRow(uid, authRecords.get(uid), profile, productCounts, orderCounts));
    seen.add(uid);
  }
  // Auth accounts without a profile document still matter for monitoring.
  for (const [uid, auth] of authRecords) {
    if (!seen.has(uid)) rows.push(buildRow(uid, auth, undefined, productCounts, orderCounts));
  }

  const q = (query.q ?? '').trim().toLowerCase();
  let filtered = rows;
  if (query.role !== 'all') {
    filtered = filtered.filter((r) => r.role === query.role);
  }
  if (query.status) {
    filtered = filtered.filter((r) => r.verificationStatus === query.status);
  }
  if (q) {
    filtered = filtered.filter(
      (r) =>
        r.email.toLowerCase().includes(q) ||
        r.name.toLowerCase().includes(q) ||
        r.businessName.toLowerCase().includes(q) ||
        r.uid.toLowerCase().includes(q)
    );
  }
  filtered.sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));

  return {
    total: filtered.length,
    limit: query.limit,
    offset: query.offset,
    items: filtered.slice(query.offset, query.offset + query.limit),
  };
}

/**
 * Per-user counts for one uid: product docs whose `supplierId` or nested
 * `supplier.id` matches (union of ids, no double count) and order docs
 * where the uid appears as customer or in `supplierIds` (union of ids).
 */
export async function countsForUser(uid: string): Promise<{ productCount: number; orderCount: number }> {
  const [bySupplierId, byNestedSupplier, byCustomer, bySupplierIds] = await Promise.all([
    fbDb().collection('products').where('supplierId', '==', uid).select('supplierId').get(),
    fbDb().collection('products').where('supplier.id', '==', uid).select('supplier').get(),
    fbDb().collection('orders').where('customerId', '==', uid).select('customerId').get(),
    fbDb().collection('orders').where('supplierIds', 'array-contains', uid).select('supplierIds').get(),
  ]);
  const productIds = new Set<string>();
  for (const d of bySupplierId.docs) productIds.add(d.id);
  for (const d of byNestedSupplier.docs) productIds.add(d.id);
  const orderIds = new Set<string>();
  for (const d of byCustomer.docs) orderIds.add(d.id);
  for (const d of bySupplierIds.docs) orderIds.add(d.id);
  return { productCount: productIds.size, orderCount: orderIds.size };
}

export async function getUserDetail(uid: string): Promise<AdminUserDetail> {
  const [auth, profileSnap, counts] = await Promise.all([
    fbAuth()
      .getUser(uid)
      .catch((err: unknown) => {
        if ((err as { code?: string }).code === 'auth/user-not-found') return null;
        throw err;
      }),
    fbDb().collection('users').doc(uid).get(),
    countsForUser(uid),
  ]);
  const profile = profileSnap.exists ? (profileSnap as unknown as QueryDocumentSnapshot) : undefined;
  if (!auth && !profile) {
    throw new ApiError(404, 'USER_NOT_FOUND', `No account found for uid ${uid}.`);
  }

  const data = profile?.data() ?? {};
  return {
    ...buildRow(
      uid,
      auth ?? undefined,
      profile,
      new Map([[uid, counts.productCount]]),
      new Map([[uid, counts.orderCount]])
    ),
    address: (data.address as string) || '',
    profilePicture: (data.profilePicture as string) || '',
    businessAddress: (data.businessAddress as string) || '',
    updatedAt: toIso(data.updatedAt) ?? null,
  };
}

export async function getStats(): Promise<AdminStats> {
  const [profiles, authRecords, productCount, orderCount, pendingApps] = await Promise.all([
    loadProfiles(),
    loadAuthRecords().catch(() => new Map<string, UserRecord>()),
    fbDb().collection('products').count().get(),
    fbDb().collection('orders').count().get(),
    // Suppliers whose IC application is still waiting for a decision.
    fbDb().collection('verification_applications').where('status', '==', 'pending').count().get(),
  ]);

  let customers = 0;
  let suppliers = 0;
  let pendingSuppliers = 0;
  let rejectedSuppliers = 0;
  let unverifiedSuppliers = 0;
  const recent: AdminStats['recentUsers'] = [];

  for (const [, doc] of profiles) {
    const data = doc.data();
    const role = normalizeRole(data.role);
    const status = normalizeStatus(data.verificationStatus);
    if (role === 'homeowner') customers += 1;
    if (role === 'supplier') {
      suppliers += 1;
      if (status === 'pending') pendingSuppliers += 1;
      if (status === 'rejected') rejectedSuppliers += 1;
      if (status !== 'verified') unverifiedSuppliers += 1;
    }
    recent.push({
      uid: doc.id,
      email: (data.email as string) || '',
      name: (data.name as string) || '',
      role,
      verificationStatus: status,
      createdAt: toIso(data.createdAt),
    });
  }
  recent.sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));

  let authOnly = 0;
  for (const uid of authRecords.keys()) {
    if (!profiles.has(uid)) authOnly += 1;
  }

  return {
    customers,
    suppliers,
    authOnlyAccounts: authOnly,
    products: productCount.data().count,
    orders: orderCount.data().count,
    pendingSuppliers,
    rejectedSuppliers,
    unverifiedSuppliers,
    pendingVerifications: pendingApps.data().count,
    recentUsers: recent.slice(0, 5),
  };
}
