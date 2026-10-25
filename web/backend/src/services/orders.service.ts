import type { RequestHandler } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { fbDb } from '../config/firebase';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import type {
  AdminOrderDetail,
  AdminOrderItem,
  AdminOrderRow,
  AdminOrderStatus,
  ListOrdersQuery,
  ListOrdersResult,
} from '../types/models';

export interface OrdersDeps {
  list: (query: ListOrdersQuery) => Promise<ListOrdersResult>;
  get: (orderId: string) => Promise<AdminOrderDetail>;
  setStatus: (orderId: string, status: AdminOrderStatus) => Promise<AdminOrderDetail>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultOrdersDeps(): OrdersDeps {
  return {
    list: (query) => listOrders(query),
    get: (orderId) => getOrderDetail(orderId),
    setStatus: (orderId, status) => setOrderStatus(orderId, status),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

const STATUSES: AdminOrderStatus[] = [
  'pending',
  'confirmed',
  'waitingCollection',
  'collected',
  'cancelled',
];
const RANK: Record<AdminOrderStatus, number> = {
  pending: 0,
  confirmed: 1,
  waitingCollection: 2,
  collected: 3,
  cancelled: 99,
};

export function normalizeOrderStatus(raw: unknown): AdminOrderStatus {
  const s = typeof raw === 'string' ? raw.toLowerCase() : '';
  // Case-insensitive match — 'waitingCollection' is camelCase, so a plain
  // toLowerCase() compare against STATUSES would never hit it.
  const match = STATUSES.find((t) => t.toLowerCase() === s);
  if (match) return match;
  // Legacy delivery-era statuses keep their place in the collection chain.
  if (s === 'shipped') return 'waitingCollection';
  if (s === 'delivered') return 'collected';
  return 'pending';
}

function isTerminal(status: AdminOrderStatus): boolean {
  return status === 'collected' || status === 'cancelled';
}

/**
 * Admin transitions may skip steps forward (pending → collected); the app's
 * single-step ensureAdvance stays as-is for customer/supplier flows.
 */
export function canTransition(from: AdminOrderStatus, to: AdminOrderStatus): boolean {
  if (from === to) return false;
  if (isTerminal(from)) return false;
  if (to === 'cancelled') return true;
  return RANK[to] > RANK[from];
}

/** Forward statuses from `from` (skips included; empty when terminal). */
export function nextStatuses(from: AdminOrderStatus): AdminOrderStatus[] {
  if (isTerminal(from)) return [];
  if (from === 'cancelled') return [];
  return STATUSES.filter((s) => s !== 'cancelled' && canTransition(from, s));
}

function toIso(value: unknown): string | null {
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string' && value) return value;
  return null;
}

function asRecord(data: Record<string, unknown> | undefined): Record<string, unknown> {
  return data ?? {};
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function asNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function toItem(raw: unknown): AdminOrderItem | null {
  if (!raw || typeof raw !== 'object') return null;
  const d = raw as Record<string, unknown>;
  return {
    productId: asString(d.productId),
    name: asString(d.name) || 'Unknown product',
    image: asString(d.image),
    unitPrice: Math.round(asNumber(d.unitPrice)),
    quantity: Math.max(1, Math.round(asNumber(d.quantity))),
    supplierId: asString(d.supplierId),
  };
}

function statusHistoryIso(raw: unknown): Record<string, string> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const iso = toIso(value);
    if (iso) out[key] = iso;
  }
  return out;
}

/** orders/{id} → table row. */
export function toOrderRow(orderId: string, raw: Record<string, unknown>): AdminOrderRow {
  const data = asRecord(raw);
  const items = Array.isArray(data.items) ? data.items : [];
  const itemCount = items.reduce((sum, it) => sum + Math.max(1, Math.round(asNumber((it as Record<string, unknown>)?.quantity))), 0);
  const status = normalizeOrderStatus(data.status);
  return {
    orderId,
    orderNumber: asString(data.orderNumber),
    customerId: asString(data.customerId),
    customerName: asString(data.customerName),
    status,
    itemCount,
    total: Math.round(asNumber(data.total)),
    paymentMethod: asString(data.paymentMethod),
    createdAt: toIso(data.createdAt),
    nextStatuses: nextStatuses(status),
  };
}

/** orders/{id} → detail row (adds items, money, history; invoices = ids). */
export function toOrderDetail(orderId: string, raw: Record<string, unknown>): AdminOrderDetail {
  const data = asRecord(raw);
  const items = (Array.isArray(data.items) ? data.items : [])
    .map(toItem)
    .filter((i): i is AdminOrderItem => i !== null);
  const invoices = (data.invoices ?? {}) as Record<string, unknown>;
  const supplierIds = Array.isArray(data.supplierIds)
    ? (data.supplierIds as unknown[]).filter((s): s is string => typeof s === 'string' && s.length > 0)
    : [];
  return {
    ...toOrderRow(orderId, data),
    customerEmail: asString(data.customerEmail),
    customerPhone: asString(data.customerPhone),
    paymentStatus: asString(data.paymentStatus) || 'paid',
    paymentIntentId: asString(data.paymentIntentId),
    paidAt: toIso(data.paidAt),
    refundStatus: data.refundStatus == null ? null : asString(data.refundStatus),
    refundAmount:
      data.refundAmount == null ? null : Math.round(asNumber(data.refundAmount)),
    items,
    subtotal: Math.round(asNumber(data.subtotal)),
    discount: Math.round(asNumber(data.discount)),
    tax: Math.round(asNumber(data.tax)),
    supplierIds,
    statusHistory: statusHistoryIso(data.statusHistory),
    invoiceSupplierIds: Object.keys(invoices),
  };
}

export async function listOrders(query: ListOrdersQuery): Promise<ListOrdersResult> {
  const snap = await fbDb().collection('orders').get();
  let rows = snap.docs.map((doc) => toOrderRow(doc.id, doc.data()));

  if (query.status) {
    rows = rows.filter((r) => r.status === query.status);
  }
  const q = (query.q ?? '').trim().toLowerCase();
  if (q) {
    rows = rows.filter(
      (r) =>
        r.orderNumber.toLowerCase().includes(q) ||
        r.customerName.toLowerCase().includes(q) ||
        r.customerId.toLowerCase().includes(q) ||
        r.orderId.toLowerCase().includes(q)
    );
  }
  rows.sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));

  return {
    total: rows.length,
    limit: query.limit,
    offset: query.offset,
    items: rows.slice(query.offset, query.offset + query.limit),
  };
}

export async function getOrderDetail(orderId: string): Promise<AdminOrderDetail> {
  const snap = await fbDb().collection('orders').doc(orderId).get();
  if (!snap.exists) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  return toOrderDetail(orderId, snap.data() ?? {});
}

export async function setOrderStatus(
  orderId: string,
  status: AdminOrderStatus,
  dbOverride?: Firestore
): Promise<AdminOrderDetail> {
  const db = dbOverride ?? fbDb();
  const orderRef = db.collection('orders').doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  const current = normalizeOrderStatus((snap.data() ?? {}).status);
  if (!canTransition(current, status)) {
    throw new ApiError(
      400,
      'ORDER_INVALID_TRANSITION',
      `An order that is ${current} cannot become ${status}.`
    );
  }

  const nowIso = new Date().toISOString();
  const history = statusHistoryIso((snap.data() ?? {}).statusHistory);
  history[status] = nowIso;

  if (status === 'cancelled' && asString((snap.data() ?? {}).paymentStatus) === 'paid') {
    // Real money: the refund must land before stock/status move.
    const { refundOrderIfPaid } = await import('./checkout.service');
    await refundOrderIfPaid(orderId, db);
  }

  if (status !== 'cancelled') {
    // Field-level update: items, money and invoices survive by construction.
    await orderRef.update({ status, statusHistory: history });
    const after = await orderRef.get();
    return toOrderDetail(orderId, after.data() ?? {});
  }

  // Cancel: restore stock inside a transaction — aggregate duplicate lines
  // (the app's cancelOrder uses firstWhere and under-restores those), skip
  // deleted products, then flip the order. Never set() the order document.
  const items = (Array.isArray((snap.data() ?? {}).items) ? (snap.data()!.items as unknown[]) : [])
    .map(toItem)
    .filter((i): i is AdminOrderItem => i !== null);
  const quantities = new Map<string, number>();
  for (const item of items) {
    if (!item.productId) continue;
    quantities.set(item.productId, (quantities.get(item.productId) ?? 0) + item.quantity);
  }

  await db.runTransaction(async (txn) => {
    const productRefs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
    // All reads before any write — Firestore transaction rule.
    const productSnaps = await Promise.all(productRefs.map((ref) => txn.get(ref)));
    for (let i = 0; i < productRefs.length; i++) {
      const ps = productSnaps[i];
      if (!ps.exists) continue;
      const productId = productRefs[i].id;
      const stock = Math.round(asNumber((ps.data() ?? {}).stock));
      txn.update(productRefs[i], { stock: stock + (quantities.get(productId) ?? 0) });
    }
    txn.update(orderRef, { status, statusHistory: history });
  });

  const after = await orderRef.get();
  return toOrderDetail(orderId, after.data() ?? {});
}
