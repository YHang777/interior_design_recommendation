import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSystemPrompt,
  formatStateBlock,
  parseModelEnvelope,
  sanitiseSuggestions,
  type ChatProduct,
  type ChatState,
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

const fullState: ChatState = {
  cart: {
    items: [
      { productId: 'sofa-1', name: 'Nordic Sofa', qty: 1, lineTotal: 1299 },
      { productId: 'lamp-1', name: 'Floor Lamp', qty: 2, lineTotal: 600 },
    ],
    itemCount: 3,
    subtotal: 1899,
  },
  plan: {
    name: 'Living Room A',
    roomType: 'living_room',
    widthCm: 400,
    heightCm: 500,
    placed: [{ name: 'Sofa', wCm: 180, hCm: 90 }],
    pendingPlacements: 1,
  },
  budget: {
    capRm: 5000,
    room: 'Kitchen',
    ecoFriendly: true,
    estimateRm: 3200,
    remainingRm: 1800,
  },
  orders: [
    {
      orderNumber: 'A102',
      status: 'shipped',
      total: 890,
      itemCount: 2,
      placedAt: '2026-10-01T09:30:00.000Z',
    },
  ],
  wishlistCount: 5,
};

test('buildSystemPrompt → live app state is cited as fact and blindness no longer covers cart/floor plan', () => {
  const prompt = buildSystemPrompt({ messages: [], state: fullState });

  assert.ok(prompt.includes("Customer's live app state (verified app data — cite as fact):"));
  assert.ok(prompt.includes('- Cart (3 items, RM 1899): Nordic Sofa x1 — RM 1299; Floor Lamp x2 — RM 600.'));
  assert.ok(prompt.includes('RM 5000'));
  // The old blindness claim is gone; photos and order handling remain off-limits.
  assert.ok(!prompt.includes('floor plan or cart'));
  assert.ok(prompt.includes("You cannot see the customer's photos, and you cannot place orders"));
  // Budget figures are labelled honestly.
  assert.ok(prompt.includes('not money spent'));
  assert.ok(prompt.includes('catalogue median estimate RM 3200'));
  assert.ok(prompt.includes('under cap by RM 1800'));
});

test('buildSystemPrompt → no state block when the request carries none', () => {
  const prompt = buildSystemPrompt({ messages: [] });
  // The instructions may describe the block; only the real block has this head.
  assert.ok(!prompt.includes("Customer's live app state (verified app data"));
});

test('formatStateBlock → renders every section and an empty state renders nothing', () => {
  const block = formatStateBlock(fullState);
  assert.ok(block.startsWith("Customer's live app state (verified app data — cite as fact):"));
  assert.ok(block.includes('Room plan "Living Room A" (living_room, 400x500 cm)'));
  assert.ok(block.includes('Sofa 180x90 cm'));
  assert.ok(block.includes('1 chat item(s) waiting to be placed'));
  assert.ok(block.includes('Recent orders: #A102 shipped — RM 890, 2 item(s), placed 2026-10-01'));
  assert.ok(block.includes('Wishlist: 5 saved item(s)'));
  assert.equal(formatStateBlock({}), '');
});

test('formatStateBlock → a negative remainder reads as over cap', () => {
  const block = formatStateBlock({
    budget: { capRm: 1000, estimateRm: 1400, remainingRm: -400 },
  });
  assert.ok(block.includes('over cap by RM 400'));
});

test('formatStateBlock → hard-clips to 1500 chars', () => {
  const block = formatStateBlock({
    cart: {
      items: Array.from({ length: 8 }, (_, i) => ({
        productId: `p-${i}`,
        name: 'Long product name '.repeat(10),
        qty: 9,
        lineTotal: 99999,
      })),
      itemCount: 72,
      subtotal: 799992,
    },
  });
  assert.ok(block.length <= 1500);
});
