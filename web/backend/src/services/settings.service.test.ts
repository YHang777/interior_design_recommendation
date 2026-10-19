import test from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import {
  DEFAULT_TAX_RATE,
  getSettings,
  toSettings,
  updateSettings,
} from './settings.service';

// ── toSettings ───────────────────────────────────────────────────────────────

test('settings → valid taxRate passes through; metadata survives', () => {
  const s = toSettings({
    taxRate: 0.08,
    updatedAt: '2026-10-19T00:00:00.000Z',
    updatedBy: 'admin-1',
  });
  assert.equal(s.taxRate, 0.08);
  assert.equal(s.updatedAt, '2026-10-19T00:00:00.000Z');
  assert.equal(s.updatedBy, 'admin-1');
});

test('settings → out-of-range or non-numeric taxRate falls back to the default', () => {
  assert.equal(toSettings({ taxRate: 1.5 }).taxRate, DEFAULT_TAX_RATE);
  assert.equal(toSettings({ taxRate: -0.1 }).taxRate, DEFAULT_TAX_RATE);
  assert.equal(toSettings({ taxRate: '0.06' }).taxRate, DEFAULT_TAX_RATE);
  assert.equal(toSettings({ taxRate: Number.NaN }).taxRate, DEFAULT_TAX_RATE);
  assert.equal(toSettings({}).taxRate, DEFAULT_TAX_RATE);
  assert.equal(toSettings(undefined).taxRate, DEFAULT_TAX_RATE);
});

test('settings → missing metadata becomes null, not the string "undefined"', () => {
  const s = toSettings({ taxRate: 0.06 });
  assert.equal(s.updatedAt, null);
  assert.equal(s.updatedBy, null);
});

// ── getSettings / updateSettings (FakeFirestore, set+merge only) ─────────────

type Doc = Record<string, unknown>;

class FakeRef {
  constructor(private readonly db: FakeDb, readonly path: string) {}

  async get(): Promise<{ exists: boolean; data(): Doc | undefined }> {
    const data = this.db.docs.get(this.path);
    return {
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : { ...data }),
    };
  }

  async set(patch: Doc, opts?: { merge?: boolean }): Promise<void> {
    const target = this.db.docs.get(this.path);
    if (target && opts?.merge) {
      Object.assign(target, patch);
    } else {
      this.db.docs.set(this.path, { ...patch });
    }
  }
}

class FakeDb {
  readonly docs = new Map<string, Doc>();

  seed(path: string, doc: Doc): void {
    this.docs.set(path, { ...doc });
  }

  collection(name: string) {
    return { doc: (id: string) => new FakeRef(this, `${name}/${id}`) };
  }

  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }
}

test('getSettings → a missing doc returns the 6% defaults', async () => {
  const db = new FakeDb();
  const s = await getSettings(db.asFirestore());
  assert.equal(s.taxRate, DEFAULT_TAX_RATE);
  assert.equal(s.taxRate, 0.06);
  assert.equal(s.updatedAt, null);
  assert.equal(s.updatedBy, null);
});

test('getSettings → a stored rate is read back', async () => {
  const db = new FakeDb();
  db.seed('appConfig/marketplace', {
    taxRate: 0.08,
    updatedAt: '2026-10-19T01:00:00.000Z',
    updatedBy: 'admin-1',
  });
  const s = await getSettings(db.asFirestore());
  assert.equal(s.taxRate, 0.08);
  assert.equal(s.updatedBy, 'admin-1');
});

test('getSettings → a malformed stored rate falls back to the default', async () => {
  const db = new FakeDb();
  db.seed('appConfig/marketplace', { taxRate: 'lots', updatedAt: 42, updatedBy: 7 });
  const s = await getSettings(db.asFirestore());
  assert.equal(s.taxRate, DEFAULT_TAX_RATE);
  assert.equal(s.updatedAt, null);
  assert.equal(s.updatedBy, null);
});

test('updateSettings → creates the missing doc with rate and audit stamps', async () => {
  const db = new FakeDb();
  const s = await updateSettings(0.08, 'admin-1', db.asFirestore());
  assert.equal(s.taxRate, 0.08);
  assert.equal(s.updatedBy, 'admin-1');
  assert.ok(s.updatedAt);

  const stored = db.docs.get('appConfig/marketplace');
  assert.ok(stored);
  assert.equal(stored.taxRate, 0.08);
  assert.equal(stored.updatedBy, 'admin-1');
  assert.equal(stored.updatedAt, s.updatedAt);
});

test('updateSettings → a second call merges over the existing doc', async () => {
  const db = new FakeDb();
  db.seed('appConfig/marketplace', { taxRate: 0.08, note: 'keep-me' });
  await updateSettings(0.1, 'admin-2', db.asFirestore());
  const stored = db.docs.get('appConfig/marketplace');
  assert.ok(stored);
  assert.equal(stored.taxRate, 0.1);
  assert.equal(stored.updatedBy, 'admin-2');
  assert.equal(stored.note, 'keep-me');
});
