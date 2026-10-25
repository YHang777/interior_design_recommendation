import { randomInt } from 'node:crypto';
import type { RequestHandler } from 'express';
import type { DocumentReference, Firestore, Transaction } from 'firebase-admin/firestore';
import Stripe from 'stripe';
import { fbDb } from '../config/firebase';
import { env } from '../config/env';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import { getSettings, DEFAULT_TAX_RATE } from './settings.service';

export interface CheckoutItemInput {
  productId: string;
  quantity: number;
}

export interface CheckoutIntentResult {
  orderId: string;
  orderNumber: string;
  clientSecret: string;
  publishableKey: string;
  total: number;
}

export interface PaymentVerificationResult {
  paid: boolean;
  paymentMethod: string;
}

export interface CheckoutDeps {
  createIntent: (
    uid: string,
    email: string | null,
    items: CheckoutItemInput[],
    customerName: string,
    customerPhone: string
  ) => Promise<CheckoutIntentResult>;
  verify: (uid: string, orderId: string) => Promise<PaymentVerificationResult>;
  abandon: (uid: string, orderId: string) => Promise<void>;
  cancel: (uid: string, orderId: string) => Promise<PaymentVerificationResult>;
  handleWebhook: (rawBody: Buffer, signature: string) => Promise<void>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultCheckoutDeps(): CheckoutDeps {
  return {
    createIntent: (uid, email, items, customerName, customerPhone) =>
      createCheckoutIntent(uid, email, items, customerName, customerPhone),
    verify: (uid, orderId) => verifyPayment(uid, orderId),
    abandon: (uid, orderId) => abandonOrder(uid, orderId),
    cancel: (uid, orderId) => cancelOrder(uid, orderId),
    handleWebhook: (rawBody, signature) =>
      handleStripeWebhook(rawBody, signature),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

// ── Stripe client ───────────────────────────────────────────────────────────

let stripeClient: Stripe | null = null;

export function stripeConfigured(): boolean {
  return env.stripeSecretKey.trim().length > 0;
}

function stripe(): Stripe {
  if (!stripeConfigured()) {
    throw new ApiError(
      503,
      'STRIPE_NOT_CONFIGURED',
      'Payments are not configured on this server yet.'
    );
  }
  if (!stripeClient) {
    stripeClient = new Stripe(env.stripeSecretKey.trim());
  }
  return stripeClient;
}

// ── Money math (mirrors lib/core/utils/pricing.dart — integer MYR) ──────────

export interface OrderTotals {
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
}

export function computeTotals(
  subtotal: number,
  discountPercent: number,
  taxRate: number
): OrderTotals {
  const discount = Math.round((subtotal * discountPercent) / 100);
  const chargeable = subtotal - discount;
  const tax = Math.round(chargeable * taxRate);
  return { subtotal, discount, tax, total: chargeable + tax };
}

/** Mirrors the app's `AppConfigData.membershipTiers` constants. */
export const MEMBERSHIP_TIERS = [
  { name: 'Free', discountPercent: 0, minOrders: 0 },
  { name: 'Silver', discountPercent: 5, minOrders: 5 },
  { name: 'Gold', discountPercent: 10, minOrders: 15 },
] as const;

export function tierForOrderCount(collectedCount: number): {
  name: string;
  discountPercent: number;
} {
  let current: { name: string; discountPercent: number; minOrders: number } =
    MEMBERSHIP_TIERS[0];
  for (const tier of MEMBERSHIP_TIERS) {
    if (collectedCount >= tier.minOrders) current = tier;
  }
  return { name: current.name, discountPercent: current.discountPercent };
}

// ── Firestore helpers ───────────────────────────────────────────────────────

interface OrderDoc {
  id: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  customerEmail: string;
  customerPhone: string;
  items: Array<{
    productId: string;
    name: string;
    image: string;
    unitPrice: number;
    quantity: number;
    supplierId: string;
  }>;
  status: string;
  paymentStatus: string;
  paymentMethod: string;
  paymentIntentId?: string;
  paidAt?: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  membershipTier: string;
  supplierIds: string[];
  createdAt: string;
  statusHistory: Record<string, string>;
  invoices: Record<string, unknown>;
  refundStatus?: string;
  refundAmount?: number;
}

function isoNow(): string {
  return new Date().toISOString();
}

function orderNumberFor(now: Date): string {
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  return `ORD-${y}${m}${d}-${randomInt(1000, 10000)}`;
}

function newOrderId(): string {
  return `${Date.now()}${randomInt(0, 99999)}`.slice(0, 20);
}

function asRecord(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function asNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function stockQuantities(items: unknown): Map<string, number> {
  const quantities = new Map<string, number>();
  if (!Array.isArray(items)) return quantities;
  for (const raw of items) {
    const item = asRecord(raw);
    const productId = asString(item.productId);
    if (!productId) continue;
    const quantity = Math.max(1, Math.round(asNumber(item.quantity)));
    quantities.set(productId, (quantities.get(productId) ?? 0) + quantity);
  }
  return quantities;
}

/** All product reads first (Firestore transaction rule), then stock writes. */
async function restoreStock(
  db: Firestore,
  txn: Transaction,
  quantities: Map<string, number>
): Promise<void> {
  const productRefs = [...quantities.keys()].map((id) =>
    db.collection('products').doc(id)
  );
  const snaps = await Promise.all(productRefs.map((ref) => txn.get(ref)));
  for (let i = 0; i < productRefs.length; i++) {
    const snap = snaps[i];
    if (!snap.exists) continue;
    const stock = Math.round(asNumber((snap.data() ?? {}).stock));
    txn.update(productRefs[i], {
      stock: stock + (quantities.get(productRefs[i].id) ?? 0),
    });
  }
}

async function collectedOrderCount(
  db: Firestore,
  uid: string
): Promise<number> {
  const snap = await db.collection('orders').where('customerId', '==', uid).get();
  let count = 0;
  for (const doc of snap.docs) {
    if (doc.data().status === 'collected') count++;
  }
  return count;
}

// ── Payment-state transitions (webhook + verify share one idempotent path) ──

async function markOrderPaid(
  db: Firestore,
  orderId: string,
  paymentIntentId: string,
  paymentMethod: string
): Promise<boolean> {
  const ref = db.collection('orders').doc(orderId);
  return db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return false;
    const data = asRecord(snap.data());
    const current = asString(data.paymentStatus);
    if (current === 'paid' || current === 'refunded') return false;
    txn.update(ref, {
      paymentStatus: 'paid',
      paidAt: isoNow(),
      paymentIntentId,
      ...(paymentMethod ? { paymentMethod } : {}),
    });
    return true;
  });
}

async function paymentIntentState(
  paymentIntentId: string
): Promise<{ state: 'paid' | 'failed' | 'pending'; paymentMethod: string }> {
  const pi = await stripe().paymentIntents.retrieve(paymentIntentId, {
    expand: ['payment_method'],
  });
  if (pi.status === 'succeeded') {
    const method = pi.payment_method;
    const type =
      method && typeof method === 'object' && 'type' in method
        ? String(method.type)
        : '';
    return { state: 'paid', paymentMethod: type === 'fpx' ? 'fpx' : 'card' };
  }
  if (pi.status === 'canceled' || pi.status === 'requires_payment_method') {
    return { state: 'failed', paymentMethod: '' };
  }
  return { state: 'pending', paymentMethod: '' };
}

// ── createCheckoutIntent ────────────────────────────────────────────────────

export async function createCheckoutIntent(
  uid: string,
  email: string | null,
  items: CheckoutItemInput[],
  customerName: string,
  customerPhone: string,
  dbOverride?: Firestore
): Promise<CheckoutIntentResult> {
  const db = dbOverride ?? fbDb();
  const now = new Date();

  await sweepStaleUnpaidOrders(db, uid);

  // Membership tier from the customer's collected orders (server-side truth).
  const tier = tierForOrderCount(await collectedOrderCount(db, uid));
  const settings = await getSettings(db);
  const taxRate = settings.taxRate ?? DEFAULT_TAX_RATE;

  // Validate products + snapshot prices inside one transaction.
  const orderId = newOrderId();
  const prepared = await db.runTransaction(async (txn) => {
    const productRefs = items.map((i) =>
      db.collection('products').doc(i.productId)
    );
    const productSnaps = await Promise.all(productRefs.map((ref) => txn.get(ref)));

    const orderItems: OrderDoc['items'] = [];
    const supplierIds = new Set<string>();
    let subtotal = 0;
    for (let i = 0; i < items.length; i++) {
      const snap = productSnaps[i];
      const wanted = items[i];
      if (!snap.exists) {
        throw new ApiError(409, 'PRODUCT_UNAVAILABLE', 'An item in your cart is no longer available.');
      }
      const product = asRecord(snap.data());
      const name = asString(product.name) || 'Unknown product';
      if (product.isActive !== true) {
        throw new ApiError(409, 'PRODUCT_INACTIVE', `"${name}" is no longer on sale.`);
      }
      const stock = Math.round(asNumber(product.stock));
      if (stock < wanted.quantity) {
        throw new ApiError(
          409,
          'INSUFFICIENT_STOCK',
          stock <= 0
            ? `"${name}" is out of stock.`
            : `Only ${stock} of "${name}" left.`
        );
      }
      const price = Math.round(asNumber(product.price));
      const supplierId = asString(product.supplierId) || asString(asRecord(product.supplier).id);
      subtotal += price * wanted.quantity;
      if (supplierId) supplierIds.add(supplierId);
      orderItems.push({
        productId: snap.id,
        name,
        image: asString(product.image),
        unitPrice: price,
        quantity: wanted.quantity,
        supplierId,
      });
    }

    if (subtotal <= 0) {
      throw new ApiError(400, 'EMPTY_CART', 'Your cart is empty.');
    }

    const totals = computeTotals(subtotal, tier.discountPercent, taxRate);

    // Reserve stock now; released by abandon/sweep if the payment never lands.
    for (let i = 0; i < items.length; i++) {
      const snap = productSnaps[i];
      const stock = Math.round(asNumber((snap.data() ?? {}).stock));
      txn.update(productRefs[i], { stock: stock - items[i].quantity });
    }

    const order: OrderDoc = {
      id: orderId,
      orderNumber: orderNumberFor(now),
      customerId: uid,
      customerName: customerName.trim(),
      customerEmail: email ?? '',
      customerPhone: customerPhone.trim(),
      items: orderItems,
      status: 'pending',
      paymentStatus: 'unpaid',
      paymentMethod: 'card_fpx',
      ...totals,
      membershipTier: tier.name,
      supplierIds: [...supplierIds],
      createdAt: now.toISOString(),
      statusHistory: { pending: now.toISOString() },
      invoices: {},
    };
    txn.set(db.collection('orders').doc(orderId), order);
    return order;
  });

  // PaymentIntent after the order exists; compensate if Stripe refuses.
  let clientSecret: string;
  try {
    const intent = await stripe().paymentIntents.create(
      {
        amount: prepared.total * 100, // integer MYR → sen
        currency: 'myr',
        payment_method_types: ['card', 'fpx'],
        metadata: { orderId },
        ...(prepared.customerEmail ? { receipt_email: prepared.customerEmail } : {}),
      },
      { idempotencyKey: `checkout_${orderId}` }
    );
    clientSecret = intent.client_secret ?? '';
    if (!clientSecret) throw new Error('missing client_secret');
    await db
      .collection('orders')
      .doc(orderId)
      .update({ paymentIntentId: intent.id });
  } catch (err) {
    // Roll the reservation back so a Stripe failure never strands stock.
    await db.runTransaction(async (txn) => {
      const orderRef = db.collection('orders').doc(orderId);
      const snap = await txn.get(orderRef);
      if (snap.exists && asString(snap.data()?.paymentStatus) === 'unpaid') {
        await restoreStock(db, txn, stockQuantities(snap.data()?.items));
        txn.delete(orderRef);
      }
    });
    if (err instanceof ApiError) throw err;
    throw new ApiError(
      502,
      'PAYMENT_PROVIDER_ERROR',
      'Could not start the payment. Please try again.'
    );
  }

  return {
    orderId,
    orderNumber: prepared.orderNumber,
    clientSecret,
    publishableKey: env.stripePublishableKey.trim(),
    total: prepared.total,
  };
}

// ── verify (app polls after the Payment Sheet closes) ───────────────────────

export async function verifyPayment(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<PaymentVerificationResult> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists || asString(snap.data()?.customerId) !== uid) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  const data = asRecord(snap.data());
  const paymentStatus = asString(data.paymentStatus);
  if (paymentStatus === 'paid' || paymentStatus === 'refunded') {
    return { paid: true, paymentMethod: asString(data.paymentMethod) };
  }
  const paymentIntentId = asString(data.paymentIntentId);
  if (!paymentIntentId) return { paid: false, paymentMethod: '' };

  const intent = await paymentIntentState(paymentIntentId);
  if (intent.state === 'paid') {
    await markOrderPaid(db, orderId, paymentIntentId, intent.paymentMethod);
    return { paid: true, paymentMethod: intent.paymentMethod || 'card' };
  }
  return { paid: false, paymentMethod: '' };
}

// ── abandon (user closed/failed the sheet — release the reservation) ────────

export async function abandonOrder(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<void> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = asRecord(snap.data());
  if (asString(data.customerId) !== uid) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  if (asString(data.paymentStatus) !== 'unpaid') return;

  // The sheet can report a close just as the payment lands — Stripe decides.
  const paymentIntentId = asString(data.paymentIntentId);
  if (paymentIntentId) {
    const intent = await paymentIntentState(paymentIntentId);
    if (intent.state === 'paid') {
      await markOrderPaid(db, orderId, paymentIntentId, intent.paymentMethod);
      return;
    }
  }
  await releaseUnpaidOrder(db, ref, data);
}

async function releaseUnpaidOrder(
  db: Firestore,
  ref: DocumentReference,
  data: Record<string, unknown>
): Promise<void> {
  const paymentIntentId = asString(data.paymentIntentId);
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return;
    const current = asRecord(snap.data());
    if (asString(current.paymentStatus) !== 'unpaid') return;
    await restoreStock(db, txn, stockQuantities(current.items));
    txn.delete(ref);
  });
  // Best effort: kill the intent so a stray sheet retry cannot charge later.
  if (paymentIntentId) {
    await stripe()
      .paymentIntents.cancel(paymentIntentId)
      .catch(() => undefined);
  }
}

// ── cancel (after payment — refunds through Stripe, restores stock) ─────────

export async function cancelOrder(
  uid: string,
  orderId: string,
  dbOverride?: Firestore
): Promise<PaymentVerificationResult> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
  }
  const data = asRecord(snap.data());
  const supplierIds = Array.isArray(data.supplierIds)
    ? (data.supplierIds as unknown[]).map((s) => String(s))
    : [];
  if (asString(data.customerId) !== uid && !supplierIds.includes(uid)) {
    throw new ApiError(403, 'FORBIDDEN', 'You cannot cancel this order.');
  }
  const status = asString(data.status);
  if (status === 'cancelled' || status === 'collected') {
    throw new ApiError(409, 'ORDER_NOT_CANCELLABLE', 'This order can no longer be cancelled.');
  }

  const paymentStatus = asString(data.paymentStatus);

  if (paymentStatus === 'paid') {
    // Refund first: stock/status only move once the money is on its way back.
    await refundOrderIfPaid(orderId, db);
  } else if (paymentStatus === 'unpaid') {
    // Never charged — just release the reservation and drop the order.
    await releaseUnpaidOrder(db, ref, data);
    return { paid: false, paymentMethod: '' };
  }

  await db.runTransaction(async (txn) => {
    const orderSnap = await txn.get(ref);
    if (!orderSnap.exists) return;
    const current = asRecord(orderSnap.data());
    if (asString(current.status) === 'cancelled') return;
    await restoreStock(db, txn, stockQuantities(current.items));
    txn.update(ref, {
      status: 'cancelled',
      statusHistory: {
        ...asRecord(current.statusHistory),
        cancelled: isoNow(),
      },
    });
  });

  return { paid: true, paymentMethod: asString(data.paymentMethod) };
}

/**
 * Idempotent Stripe refund for a paid order — shared by the app's cancel
 * endpoint and the admin PATCH cancel path. Returns false when there is
 * nothing to refund (already refunded, unpaid, or predates Stripe).
 */
export async function refundOrderIfPaid(
  orderId: string,
  dbOverride?: Firestore
): Promise<boolean> {
  const db = dbOverride ?? fbDb();
  const ref = db.collection('orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const data = asRecord(snap.data());
  if (asString(data.paymentStatus) !== 'paid') return false;
  const paymentIntentId = asString(data.paymentIntentId);
  if (!paymentIntentId) return false;
  try {
    await stripe().refunds.create({ payment_intent: paymentIntentId });
  } catch (err) {
    const message = (err as { message?: string }).message ?? '';
    if (!message.toLowerCase().includes('already been refunded')) {
      throw new ApiError(
        502,
        'REFUND_FAILED',
        'Could not start the refund. Please contact support.'
      );
    }
  }
  await markRefunded(db, orderId, asNumber(data.total));
  return true;
}

async function markRefunded(db: Firestore, orderId: string, amount: number): Promise<void> {
  const ref = db.collection('orders').doc(orderId);
  await db.runTransaction(async (txn) => {
    const snap = await txn.get(ref);
    if (!snap.exists) return;
    const current = asRecord(snap.data());
    if (asString(current.paymentStatus) === 'refunded') return;
    txn.update(ref, {
      paymentStatus: 'refunded',
      refundStatus: 'processed',
      refundAmount: amount,
    });
  });
}

// ── stale sweep (app killed mid-payment) ────────────────────────────────────

const STALE_UNPAID_MS = 15 * 60 * 1000;

async function sweepStaleUnpaidOrders(db: Firestore, uid: string): Promise<void> {
  const snap = await db.collection('orders').where('customerId', '==', uid).get();
  const cutoff = Date.now() - STALE_UNPAID_MS;
  for (const doc of snap.docs) {
    const data = asRecord(doc.data());
    if (asString(data.paymentStatus) !== 'unpaid') continue;
    if (asString(data.status) !== 'pending') continue;
    const createdAt = Date.parse(asString(data.createdAt));
    if (!Number.isFinite(createdAt) || createdAt > cutoff) continue;

    const paymentIntentId = asString(data.paymentIntentId);
    if (paymentIntentId) {
      // Stripe decides: a payment that just landed must keep its order.
      const intent = await paymentIntentState(paymentIntentId).catch(() => null);
      if (intent?.state === 'paid') {
        await markOrderPaid(db, doc.id, paymentIntentId, intent.paymentMethod);
        continue;
      }
      if (intent?.state === 'pending') continue;
    }
    await releaseUnpaidOrder(db, doc.ref, data);
  }
}

// ── webhook ─────────────────────────────────────────────────────────────────

export async function handleStripeWebhook(
  rawBody: Buffer,
  signature: string,
  dbOverride?: Firestore
): Promise<void> {
  if (!env.stripeWebhookSecret.trim()) {
    throw new ApiError(
      503,
      'WEBHOOK_NOT_CONFIGURED',
      'Webhooks are not configured on this server.'
    );
  }
  let event: Stripe.Event;
  try {
    event = stripe().webhooks.constructEvent(
      rawBody,
      signature,
      env.stripeWebhookSecret.trim()
    );
  } catch {
    throw new ApiError(400, 'BAD_SIGNATURE', 'Invalid webhook signature.');
  }

  const db = dbOverride ?? fbDb();
  if (event.type === 'payment_intent.succeeded') {
    const pi = event.data.object as Stripe.PaymentIntent;
    const orderId = asString(pi.metadata?.orderId);
    if (!orderId) return;
    const method =
      pi.payment_method && typeof pi.payment_method === 'object' && 'type' in pi.payment_method
        ? String((pi.payment_method as Stripe.PaymentMethod).type)
        : '';
    await markOrderPaid(db, orderId, pi.id, method === 'fpx' ? 'fpx' : 'card');
    return;
  }
  // payment_intent.payment_failed is deliberately ignored: the sheet may
  // still be retrying. Cleanup happens via the app's abandon call or sweep.
}
