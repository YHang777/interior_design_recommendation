import test from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { ApiError } from '../lib/errors';
import {
  canTransition,
  nextStatuses,
  normalizeOrderStatus,
  setOrderStatus,
  toOrderDetail,
  toOrderRow,
} from './orders.service';
import type { AdminOrderStatus } from '../types/models';

// ── normalizeOrderStatus ─────────────────────────────────────────────────────

test('status → known values pass through; unknown parses as pending (app parity)', () => {
  assert.equal(normalizeOrderStatus('confirmed'), 'confirmed');
  assert.equal(normalizeOrderStatus('DELIVERED'), 'delivered');
  assert.equal(normalizeOrderStatus('banana'), 'pending');
  assert.equal(normalizeOrderStatus(undefined), 'pending');
  assert.equal(normalizeOrderStatus(42), 'pending');
});

// ── canTransition ────────────────────────────────────────────────────────────

const MATRIX: [AdminOrderStatus, AdminOrderStatus, boolean][] = [
  ['pending', 'confirmed', true],
  ['pending', 'shipped', true],
  ['pending', 'delivered', true],
  ['pending', 'cancelled', true],
  ['confirmed', 'shipped', true],
  ['confirmed', 'delivered', true],
  ['confirmed', 'cancelled', true],
  ['confirmed', 'pending', false],
  ['shipped', 'delivered', true],
  ['shipped', 'cancelled', true],
  ['shipped', 'confirmed', false],
  ['shipped', 'pending', false],
  ['delivered', 'cancelled', false],
  ['delivered', 'shipped', false],
  ['delivered', 'delivered', false],
  ['cancelled', 'pending', false],
  ['cancelled', 'confirmed', false],
  ['cancelled', 'cancelled', false],
  ['pending', 'pending', false],
];

for (const [from, to, ok] of MATRIX) {
  test(`transition → ${from} → ${to} ${ok ? 'allowed' : 'blocked'}`, () => {
    assert.equal(canTransition(from, to), ok);
  });
}

test('nextStatuses → forward skips included; terminal returns none', () => {
  assert.deepEqual(nextStatuses('pending'), ['confirmed', 'shipped', 'delivered']);
  assert.deepEqual(nextStatuses('confirmed'), ['shipped', 'delivered']);
  assert.deepEqual(nextStatuses('shipped'), ['delivered']);
  assert.deepEqual(nextStatuses('delivered'), []);
  assert.deepEqual(nextStatuses('cancelled'), []);
});

// ── toOrderRow / toOrderDetail ───────────────────────────────────────────────

const FULL_ORDER = {
  orderNumber: 'ORD-20261015-1234',
  customerId: 'user-1',
  customerName: 'Aina',
  customerEmail: 'aina@example.com',
  customerPhone: '0123456789',
  shippingAddress: '1 Jalan Test, KL',
  status: 'confirmed',
  paymentMethod: 'fpx',
  subtotal: 1000,
  shippingFee: 25,
  total: 1025,
  discount: 0,
  tax: 60,
  supplierIds: ['seller-1', 'seller-2'],
  shippingBySupplier: { 'seller-1': 25 },
  items: [
    { productId: 'p-1', name: 'Sofa', image: '', unitPrice: 500, quantity: 2, supplierId: 'seller-1' },
  ],
  statusHistory: {
    pending: '2026-10-15T00:00:00.000Z',
    confirmed: '2026-10-15T01:00:00.000Z',
  },
  invoices: { 'seller-1': { invoiceNumber: 'INV-1', total: 500 } },
  createdAt: '2026-10-15T00:00:00.000Z',
};

test('row → a full order doc maps the table columns', () => {
  const row = toOrderRow('ord-1', FULL_ORDER);
  assert.equal(row.orderId, 'ord-1');
  assert.equal(row.orderNumber, 'ORD-20261015-1234');
  assert.equal(row.customerId, 'user-1');
  assert.equal(row.customerName, 'Aina');
  assert.equal(row.status, 'confirmed');
  assert.equal(row.itemCount, 2);
  assert.equal(row.total, 1025);
  assert.equal(row.paymentMethod, 'fpx');
  assert.equal(row.createdAt, '2026-10-15T00:00:00.000Z');
  assert.deepEqual(row.nextStatuses, ['shipped', 'delivered']);
});

test('row → unknown status parses as pending and exposes forward options', () => {
  const row = toOrderRow('ord-2', { ...FULL_ORDER, status: 'weird' });
  assert.equal(row.status, 'pending');
  assert.deepEqual(row.nextStatuses, ['confirmed', 'shipped', 'delivered']);
});

test('detail → items, money, history; invoices surface as supplier ids only', () => {
  const detail = toOrderDetail('ord-1', FULL_ORDER);
  assert.equal(detail.items.length, 1);
  assert.equal(detail.items[0].name, 'Sofa');
  assert.equal(detail.items[0].unitPrice, 500);
  assert.equal(detail.subtotal, 1000);
  assert.equal(detail.shippingFee, 25);
  assert.equal(detail.tax, 60);
  assert.deepEqual(detail.supplierIds, ['seller-1', 'seller-2']);
  assert.equal(detail.statusHistory.confirmed, '2026-10-15T01:00:00.000Z');
  assert.deepEqual(detail.invoiceSupplierIds, ['seller-1']);
  assert.ok(!JSON.stringify(detail).includes('INV-1'));
});

// ── setOrderStatus (FakeFirestore with runTransaction) ───────────────────────

type Doc = Record<string, unknown>;

class FakeTxn {
  private readonly writes: (() => void)[] = [];

  async get(ref: FakeRef): Promise<{ exists: boolean; data(): Doc | undefined }> {
    return ref.get();
  }

  update(ref: FakeRef, patch: Doc): void {
    this.writes.push(() => ref.updateSync(patch));
  }

  flush(): void {
    for (const w of this.writes) w();
  }
}

class FakeRef {
  constructor(private readonly db: FakeDb, readonly path: string, readonly id: string) {}

  async get(): Promise<{ exists: boolean; data(): Doc | undefined }> {
    const data = this.db.docs.get(this.path);
    return { exists: data !== undefined, data: () => (data === undefined ? undefined : { ...data }) };
  }

  async update(patch: Doc): Promise<void> {
    this.updateSync(patch);
  }

  updateSync(patch: Doc): void {
    const target = this.db.docs.get(this.path);
    if (!target) throw new Error(`NOT_FOUND: ${this.path}`);
    Object.assign(target, patch);
  }
}

class FakeDb {
  readonly docs = new Map<string, Doc>();

  seed(path: string, doc: Doc): void {
    this.docs.set(path, { ...doc });
  }

  read(path: string): Doc | undefined {
    const d = this.docs.get(path);
    return d === undefined ? undefined : { ...d };
  }

  collection(name: string) {
    return {
      doc: (id: string) => new FakeRef(this, `${name}/${id}`, id),
    };
  }

  async runTransaction<T>(fn: (txn: FakeTxn) => Promise<T>): Promise<T> {
    const txn = new FakeTxn();
    const result = await fn(txn);
    txn.flush();
    return result;
  }

  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}

function seedPendingOrder(items: Doc[]): FakeDb {
  const db = new FakeDb();
  db.seed('orders/ord-9', {
    orderNumber: 'ORD-1',
    customerId: 'user-1',
    customerName: 'Aina',
    status: 'pending',
    paymentMethod: 'fpx',
    subtotal: 700,
    shippingFee: 25,
    total: 725,
    discount: 0,
    tax: 0,
    supplierIds: ['seller-1'],
    items,
    statusHistory: { pending: '2026-10-15T00:00:00.000Z' },
    invoices: { 'seller-1': { invoiceNumber: 'INV-1' } },
    createdAt: '2026-10-15T00:00:00.000Z',
  });
  return db;
}

test('setStatus → non-cancel leaves items, money and invoices untouched', async () => {
  const db = seedPendingOrder([
    { productId: 'p-1', name: 'Sofa', unitPrice: 500, quantity: 1, supplierId: 'seller-1' },
  ]);
  db.seed('products/p-1', { name: 'Sofa', stock: 9 });

  const detail = await setOrderStatus('ord-9', 'confirmed', db.asFirestore());

  assert.equal(detail.status, 'confirmed');
  assert.equal(detail.total, 725);
  assert.equal(detail.subtotal, 700);
  assert.deepEqual(detail.invoiceSupplierIds, ['seller-1']);
  assert.ok(detail.statusHistory.confirmed);
  // Stock untouched on a non-cancel transition.
  assert.equal(db.read('products/p-1')?.stock, 9);
});

test('setStatus → cancel restores stock, aggregating duplicate lines', async () => {
  const db = seedPendingOrder([
    { productId: 'p-1', name: 'Sofa', unitPrice: 100, quantity: 2, supplierId: 'seller-1' },
    { productId: 'p-1', name: 'Sofa', unitPrice: 100, quantity: 3, supplierId: 'seller-1' },
    { productId: 'p-2', name: 'Lamp', unitPrice: 50, quantity: 1, supplierId: 'seller-2' },
  ]);
  db.seed('products/p-1', { stock: 4 });
  db.seed('products/p-2', { stock: 10 });

  const detail = await setOrderStatus('ord-9', 'cancelled', db.asFirestore());

  assert.equal(detail.status, 'cancelled');
  // 2 + 3 duplicate lines aggregate to 5 — the app's firstWhere only adds 2.
  assert.equal(db.read('products/p-1')?.stock, 9);
  assert.equal(db.read('products/p-2')?.stock, 11);
  assert.ok(detail.statusHistory.cancelled);
  assert.deepEqual(detail.invoiceSupplierIds, ['seller-1']);
});

test('setStatus → cancel skips products deleted since checkout', async () => {
  const db = seedPendingOrder([
    { productId: 'p-gone', name: 'Retired Table', unitPrice: 100, quantity: 1, supplierId: 'seller-1' },
    { productId: 'p-1', name: 'Sofa', unitPrice: 100, quantity: 1, supplierId: 'seller-1' },
  ]);
  db.seed('products/p-1', { stock: 5 });
  // p-gone intentionally absent.

  const detail = await setOrderStatus('ord-9', 'cancelled', db.asFirestore());
  assert.equal(detail.status, 'cancelled');
  assert.equal(db.read('products/p-1')?.stock, 6);
  assert.equal(db.read('products/p-gone'), undefined);
});

test('setStatus → cancel on a terminal order is a 400', async () => {
  const db = seedPendingOrder([]);
  db.docs.set('orders/ord-9', { ...(db.read('orders/ord-9') ?? {}), status: 'delivered' });

  await assert.rejects(
    () => setOrderStatus('ord-9', 'cancelled', db.asFirestore()),
    (err: unknown) => {
      assert.ok(err instanceof ApiError);
      assert.equal(err.statusCode, 400);
      assert.equal(err.code, 'ORDER_INVALID_TRANSITION');
      return true;
    }
  );
});

test('setStatus → missing order is a 404', async () => {
  const db = new FakeDb();
  await assert.rejects(
    () => setOrderStatus('nope', 'confirmed', db.asFirestore()),
    (err: unknown) => {
      assert.ok(err instanceof ApiError);
      assert.equal(err.statusCode, 404);
      assert.equal(err.code, 'ORDER_NOT_FOUND');
      return true;
    }
  );
});
