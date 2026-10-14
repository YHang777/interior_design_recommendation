import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildVisionPrompt,
  collectImageUrls,
  parseVisionJson,
} from './product-vision.service';

// ─── parseVisionJson ─────────────────────────────────────────────────────────

const goodJson = JSON.stringify({
  summary: 'A roll of floral wallpaper with pink blossoms.',
  labels: ['wallpaper roll', 'floral print', 'pink'],
  visualCategory: 'Wallpaper',
  visualStyle: 'Floral',
  mismatch: { flagged: false, reason: '' },
});

test('parse → a clean JSON verdict round-trips', () => {
  const v = parseVisionJson(goodJson);
  assert.ok(v);
  assert.equal(v.summary, 'A roll of floral wallpaper with pink blossoms.');
  assert.deepEqual(v.labels, ['wallpaper roll', 'floral print', 'pink']);
  assert.equal(v.visualCategory, 'Wallpaper');
  assert.equal(v.mismatchFlagged, false);
});

test('parse → markdown fences and surrounding prose do not break it', () => {
  const v = parseVisionJson(`Sure! Here is the verdict:\n\`\`\`json\n${goodJson}\n\`\`\`\nHope that helps.`);
  assert.ok(v);
  assert.equal(v.visualCategory, 'Wallpaper');
});

test('parse → a flagged verdict keeps its flag and reason', () => {
  const v = parseVisionJson(
    JSON.stringify({
      summary: 'A living room scene, not a wallpaper sample.',
      labels: ['living room', 'sofa'],
      visualCategory: 'Interior design',
      visualStyle: 'Bohemian',
      mismatch: { flagged: true, reason: 'Photo shows a room, not wallpaper.' },
    })
  );
  assert.ok(v);
  assert.equal(v.mismatchFlagged, true);
  assert.equal(v.mismatchReason, 'Photo shows a room, not wallpaper.');
});

test('parse → non-boolean mismatch garbage never invents a flag', () => {
  for (const flagged of ['true', 1, 'yes', null, undefined]) {
    const v = parseVisionJson(
      JSON.stringify({
        summary: 'A sofa.',
        labels: ['sofa'],
        mismatch: { flagged },
      })
    );
    assert.ok(v, `verdict for flagged=${String(flagged)}`);
    assert.equal(v.mismatchFlagged, false, `flagged=${String(flagged)}`);
  }
});

test('parse → unparseable output returns null (never a crash, never a flag)', () => {
  assert.equal(parseVisionJson(''), null);
  assert.equal(parseVisionJson('the model just apologised'), null);
  assert.equal(parseVisionJson('{"summary": "truncated by maxOutputTok'), null);
  assert.equal(parseVisionJson('[1,2,3]'), null);
});

test('parse → an empty verdict (no summary, no labels) is unusable → null', () => {
  assert.equal(
    parseVisionJson(JSON.stringify({ summary: '', labels: [], mismatch: { flagged: true } })),
    null
  );
});

test('parse → labels coerce to ≤ 8 strings, each ≤ 60 chars', () => {
  const rawLabels: unknown[] = [...Array(12).fill(0)].map((_, i) => `label ${i}`);
  rawLabels.push(42, null); // garbage entries must be dropped, not crash
  const v = parseVisionJson(JSON.stringify({ summary: 'ok', labels: rawLabels }));
  assert.ok(v);
  assert.equal(v.labels.length, 8);
  assert.ok(v.labels.every((l) => typeof l === 'string' && l.length <= 60));
});

// ─── collectImageUrls ────────────────────────────────────────────────────────

test('images → gallery first, primary as fallback, https only, capped at 3', () => {
  const urls = collectImageUrls({
    images: ['https://cdn/a.jpg', 'http://insecure/a.jpg', 'https://cdn/b.jpg', 'https://cdn/a.jpg'],
    image: 'https://cdn/primary.jpg',
    also: 'https://cdn/ignored.jpg',
  });
  // http:// skipped, duplicate skipped, primary fills slot 3.
  assert.deepEqual(urls, ['https://cdn/a.jpg', 'https://cdn/b.jpg', 'https://cdn/primary.jpg']);

  const many = collectImageUrls({
    images: ['https://cdn/1.jpg', 'https://cdn/2.jpg', 'https://cdn/3.jpg', 'https://cdn/4.jpg'],
    image: 'https://cdn/primary.jpg',
  });
  assert.equal(many.length, 3);
});

test('images → no gallery falls back to the primary image', () => {
  assert.deepEqual(collectImageUrls({ image: 'https://cdn/only.jpg' }), [
    'https://cdn/only.jpg',
  ]);
  assert.deepEqual(collectImageUrls({ image: 'assets/images/seed.png' }), []);
});

// ─── buildVisionPrompt ───────────────────────────────────────────────────────

test('prompt → carries the seller claims and the narrow flag rule', () => {
  const p = buildVisionPrompt({
    name: 'Silk Luxury Wallpaper',
    category: 'Wallpaper',
    style: 'Modern',
    description: 'Real silk finish, 10m roll',
  });
  assert.ok(p.includes('Silk Luxury Wallpaper'));
  assert.ok(p.includes('Real silk finish, 10m roll'));
  assert.ok(p.includes('ONLY when the photos clearly show a different product type'));
  assert.ok(p.includes('"mismatch"'));
});
