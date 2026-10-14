import test from 'node:test';
import assert from 'node:assert/strict';
import { toFlagRow } from './product-flags.service';

// ─── toFlagRow ───────────────────────────────────────────────────────────────
// Firestore doc → queue row. The mapper must be total: anything the seller
// client (or a legacy doc) can put in the document still yields a row the
// admin table can render.

test('row → a full flagged doc maps every column', () => {
  const row = toFlagRow('wall-1', {
    name: 'Floral Wallpaper',
    category: 'Wallpaper',
    price: 30,
    supplierId: 'seller-1',
    image: 'https://cdn.example/wall.jpg',
    description: 'Premium vinyl, waterproof.',
    vision: {
      status: 'ok',
      labels: ['living room', 'sofa'],
      visualCategory: 'Living room',
      summary: 'A living room with a grey sofa.',
      mismatch: { flagged: true, reason: 'Photo shows a room, not wallpaper.' },
      analyzedAt: '2026-10-14T00:00:00.000Z',
      model: 'gemini-3.1-flash-lite',
      // An admin decision on top of the analysis:
      review: {
        status: 'resolved',
        note: 'Confirmed fake.',
        reviewedAt: '2026-10-15T00:00:00.000Z',
        reviewedBy: 'admin-1',
      },
    },
  });

  assert.equal(row.productId, 'wall-1');
  assert.equal(row.name, 'Floral Wallpaper');
  assert.equal(row.price, 30);
  assert.equal(row.supplierId, 'seller-1');
  assert.equal(row.vision.summary, 'A living room with a grey sofa.');
  assert.equal(row.vision.mismatch.flagged, true);
  assert.equal(row.vision.mismatch.reason, 'Photo shows a room, not wallpaper.');
  assert.equal(row.vision.analyzedAt, '2026-10-14T00:00:00.000Z');
  assert.equal(row.vision.model, 'gemini-3.1-flash-lite');
  assert.equal(row.review?.status, 'resolved');
  assert.equal(row.review?.note, 'Confirmed fake.');
  assert.equal(row.review?.reviewedBy, 'admin-1');
});

test('row → no vision at all: empty defaults, review null (queue treats it as open)', () => {
  const row = toFlagRow('legacy-1', { name: 'Old Rug' });
  assert.equal(row.name, 'Old Rug');
  assert.equal(row.price, 0);
  assert.equal(row.supplierId, '');
  assert.equal(row.image, '');
  assert.equal(row.vision.status, '');
  assert.deepEqual(row.vision.labels, []);
  assert.equal(row.vision.summary, '');
  assert.equal(row.vision.mismatch.flagged, false);
  assert.equal(row.vision.analyzedAt, null);
  assert.equal(row.review, null);
});

test('row → wrong-typed fields coerce instead of crashing', () => {
  const row = toFlagRow('garbage-1', {
    name: 42,
    category: { nested: true },
    price: 'free',
    supplierId: null,
    image: ['a', 'b'],
    description: undefined,
    vision: {
      status: 7,
      labels: ['ok', 42, null, 'wallpaper'],
      visualCategory: true,
      summary: 123,
      mismatch: { flagged: 'yes', reason: 99 },
      analyzedAt: 1712345678,
      model: ['list'],
    },
  });

  assert.equal(row.name, '');
  assert.equal(row.category, '');
  assert.equal(row.price, 0);
  assert.equal(row.supplierId, '');
  assert.equal(row.image, '');
  assert.equal(row.description, '');
  assert.equal(row.vision.status, '');
  // Non-string labels are dropped, strings survive in order.
  assert.deepEqual(row.vision.labels, ['ok', 'wallpaper']);
  assert.equal(row.vision.visualCategory, '');
  assert.equal(row.vision.summary, '');
  // 'yes' is not boolean true — never invent a flag.
  assert.equal(row.vision.mismatch.flagged, false);
  assert.equal(row.vision.mismatch.reason, '');
  assert.equal(row.vision.analyzedAt, null);
  assert.equal(row.vision.model, '');
});

test('row → absent review means open; an unknown review status is ignored too', () => {
  const without = toFlagRow('a', { vision: { mismatch: { flagged: true } } });
  assert.equal(without.review, null);

  const bogus = toFlagRow('b', {
    vision: {
      mismatch: { flagged: true },
      review: { status: 'maybe', reviewedAt: 'x', reviewedBy: 'y' },
    },
  });
  assert.equal(bogus.review, null);
});

test('row → a review keeps optional note but blanks missing stamps', () => {
  const row = toFlagRow('c', {
    vision: {
      mismatch: { flagged: true },
      review: { status: 'open' },
    },
  });
  assert.equal(row.review?.status, 'open');
  assert.equal(row.review?.note, undefined); // absent note stays absent
  assert.equal(row.review?.reviewedAt, '');
  assert.equal(row.review?.reviewedBy, '');
});
