import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import type { Firestore } from 'firebase-admin/firestore';
import { Timestamp } from 'firebase-admin/firestore';
import {
  createAccountDeletionRouter,
  createDeletionConfirmRouter,
  type AccountDeletionDeps,
} from './account-deletion.routes';
import { createVerifyEmailRouter } from './verify-email.routes';
import { ApiError } from '../lib/errors';
import { errorHandler } from '../middleware/errorHandler';
import { VerificationEmailException, VerificationMailer } from '../lib/verification-mailer';
import { createVerificationToken, verifyVerificationToken } from '../lib/verification-token';

// ── In-memory Firestore fake (only the surface these routes touch) ────────

type Doc = Record<string, unknown>;

function getPathField(doc: Doc, field: string): unknown {
  let acc: unknown = doc;
  for (const key of field.split('.')) {
    if (acc === null || typeof acc !== 'object') return undefined;
    acc = (acc as Doc)[key];
  }
  return acc;
}

/**
 * Values a Firestore `update` understands directly. Anything else (the
 * `FieldValue.delete()` sentinel, for instance) means "remove this key" —
 * which is exactly how the real SDK treats the transform.
 */
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

  /** Test helper: write a document verbatim. */
  seed(collectionPath: string, id: string, doc: Doc): void {
    this.applySet(collectionPath, id, doc, false);
  }

  /** Test helper: read a document (copy) — undefined when absent. */
  doc(collectionPath: string, id: string): Doc | undefined {
    const found = this.store.get(collectionPath)?.get(id);
    return found === undefined ? undefined : { ...found };
  }

  /** Test helper: every document in a collection. */
  all(collectionPath: string): Doc[] {
    return [...(this.store.get(collectionPath)?.values() ?? [])].map((d) => ({ ...d }));
  }

  applySet(collectionPath: string, id: string, doc: Doc, merge: boolean): void {
    const col = this.store.get(collectionPath) ?? new Map<string, Doc>();
    this.store.set(collectionPath, col);
    const existing = col.get(id);
    if (merge && existing) {
      Object.assign(existing, doc);
    } else {
      col.set(id, { ...doc });
    }
  }

  applyUpdate(collectionPath: string, id: string, patch: Doc): void {
    const target = this.store.get(collectionPath)?.get(id);
    if (!target) throw new Error(`NOT_FOUND: no document at ${collectionPath}/${id}`);
    for (const [key, value] of Object.entries(patch)) {
      if (isPlainJsonValue(value)) target[key] = value;
      else delete target[key]; // FieldValue transform (delete)
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
  constructor(
    private readonly db: FakeFirestore,
    private readonly path: string,
    private readonly filters: Array<{ field: string; value: unknown }>
  ) {}

  select(..._fields: string[]): this {
    return this;
  }

  limit(_n: number): this {
    return this; // tests stay well under any limit
  }

  async get(): Promise<{ docs: FakeDocSnapshot[]; empty: boolean; size: number }> {
    const col = this.db.store.get(this.path);
    const docs: FakeDocSnapshot[] = [];
    for (const [id, doc] of col ?? []) {
      const matches = this.filters.every((f) => getPathField(doc, f.field) === f.value);
      if (!matches) continue;
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

// ── Harness ────────────────────────────────────────────────────────────────

interface CapturedMail {
  email: string;
  token: string;
  baseUrlOverride?: string;
}

interface StartOpts {
  deps?: Partial<AccountDeletionDeps>;
  /** false → authorize rejects like the real middleware (401). */
  authed?: boolean;
  uid?: string;
  email?: string;
  seed?: (fake: FakeFirestore) => void;
}

interface Harness {
  base: string;
  fake: FakeFirestore;
  mails: CapturedMail[];
  sweepCount: () => number;
  close: () => Promise<void>;
}

async function listen(app: express.Express): Promise<{ base: string; close: () => Promise<void> }> {
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return {
    base: `http://127.0.0.1:${port}`,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

async function start(opts: StartOpts = {}): Promise<Harness> {
  const fake = new FakeFirestore();
  opts.seed?.(fake);

  const mails: CapturedMail[] = [];
  let sweeps = 0;
  const uid = opts.uid ?? 'u1';
  const email = opts.email ?? 'user@example.com';

  const authorize: RequestHandler =
    opts.authed === false
      ? (_req, _res, next) => next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'))
      : (req, _res, next) => {
          req.user = { uid, email, name: null, adminClaim: false };
          next();
        };

  const deps: AccountDeletionDeps = {
    tokenSecret: 'test-secret',
    mailer: {
      isConfigured: true,
      sendDeletionEmail: async (args) => {
        mails.push({ ...args });
      },
    },
    authorize,
    db: () => fake as unknown as Firestore,
    getAuthEmail: async () => null,
    sweep: async () => {
      sweeps += 1;
      return { purged: 0, partial: 0, errors: 0 };
    },
    log: () => {},
    ...opts.deps,
  };

  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/account', createAccountDeletionRouter(deps));
  app.use('/account/delete', createDeletionConfirmRouter(deps));
  app.use(errorHandler);

  const { base, close } = await listen(app);
  return { base, fake, mails, sweepCount: () => sweeps, close };
}

function post(base: string, path: string, body: unknown): Promise<Response> {
  return fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer fake-token' },
    body: JSON.stringify(body),
  });
}

function get(base: string, path: string): Promise<Response> {
  return fetch(`${base}${path}`, { headers: { Authorization: 'Bearer fake-token' } });
}

const profile = (over: Doc = {}): Doc => ({
  email: 'user@example.com',
  role: 'homeowner',
  name: 'Ann',
  ...over,
});

const pendingRequest = (over: Doc = {}): Doc => ({
  uid: 'u1',
  email: 'user@example.com',
  role: 'homeowner',
  status: 'pending_email',
  requestedAt: Timestamp.fromDate(new Date('2026-10-01T00:00:00Z')),
  deactivatedProductIds: [],
  ...over,
});

// ── POST /api/account/deletion-request ─────────────────────────────────────

test('request → 200 pending_email, writes the request, mails an account_delete token', async () => {
  const h = await start({ seed: (f) => f.seed('users', 'u1', profile()) });
  try {
    // Case-insensitive + trimmed match (same rule as admin deleteAccount).
    const res = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: '  USER@Example.com ',
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as { status: string; expiresAt: string };
    assert.equal(body.status, 'pending_email');
    // ~24h from now (the token TTL the plan freezes).
    const expiresInHours = (new Date(body.expiresAt).getTime() - Date.now()) / 3_600_000;
    assert.ok(expiresInHours > 23 && expiresInHours < 25, `expiresInHours=${expiresInHours}`);

    const doc = h.fake.doc('deletionRequests', 'u1');
    assert.ok(doc);
    assert.equal(doc.status, 'pending_email');
    assert.equal(doc.email, 'user@example.com');
    assert.equal(doc.role, 'homeowner');
    assert.deepEqual(doc.deactivatedProductIds, []);

    assert.equal(h.mails.length, 1);
    assert.equal(h.mails[0].email, 'user@example.com');
    const payload = verifyVerificationToken(h.mails[0].token, 'test-secret');
    assert.ok(payload !== null);
    assert.equal(payload.purpose, 'account_delete');

    const audit = h.fake.all('deletion_audit_logs');
    assert.equal(audit.length, 1);
    assert.equal(audit[0].event, 'requested');
    assert.equal(audit[0].uid, 'u1');
  } finally {
    await h.close();
  }
});

test('request → 400 CONFIRM_MISMATCH when the typed email differs', async () => {
  const h = await start({ seed: (f) => f.seed('users', 'u1', profile()) });
  try {
    const res = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: 'not-my@email.com',
    });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string; message: string } };
    assert.equal(body.error.code, 'CONFIRM_MISMATCH');
    // Nothing was written and no mail went out.
    assert.equal(h.fake.doc('deletionRequests', 'u1'), undefined);
    assert.equal(h.mails.length, 0);
  } finally {
    await h.close();
  }
});

test('request → 409 with the current status while pending/grace', async () => {
  const graceUntil = new Date('2026-10-12T00:00:00Z');

  const pendingHarness = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile());
      f.seed('deletionRequests', 'u1', pendingRequest());
    },
  });
  try {
    const pending = await post(pendingHarness.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(pending.status, 409);
    assert.deepEqual(await pending.json(), { status: 'pending_email' });
    assert.equal(pendingHarness.mails.length, 0);
  } finally {
    await pendingHarness.close();
  }

  const graceHarness = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile());
      f.seed('deletionRequests', 'u1', pendingRequest({
        status: 'grace',
        graceUntil: Timestamp.fromDate(graceUntil),
        purgeAt: Timestamp.fromDate(graceUntil),
      }));
    },
  });
  try {
    const grace = await post(graceHarness.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(grace.status, 409);
    const body = (await grace.json()) as { status: string; graceUntil?: string };
    assert.equal(body.status, 'grace');
    assert.equal(body.graceUntil, graceUntil.toISOString());
    assert.equal(graceHarness.mails.length, 0);
  } finally {
    await graceHarness.close();
  }
});

test('request → 503 when the flow is not configured', async () => {
  const h = await start({ deps: { tokenSecret: '' } });
  try {
    const res = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(res.status, 503);
    const body = (await res.json()) as { error: string };
    assert.equal(body.error, 'Account deletion is not configured.');
  } finally {
    await h.close();
  }
});

test('request → 502 on mail failure, rolls back, and a retry succeeds', async () => {
  let failNext = true;
  const tokens: string[] = [];
  const h = await start({
    seed: (f) => f.seed('users', 'u1', profile()),
    deps: {
      mailer: {
        isConfigured: true,
        sendDeletionEmail: async (args) => {
          if (failNext) {
            failNext = false;
            throw new VerificationEmailException('Brevo HTTP 500: boom');
          }
          tokens.push(args.token);
        },
      },
    },
  });
  try {
    const first = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(first.status, 502);
    const body = (await first.json()) as { error: string };
    assert.equal(body.error, 'Could not send the confirmation email. Please try again.');
    // Exception detail never leaks.
    assert.ok(!JSON.stringify(body).includes('Brevo HTTP 500'));
    // Rolled back → not stranded behind a 409.
    assert.equal(h.fake.doc('deletionRequests', 'u1'), undefined);

    const second = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(second.status, 200);
    assert.equal(tokens.length, 1);
    assert.equal(h.fake.doc('deletionRequests', 'u1')?.status, 'pending_email');
  } finally {
    await h.close();
  }
});

test('request → 401 without a valid session', async () => {
  const h = await start({ authed: false });
  try {
    const res = await post(h.base, '/api/account/deletion-request', {
      confirmEmail: 'user@example.com',
    });
    assert.equal(res.status, 401);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'UNAUTHENTICATED');
  } finally {
    await h.close();
  }
});

// ── GET /account/delete/confirm ────────────────────────────────────────────

test('confirm → success HTML, request goes to grace with the users mirror', async () => {
  const h = await start({ seed: (f) => f.seed('users', 'u1', profile()) });
  try {
    await post(h.base, '/api/account/deletion-request', { confirmEmail: 'user@example.com' });
    assert.equal(h.mails.length, 1);
    const token = h.mails[0].token;

    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') ?? '', /html/);
    const text = await res.text();
    assert.ok(text.includes('Deletion scheduled'));
    assert.ok(text.includes('7 days to recover'));
    assert.ok(text.includes('Sign in'));

    const req = h.fake.doc('deletionRequests', 'u1');
    assert.ok(req);
    assert.equal(req.status, 'grace');
    const graceUntil = req.graceUntil as Timestamp;
    const purgeAt = req.purgeAt as Timestamp;
    assert.ok(graceUntil instanceof Timestamp);
    assert.equal(graceUntil.toDate().getTime(), purgeAt.toDate().getTime());
    const days = (graceUntil.toDate().getTime() - Date.now()) / 86_400_000;
    assert.ok(days > 6.9 && days < 7.1, `days=${days}`);
    assert.ok(req.emailConfirmedAt instanceof Timestamp);

    const mirror = h.fake.doc('users', 'u1');
    assert.ok(mirror);
    const deletion = mirror.deletion as { status: string; purgeAt: Timestamp };
    assert.equal(deletion.status, 'grace');
    assert.ok(deletion.purgeAt instanceof Timestamp);

    const events = h.fake.all('deletion_audit_logs').map((d) => d.event);
    assert.ok(events.includes('requested'));
    assert.ok(events.includes('email_confirmed'));
  } finally {
    await h.close();
  }
});

test('confirm → an expired token renders the invalid page and changes nothing', async () => {
  const h = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile());
      f.seed('deletionRequests', 'u1', pendingRequest());
    },
  });
  try {
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
      ttlSeconds: -60,
      purpose: 'account_delete',
    });
    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('Deletion link invalid'));
    assert.ok(text.includes('invalid or has expired'));
    assert.equal(h.fake.doc('deletionRequests', 'u1')?.status, 'pending_email');
  } finally {
    await h.close();
  }
});

test('confirm → a wrong-purpose (email_verify) token is rejected', async () => {
  const h = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile());
      f.seed('deletionRequests', 'u1', pendingRequest());
    },
  });
  try {
    // Legacy / verification token: no purpose field → email_verify.
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
    });
    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    const text = await res.text();
    assert.ok(text.includes('Deletion link invalid'));
    assert.equal(h.fake.doc('deletionRequests', 'u1')?.status, 'pending_email');
  } finally {
    await h.close();
  }
});

test('confirm → idempotent: an already-grace request re-renders the same page', async () => {
  const graceUntil = new Date('2026-10-12T00:00:00Z');
  const h = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile());
      f.seed(
        'deletionRequests',
        'u1',
        pendingRequest({
          status: 'grace',
          emailConfirmedAt: Timestamp.fromDate(new Date('2026-10-05T00:00:00Z')),
          graceUntil: Timestamp.fromDate(graceUntil),
          purgeAt: Timestamp.fromDate(graceUntil),
        })
      );
    },
  });
  try {
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
      purpose: 'account_delete',
    });
    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('Deletion scheduled'));
    // graceUntil untouched.
    const req = h.fake.doc('deletionRequests', 'u1');
    assert.equal((req?.graceUntil as Timestamp).toDate().toISOString(), graceUntil.toISOString());
  } finally {
    await h.close();
  }
});

test('confirm → purged renders "already deleted"; cancelled explains restart', async () => {
  for (const [status, needle] of [
    ['purged', 'already been deleted'],
    ['cancelled', 'This deletion request was cancelled'],
  ] as const) {
    const h = await start({
      seed: (f) => {
        f.seed('deletionRequests', 'u1', pendingRequest({ status }));
      },
    });
    try {
      const token = createVerificationToken({
        uid: 'u1',
        email: 'user@example.com',
        secret: 'test-secret',
        purpose: 'account_delete',
      });
      const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
      assert.equal(res.status, 200);
      const text = await res.text();
      assert.ok(text.includes(needle), `expected "${needle}" for status ${status}`);
    } finally {
      await h.close();
    }
  }
});

test('confirm → a valid token with no stored request renders not-found', async () => {
  const h = await start();
  try {
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
      purpose: 'account_delete',
    });
    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    const text = await res.text();
    assert.ok(text.includes('Deletion request not found'));
  } finally {
    await h.close();
  }
});

test('confirm → supplier: listings deactivated and ids remembered', async () => {
  const h = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile({ role: 'supplier' }));
      f.seed('products', 'p1', { name: 'Sofa', supplierId: 'u1', isActive: true });
      f.seed('products', 'p2', { name: 'Lamp', supplierId: 'u1', isActive: false });
      f.seed('deletionRequests', 'u1', pendingRequest({ role: 'supplier' }));
    },
  });
  try {
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
      purpose: 'account_delete',
    });
    const res = await fetch(`${h.base}/account/delete/confirm?token=${encodeURIComponent(token)}`);
    const text = await res.text();
    assert.ok(text.includes('Deletion scheduled'));

    assert.equal(h.fake.doc('products', 'p1')?.isActive, false);
    assert.equal(h.fake.doc('products', 'p2')?.isActive, false); // never deleted
    const req = h.fake.doc('deletionRequests', 'u1');
    assert.equal(req?.status, 'grace');
    const ids = (req?.deactivatedProductIds as string[]).slice().sort();
    assert.deepEqual(ids, ['p1', 'p2']);
  } finally {
    await h.close();
  }
});

// ── Cross-purpose guard the other way (verify-email side) ─────────────────

test('a deletion token cannot confirm an email (verify-email purpose guard)', async () => {
  let verified = false;
  const app = express();
  app.use(
    '/verify-email',
    createVerifyEmailRouter({
      tokenSecret: 'test-secret',
      mailer: { isConfigured: true, sendVerificationEmail: async () => {} },
      isFirebaseConfigured: () => true,
      setEmailVerified: async () => {
        verified = true;
      },
      log: () => {},
    })
  );
  const { base, close } = await listen(app);
  try {
    const token = createVerificationToken({
      uid: 'u1',
      email: 'user@example.com',
      secret: 'test-secret',
      purpose: 'account_delete',
    });
    const res = await fetch(`${base}/verify-email/confirm?token=${encodeURIComponent(token)}`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.ok(text.includes('Verification failed'));
    assert.equal(verified, false);
  } finally {
    await close();
  }
});

// ── POST /api/account/deletion-request/cancel ──────────────────────────────

test('cancel → grace: restores supplier products, clears the mirror, audits', async () => {
  const h = await start({
    seed: (f) => {
      f.seed('users', 'u1', profile({ role: 'supplier', deletion: { status: 'grace' } }));
      f.seed('products', 'p1', { name: 'Sofa', supplierId: 'u1', isActive: false });
      f.seed('products', 'p2', { name: 'Desk', supplierId: 'other', isActive: true });
      f.seed(
        'deletionRequests',
        'u1',
        pendingRequest({
          role: 'supplier',
          status: 'grace',
          deactivatedProductIds: ['p1'],
          graceUntil: Timestamp.fromDate(new Date('2026-10-12T00:00:00Z')),
          purgeAt: Timestamp.fromDate(new Date('2026-10-12T00:00:00Z')),
        })
      );
    },
  });
  try {
    const res = await post(h.base, '/api/account/deletion-request/cancel', {});
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'cancelled' });

    assert.equal(h.fake.doc('products', 'p1')?.isActive, true); // restored
    assert.equal(h.fake.doc('products', 'p2')?.isActive, true); // untouched
    const mirror = h.fake.doc('users', 'u1');
    assert.ok(mirror);
    assert.ok(!('deletion' in mirror), 'users/{uid}.deletion must be cleared');
    assert.equal(h.fake.doc('deletionRequests', 'u1')?.status, 'cancelled');

    const events = h.fake.all('deletion_audit_logs').map((d) => d.event);
    assert.ok(events.includes('cancelled'));
  } finally {
    await h.close();
  }
});

test('cancel → 404 when there is no active request', async () => {
  const h = await start({
    seed: (f) => f.seed('deletionRequests', 'u1', pendingRequest({ status: 'purged' })),
  });
  try {
    const missing = await post(h.base, '/api/account/deletion-request/cancel', {});
    assert.equal(missing.status, 404);
    const body = (await missing.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'NOT_FOUND');
    // Already-cancelled / purged requests are also "no active request".
    const stillPurged = h.fake.doc('deletionRequests', 'u1');
    assert.equal(stillPurged?.status, 'purged');
  } finally {
    await h.close();
  }
});

// ── GET /api/account/deletion-status ───────────────────────────────────────

test('status → none when no request exists (and kicks a sweep)', async () => {
  const h = await start();
  try {
    const res = await get(h.base, '/api/account/deletion-status');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'none' });
    // Fire-and-forget: never awaited by the response, but it must happen.
    await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(h.sweepCount(), 1);
  } finally {
    await h.close();
  }
});

test('status → pending_email / grace shapes with ISO timestamps', async () => {
  const graceUntil = new Date('2026-10-12T00:00:00Z');
  const seed = (f: FakeFirestore): void => {
    f.seed('deletionRequests', 'u2', pendingRequest({ uid: 'u2', status: 'pending_email' }));
    f.seed(
      'deletionRequests',
      'u1',
      pendingRequest({
        status: 'grace',
        graceUntil: Timestamp.fromDate(graceUntil),
        purgeAt: Timestamp.fromDate(graceUntil),
      })
    );
  };

  const pendingHarness = await start({ uid: 'u2', email: 'u2@example.com', seed });
  try {
    const res = await get(pendingHarness.base, '/api/account/deletion-status');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'pending_email' });
  } finally {
    await pendingHarness.close();
  }

  const graceHarness = await start({ uid: 'u1', seed });
  try {
    const res = await get(graceHarness.base, '/api/account/deletion-status');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), {
      status: 'grace',
      graceUntil: graceUntil.toISOString(),
      purgeAt: graceUntil.toISOString(),
    });
  } finally {
    await graceHarness.close();
  }
});

// ── Mailer contract (real VerificationMailer against a fake fetch) ─────────

test('sendDeletionEmail → correct endpoint, subject, link and body', async () => {
  const calls: Array<{ url: string; body?: unknown }> = [];
  const mailer = new VerificationMailer({
    apiKey: 'test-key',
    senderEmail: 'noreply@interior-design.app',
    publicBaseUrl: 'https://example.test',
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), body: init?.body === undefined ? undefined : JSON.parse(String(init.body)) });
      return new Response('{"messageId":1}', { status: 200 });
    },
  });
  await mailer.sendDeletionEmail({ email: 'a@b.co', token: 'TOK' });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.brevo.com/v3/smtp/email');
  const body = calls[0].body as {
    subject: string;
    to: Array<{ email: string }>;
    htmlContent: string;
  };
  assert.equal(body.subject, 'Confirm account deletion — Intellar');
  assert.equal(body.to[0].email, 'a@b.co');
  assert.ok(body.htmlContent.includes('https://example.test/account/delete/confirm?token=TOK'));
  assert.ok(body.htmlContent.includes('24 hours'));
  assert.ok(body.htmlContent.includes('7-day recovery'));
  assert.ok(body.htmlContent.includes('anonymized records'));
  assert.ok(body.htmlContent.includes('signing in'));
});
