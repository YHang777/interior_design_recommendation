import test from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { Timestamp } from 'firebase-admin/firestore';
import { purgeDueDeletions, type PurgeDeps } from './deletion.service';

// ── In-memory Firestore fake (own copy — test files must not import from
//    each other, node --test would execute the imported file twice) ────────

type Doc = Record<string, unknown>;

function getPathField(doc: Doc, field: string): unknown {
  let acc: unknown = doc;
  for (const key of field.split('.')) {
    if (acc === null || typeof acc !== 'object') return undefined;
    acc = (acc as Doc)[key];
  }
  return acc;
}

/** Non-plain values in an update (the `FieldValue.delete()` sentinel) mean
 *  "remove this key", matching how the real SDK treats the transform. */
function isPlainJsonValue(value: unknown): boolean {
  if (value === null || typeof value !== 'object') return true;
  if (Array.isArray(value) || value instanceof Date || value instanceof Timestamp) return true;
  // Plain object → a real nested value. Any other class instance (the
  // `FieldValue.delete()` transform sentinel, for one) → not a value, i.e.
  // "remove this key" — matching how the real SDK treats it.
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

let autoId = 0;

class FakeFirestore {
  readonly store = new Map<string, Map<string, Doc>>();

  collection(path: string): FakeCollection {
    if (!this.store.has(path)) this.store.set(path, new Map());
    return new FakeCollection(this, path);
  }

  batch(): FakeBatch {
    return new FakeBatch(this);
  }

  seed(collectionPath: string, id: string, doc: Doc): void {
    this.applySet(collectionPath, id, doc, false);
  }

  doc(collectionPath: string, id: string): Doc | undefined {
    const found = this.store.get(collectionPath)?.get(id);
    return found === undefined ? undefined : { ...found };
  }

  all(collectionPath: string): Doc[] {
    return [...(this.store.get(collectionPath)?.values() ?? [])].map((d) => ({ ...d }));
  }

  applySet(collectionPath: string, id: string, doc: Doc, merge: boolean): void {
    const col = this.store.get(collectionPath) ?? new Map<string, Doc>();
    this.store.set(collectionPath, col);
    const existing = col.get(id);
    if (merge && existing) Object.assign(existing, doc);
    else col.set(id, { ...doc });
  }

  applyUpdate(collectionPath: string, id: string, patch: Doc): void {
    const target = this.store.get(collectionPath)?.get(id);
    if (!target) throw new Error(`NOT_FOUND: no document at ${collectionPath}/${id}`);
    for (const [key, value] of Object.entries(patch)) {
      if (isPlainJsonValue(value)) target[key] = value;
      else delete target[key];
    }
  }

  applyDelete(collectionPath: string, id: string): void {
    this.store.get(collectionPath)?.delete(id);
  }
}

class FakeCollection {
  constructor(private readonly db: FakeFirestore, readonly path: string) {}

  doc(id: string): FakeDocRef {
    return new FakeDocRef(this.db, this.path, id);
  }

  where(field: string, op: string, value: unknown): FakeQuery {
    assert.equal(op, '==', 'the fake only supports equality filters');
    return new FakeQuery(this.db, this.path, [{ field, value }]);
  }

  limit(_n: number): FakeQuery {
    return new FakeQuery(this.db, this.path, []);
  }

  async add(doc: Doc): Promise<FakeDocRef> {
    const id = `auto_${++autoId}`;
    this.db.applySet(this.path, id, doc, false);
    return this.doc(id);
  }
}

class FakeDocRef {
  constructor(
    private readonly db: FakeFirestore,
    readonly collectionPath: string,
    readonly id: string
  ) {}

  async get(): Promise<FakeDocSnapshot> {
    const data = this.db.store.get(this.collectionPath)?.get(this.id);
    return new FakeDocSnapshot(this.id, this, data === undefined ? undefined : { ...data });
  }

  async set(data: Doc, opts?: { merge?: boolean }): Promise<void> {
    this.db.applySet(this.collectionPath, this.id, data, opts?.merge === true);
  }

  async update(patch: Doc): Promise<void> {
    this.db.applyUpdate(this.collectionPath, this.id, patch);
  }

  async delete(): Promise<void> {
    this.db.applyDelete(this.collectionPath, this.id);
  }

  collection(name: string): FakeCollection {
    return new FakeCollection(this.db, `${this.collectionPath}/${this.id}/${name}`);
  }
}

class FakeDocSnapshot {
  constructor(
    readonly id: string,
    readonly ref: FakeDocRef,
    private readonly data_: Doc | undefined
  ) {}

  get exists(): boolean {
    return this.data_ !== undefined;
  }

  data(): Doc | undefined {
    return this.data_ === undefined ? undefined : { ...this.data_ };
  }

  get(field: string): unknown {
    return this.data_ === undefined ? undefined : getPathField(this.data_, field);
  }
}

class FakeQuery {
  private readonly filters: Array<{ field: string; value: unknown }>;

  constructor(
    private readonly db: FakeFirestore,
    private readonly path: string,
    filters: Array<{ field: string; value: unknown }>
  ) {
    this.filters = filters;
  }

  select(..._fields: string[]): this {
    return this;
  }

  limit(_n: number): this {
    return this; // tests stay far below any limit
  }

  async get(): Promise<{ docs: FakeDocSnapshot[]; empty: boolean; size: number }> {
    const col = this.db.store.get(this.path);
    const docs: FakeDocSnapshot[] = [];
    for (const [id, doc] of col ?? []) {
      if (!this.filters.every((f) => getPathField(doc, f.field) === f.value)) continue;
      docs.push(new FakeDocSnapshot(id, new FakeDocRef(this.db, this.path, id), { ...doc }));
    }
    return { docs, empty: docs.length === 0, size: docs.length };
  }
}

class FakeBatch {
  private readonly ops: Array<() => void> = [];

  constructor(private readonly db: FakeFirestore) {}

  set(ref: FakeDocRef, data: Doc, opts?: { merge?: boolean }): void {
    this.ops.push(() => this.db.applySet(ref.collectionPath, ref.id, data, opts?.merge === true));
  }

  update(ref: FakeDocRef, patch: Doc): void {
    this.ops.push(() => this.db.applyUpdate(ref.collectionPath, ref.id, patch));
  }

  delete(ref: FakeDocRef): void {
    this.ops.push(() => this.db.applyDelete(ref.collectionPath, ref.id));
  }

  async commit(): Promise<void> {
    for (const op of this.ops) op();
  }
}

// ── Fixture helpers ────────────────────────────────────────────────────────

const NOW = new Date('2026-10-05T12:00:00.000Z');
const DUE = new Date('2026-10-01T00:00:00.000Z');
const NOT_YET = new Date('2026-12-01T00:00:00.000Z');

function purgeDeps(fake: FakeFirestore, over: Partial<PurgeDeps> = {}): Partial<PurgeDeps> {
  return {
    db: () => fake as unknown as Firestore,
    deleteAuth: async () => true,
    deleteVerificationFiles: async () => 0,
    // Unconfigured in these tests (overridden where Supabase matters), so
    // the real default fetch must never be reached.
    supabaseUrl: '',
    supabaseServiceRoleKey: '',
    now: () => NOW,
    log: () => {},
    ...over,
  };
}

function graceRequest(uid: string, over: Doc = {}): Doc {
  return {
    uid,
    email: `${uid}@example.com`,
    role: 'homeowner',
    status: 'grace',
    requestedAt: Timestamp.fromDate(new Date('2026-10-01T00:00:00Z')),
    graceUntil: Timestamp.fromDate(DUE),
    purgeAt: Timestamp.fromDate(DUE),
    deactivatedProductIds: [],
    ...over,
  };
}

function seedHomeowner(fake: FakeFirestore): void {
  fake.seed('users', 'u1', { email: 'u1@example.com', role: 'homeowner', name: 'Ann' });
  fake.seed('users/u1/cart', 'c1', { productId: 'p1' });
  fake.seed('users/u1/wishlist', 'w1', { productId: 'p2' });
  fake.seed('orders', 'o1', {
    customerId: 'u1',
    customerName: 'Ann Lee',
    customerEmail: 'ann@example.com',
    customerPhone: '555-0100',
    items: [{ productId: 'p1', qty: 1 }],
  });
  fake.seed('products', 'p1', { name: 'Sofa', isActive: true });
  fake.seed('products', 'p2', { name: 'Lamp', isActive: true });
  fake.seed('products/p1/reviews', 'r1', {
    userId: 'u1',
    userName: 'Ann',
    rating: 5,
    comment: 'love it',
  });
  fake.seed('products/p1/reviews', 'r2', {
    userId: 'u2',
    userName: 'Bob',
    rating: 4,
    comment: 'fine',
  });
  fake.seed('deletionRequests', 'u1', graceRequest('u1'));
}

// ── purgeDueDeletions ──────────────────────────────────────────────────────

test('homeowner purge: anonymize orders, scrub reviews, delete profile, tombstone', async () => {
  const fake = new FakeFirestore();
  seedHomeowner(fake);
  const authCalls: string[] = [];

  const result = await purgeDueDeletions(
    purgeDeps(fake, { deleteAuth: async (uid) => (authCalls.push(uid), true) })
  );
  assert.deepEqual(result, { purged: 1, partial: 0, errors: 0 });
  assert.deepEqual(authCalls, ['u1']);

  // Orders: UPDATED (anonymized) in place — never deleted.
  const order = fake.doc('orders', 'o1');
  assert.ok(order, 'order must not be deleted');
  assert.equal(order.customerName, 'Deleted Customer');
  assert.equal(order.customerEmail, 'deleted@removed.invalid');
  assert.equal(order.customerPhone, '');
  assert.deepEqual(order.items, [{ productId: 'p1', qty: 1 }]);

  // Products: never touched for a homeowner, never deleted.
  assert.equal(fake.doc('products', 'p1')?.isActive, true);
  assert.ok(fake.doc('products', 'p2'));

  // Review scrub: identity removed, rating/text kept; other users untouched.
  const r1 = fake.doc('products/p1/reviews', 'r1');
  assert.ok(r1);
  assert.equal(r1.userName, 'Deleted user');
  assert.equal(r1.userId, '');
  assert.equal(r1.rating, 5);
  assert.equal(r1.comment, 'love it');
  const r2 = fake.doc('products/p1/reviews', 'r2');
  assert.equal(r2?.userName, 'Bob');
  assert.equal(r2?.userId, 'u2');

  // Profile + per-user subcollections gone.
  assert.equal(fake.doc('users', 'u1'), undefined);
  assert.equal(fake.doc('users/u1/cart', 'c1'), undefined);
  assert.equal(fake.doc('users/u1/wishlist', 'w1'), undefined);

  // Request becomes the tombstone.
  const request = fake.doc('deletionRequests', 'u1');
  assert.ok(request);
  assert.equal(request.status, 'purged');
  assert.ok(request.purgedAt instanceof Timestamp);

  // Audits: purge_started then purged, with the documented shapes.
  const audits = fake.all('deletion_audit_logs');
  assert.deepEqual(
    audits.map((a) => a.event),
    ['purge_started', 'purged']
  );
  const purged = audits[1];
  assert.equal(purged.uid, 'u1');
  assert.equal(purged.role, 'homeowner');
  const dataTypes = purged.dataTypes as string[];
  assert.ok(dataTypes.includes('firebase_auth'));
  assert.ok(dataTypes.includes('orders_anonymized'));
  assert.ok(dataTypes.includes('reviews_scrubbed'));
  assert.ok(dataTypes.includes('users_profile'));
  assert.ok(!dataTypes.includes('products_deactivated'), 'homeowner owns no products');
  assert.ok(!dataTypes.includes('room_designs'), 'skipped stays out of dataTypes');
  const counts = purged.counts as Record<string, number>;
  assert.equal(counts.ordersAnonymized, 1);
  assert.equal(counts.reviewsScrubbed, 1);
  assert.equal(counts.cartItems, 1);
  assert.equal(counts.wishlistItems, 1);
  const metadata = purged.metadata as Record<string, unknown>;
  assert.equal(metadata.roomDesigns, 'skipped (no service key)');
});

test('sweep skips requests that are not yet due and non-grace statuses', async () => {
  const fake = new FakeFirestore();
  fake.seed('users', 'u1', { email: 'u1@example.com', role: 'homeowner' });
  fake.seed('deletionRequests', 'u1', graceRequest('u1', { purgeAt: Timestamp.fromDate(NOT_YET) }));
  fake.seed(
    'deletionRequests',
    'u2',
    graceRequest('u2', { status: 'pending_email', purgeAt: Timestamp.fromDate(DUE) })
  );

  const result = await purgeDueDeletions(purgeDeps(fake));
  assert.deepEqual(result, { purged: 0, partial: 0, errors: 0 });
  assert.equal(fake.doc('deletionRequests', 'u1')?.status, 'grace');
  assert.equal(fake.doc('deletionRequests', 'u2')?.status, 'pending_email');
  assert.ok(fake.doc('users', 'u1'), 'not-yet-due profile must survive');
  assert.equal(fake.all('deletion_audit_logs').length, 0);
});

test('supplier purge: deactivate listings, drop IC application, keep supplier orders', async () => {
  const fake = new FakeFirestore();
  fake.seed('users', 'u1', { email: 's@example.com', role: 'supplier', name: 'Supplier Co' });
  fake.seed('products', 'p1', { name: 'Sofa', supplierId: 'u1', isActive: true });
  fake.seed('products', 'p2', { name: 'Chair', supplierId: 'other', isActive: true });
  fake.seed('products/p1/reviews', 'r1', {
    userId: 'u1',
    userName: 'Supplier Co',
    rating: 5,
    comment: 'our own product',
  });
  fake.seed('products/p1/reviews', 'r2', {
    userId: 'u2',
    userName: 'Bob',
    rating: 3,
    comment: 'mediocre',
  });
  fake.seed('orders', 'o1', {
    customerId: 'u1',
    customerName: 'Supplier Co',
    customerEmail: 's@example.com',
    customerPhone: '555-0199',
    items: [{ productId: 'p1', qty: 2 }],
  });
  fake.seed('verification_applications', 'u1', { status: 'approved', legalName: 'Co' });
  fake.seed(
    'deletionRequests',
    'u1',
    graceRequest('u1', { role: 'supplier', deactivatedProductIds: ['p1'] })
  );

  const result = await purgeDueDeletions(
    purgeDeps(fake, {
      deleteVerificationFiles: async () => 3,
    })
  );
  assert.deepEqual(result, { purged: 1, partial: 0, errors: 0 });

  // Products deactivated, never deleted (order snapshots keep resolving).
  const p1 = fake.doc('products', 'p1');
  assert.ok(p1, 'supplier product must not be deleted');
  assert.equal(p1.isActive, false);
  assert.equal(fake.doc('products', 'p2')?.isActive, true); // other supplier untouched

  // Supplier purchase history is NOT anonymized (plan matrix: homeowner rows only).
  const order = fake.doc('orders', 'o1');
  assert.equal(order?.customerName, 'Supplier Co');
  assert.equal(order?.customerEmail, 's@example.com');

  // Self-review scrubbed (owned product), unrelated reviewer untouched.
  const r1 = fake.doc('products/p1/reviews', 'r1');
  assert.equal(r1?.userName, 'Deleted user');
  assert.equal(r1?.userId, '');
  assert.equal(r1?.rating, 5);
  assert.equal(fake.doc('products/p1/reviews', 'r2')?.userName, 'Bob');

  // IC application + Storage count recorded; profile gone; tombstone set.
  assert.equal(fake.doc('verification_applications', 'u1'), undefined);
  assert.equal(fake.doc('users', 'u1'), undefined);
  const request = fake.doc('deletionRequests', 'u1');
  assert.equal(request?.status, 'purged');

  const purged = fake.all('deletion_audit_logs').find((a) => a.event === 'purged');
  assert.ok(purged);
  const counts = purged.counts as Record<string, number | string>;
  assert.equal(counts.productsDeactivated, 1);
  assert.equal(counts.verificationFiles, 3);
  const dataTypes = purged.dataTypes as string[];
  assert.ok(dataTypes.includes('products_deactivated'));
  assert.ok(dataTypes.includes('verification_application'));
  assert.ok(!dataTypes.includes('orders_anonymized'));
});

test('a failing step marks partial with lastError; the next sweep retries to purged', async () => {
  const fake = new FakeFirestore();
  seedHomeowner(fake);
  let failAuth = true;
  const deleteAuth = async (uid: string): Promise<boolean> => {
    if (failAuth) {
      failAuth = false;
      throw new Error('auth backend down');
    }
    void uid;
    return true;
  };

  const first = await purgeDueDeletions(purgeDeps(fake, { deleteAuth }));
  assert.deepEqual(first, { purged: 0, partial: 1, errors: 0 });

  const afterFailure = fake.doc('deletionRequests', 'u1');
  assert.equal(afterFailure?.status, 'partial');
  assert.match(String(afterFailure?.lastError), /auth backend down/);
  // Auth was step 1 — nothing else moved, profile still present for retries.
  assert.ok(fake.doc('users', 'u1'));
  assert.equal(fake.doc('orders', 'o1')?.customerName, 'Ann Lee');

  const events = fake.all('deletion_audit_logs').map((a) => a.event);
  assert.deepEqual(events, ['purge_started', 'partial_delete']);

  // Retry (same idempotent cascade) — `partial` is part of the status query.
  const second = await purgeDueDeletions(purgeDeps(fake, { deleteAuth }));
  assert.deepEqual(second, { purged: 1, partial: 0, errors: 0 });
  assert.equal(fake.doc('deletionRequests', 'u1')?.status, 'purged');
  assert.equal(fake.doc('users', 'u1'), undefined);
  assert.equal(fake.doc('orders', 'o1')?.customerName, 'Deleted Customer');
});

test('Supabase configured: room_designs counted and deleted with the service key', async () => {
  const fake = new FakeFirestore();
  seedHomeowner(fake);
  const calls: Array<{ url: string; init?: RequestInit }> = [];

  const result = await purgeDueDeletions(
    purgeDeps(fake, {
      supabaseUrl: 'https://proj.supabase.co/', // trailing slash — trimmed
      supabaseServiceRoleKey: 'svc-secret',
      fetchImpl: async (input, init) => {
        calls.push({ url: String(input), init });
        if (init?.method === 'DELETE') return new Response(null, { status: 204 });
        return new Response(JSON.stringify([{ id: 'a' }, { id: 'b' }]), { status: 200 });
      },
    })
  );
  assert.deepEqual(result, { purged: 1, partial: 0, errors: 0 });

  assert.equal(calls.length, 2);
  assert.equal(
    calls[0].url,
    'https://proj.supabase.co/rest/v1/room_designs?user_id=eq.u1&select=id'
  );
  assert.equal(calls[1].url, 'https://proj.supabase.co/rest/v1/room_designs?user_id=eq.u1');
  assert.equal(calls[1].init?.method, 'DELETE');
  const headers = calls[0].init?.headers as Record<string, string>;
  assert.equal(headers.Authorization, 'Bearer svc-secret');
  assert.equal(headers.apikey, 'svc-secret');

  const purged = fake.all('deletion_audit_logs').find((a) => a.event === 'purged');
  assert.ok(purged);
  const counts = purged.counts as Record<string, number | string>;
  assert.equal(counts.roomDesigns, 2);
  assert.ok((purged.dataTypes as string[]).includes('room_designs'));
  assert.ok(!('roomDesigns' in (purged.metadata as Record<string, unknown>)));
});
