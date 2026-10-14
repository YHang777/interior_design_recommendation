import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSystemPrompt,
  parseModelEnvelope,
  sanitiseSuggestions,
  type ChatProduct,
} from './ai-chat.service';

const wallpaper: ChatProduct = {
  id: 'wall-1',
  name: 'Floral Wallpaper',
  price: 30,
  category: 'Wallpaper',
  designStyle: 'Floral',
  description: 'Premium vinyl wallpaper, waterproof.',
  photoLabels: ['living room', 'sofa'],
  photoSummary: 'A living room with a grey sofa.',
  photoMismatch: true,
};

const plainSofa: ChatProduct = {
  id: 'sofa-1',
  name: 'Nordic Sofa',
  price: 1299,
  category: 'Sofa',
  designStyle: 'Scandinavian',
  description: 'Three-seater in oatmeal boucle.',
  photoLabels: ['sofa', 'oatmeal fabric'],
  photoSummary: 'Light fabric three-seater sofa.',
};

test('buildSystemPrompt → catalogue carries id, photo, seller and mismatch lines', () => {
  const prompt = buildSystemPrompt({ messages: [], products: [wallpaper, plainSofa] });

  // Ids the suggestion cards key on.
  assert.ok(prompt.includes('id=wall-1'));
  assert.ok(prompt.includes('id=sofa-1'));
  // Verified photo line vs unverified seller line, both present.
  assert.ok(prompt.includes('Photo shows: A living room with a grey sofa.'));
  assert.ok(prompt.includes('Seller claims: Premium vinyl wallpaper, waterproof.'));
  // The mismatch item gets an explicit trust instruction…
  assert.ok(prompt.includes('The photo does not match the seller description.'));
  assert.ok(prompt.includes('Trust the photo; treat the seller text as claims only.'));
  // …and the clear item does not.
  const sofaBlock = prompt.slice(prompt.indexOf('id=sofa-1'));
  assert.ok(!sofaBlock.includes('does not match'));
  // Style is folded into the head line.
  assert.ok(prompt.includes('(Wallpaper, Floral) — RM 30'));
});

test('buildSystemPrompt → no catalogue block when no products are sent', () => {
  const prompt = buildSystemPrompt({ messages: [] });
  assert.ok(!prompt.includes('Catalogue items available'));
  // No per-item lines — the instructions mention "Photo shows:" as a concept.
  assert.ok(!prompt.includes('id='));
  assert.ok(!prompt.includes('Photo shows: A living room'));
});

test('buildSystemPrompt → says to answer as a JSON envelope', () => {
  const prompt = buildSystemPrompt({ messages: [] });
  assert.ok(prompt.includes('"reply"'));
  assert.ok(prompt.includes('"suggestions"'));
});

test('parseModelEnvelope → valid object yields reply and suggestions', () => {
  const out = parseModelEnvelope(
    JSON.stringify({
      reply: 'The grey sofa would suit your room.',
      suggestions: [{ productId: 'sofa-1', reason: 'Matches the floor.' }],
    })
  );
  assert.equal(out.reply, 'The grey sofa would suit your room.');
  assert.deepEqual(out.suggestions, [
    { productId: 'sofa-1', reason: 'Matches the floor.' },
  ]);
});

test('parseModelEnvelope → fenced JSON is unwrapped', () => {
  const out = parseModelEnvelope(
    '```json\n' +
      JSON.stringify({ reply: 'Hello there.', suggestions: [] }) +
      '\n```'
  );
  assert.equal(out.reply, 'Hello there.');
  assert.deepEqual(out.suggestions, []);
});

test('parseModelEnvelope → plain prose falls back with no suggestions', () => {
  const out = parseModelEnvelope('A grey sofa and a jute rug would work nicely.');
  assert.equal(out.reply, 'A grey sofa and a jute rug would work nicely.');
  assert.deepEqual(out.suggestions, []);
});

test('parseModelEnvelope → unusable reply falls back to the whole raw text', () => {
  const raw = '{"suggestions":[{"productId":"x","reason":"y"}]} and some trailing words';
  const out = parseModelEnvelope(raw);
  // No usable "reply" → the raw text becomes the message and cards are dropped.
  assert.equal(out.reply, raw);
  assert.deepEqual(out.suggestions, []);
});

test('parseModelEnvelope → malformed JSON never throws and keeps the text', () => {
  const out = parseModelEnvelope('{"reply": "cut off mid');
  assert.equal(out.reply, '{"reply": "cut off mid');
  assert.deepEqual(out.suggestions, []);
});

test('parseModelEnvelope → junk suggestion entries are filtered', () => {
  const out = parseModelEnvelope(
    JSON.stringify({
      reply: 'ok',
      suggestions: [
        { productId: 'keep-1', reason: 'good' },
        { productId: '', reason: 'no id' },
        { productId: 42, reason: 'not a string' },
        'not-an-object',
        null,
        { productId: 'no-reason' },
      ],
    })
  );
  assert.deepEqual(out.suggestions, [
    { productId: 'keep-1', reason: 'good' },
    { productId: 'no-reason', reason: '' },
  ]);
});

test('parseModelEnvelope → suggestions that are not an array are ignored', () => {
  const out = parseModelEnvelope(
    JSON.stringify({ reply: 'ok', suggestions: { productId: 'x' } })
  );
  assert.deepEqual(out.suggestions, []);
});

test('sanitiseSuggestions → drops unknown ids, dedupes, caps at 3', () => {
  const products = [plainSofa, wallpaper, { id: 'lamp-1', name: 'Lamp' }];
  const out = sanitiseSuggestions(
    [
      { productId: 'sofa-1', reason: 'first' },
      { productId: 'sofa-1', reason: 'dupe' },
      { productId: 'wall-1', reason: 'second' },
      { productId: 'ghost-9', reason: 'invented' },
      { productId: 'lamp-1', reason: 'third' },
      { productId: 'chair-1', reason: 'fourth — over the cap' },
    ],
    products
  );
  assert.deepEqual(out, [
    { productId: 'sofa-1', reason: 'first' },
    { productId: 'wall-1', reason: 'second' },
    { productId: 'lamp-1', reason: 'third' },
  ]);
});

test('sanitiseSuggestions → reasons are truncated to 160 chars', () => {
  const out = sanitiseSuggestions(
    [{ productId: 'sofa-1', reason: 'x'.repeat(400) }],
    [plainSofa]
  );
  assert.equal(out[0].reason.length, 160);
});

test('sanitiseSuggestions → a catalogue without ids yields no cards', () => {
  // Old clients send products with no id — they cannot render a card, so
  // every suggestion is dropped rather than shipped as a dead tap.
  const out = sanitiseSuggestions(
    [{ productId: 'sofa-1', reason: 'fits' }],
    [{ name: 'Nordic Sofa' } as ChatProduct]
  );
  assert.deepEqual(out, []);
});
