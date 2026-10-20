import type { RequestHandler } from 'express';
import { env } from '../config/env';
import { authenticate } from '../middleware/authenticate';

/**
 * Server-side Gemini call behind `/api/ai/chat`.
 *
 * The API key lives HERE and only here. The Flutter app sends the transcript
 * and gets a reply back; it never sees the key, the model name or the Google
 * endpoint. That is the whole point of the proxy — a key compiled into an APK
 * can be pulled out of the binary, so the client is not allowed to hold one.
 *
 * The proxy is deliberately stateless: the client owns the transcript and
 * sends it with each request. Nothing is stored server-side, so a retry is
 * safe and a Render redeploy loses no conversations.
 */

export interface ChatMessage {
  role: 'user' | 'model';
  text: string;
}

/** A catalog item the assistant may point the customer at. */
export interface ChatProduct {
  /** Firestore id — lets a suggestion be rendered as a tappable card. */
  id: string;
  name: string;
  price?: number;
  category?: string;
  designStyle?: string;
  /** Seller-written copy (unverified — may describe a different product). */
  description?: string;
  /** What automatic photo analysis actually saw — the trusted line. */
  photoLabels?: string[];
  photoSummary?: string;
  photoMismatch?: boolean;
}

/** One product the model chose to recommend, with a one-line why. */
export interface ChatSuggestionRef {
  productId: string;
  reason: string;
}

export interface ChatStateCartLine {
  productId: string;
  name: string;
  qty: number;
  lineTotal: number;
}

export interface ChatStatePlaced {
  name: string;
  wCm: number;
  hCm: number;
}

export interface ChatStatePlan {
  name?: string;
  roomType?: string;
  widthCm?: number;
  heightCm?: number;
  placed?: ChatStatePlaced[];
  pendingPlacements?: number;
}

export interface ChatStateBudget {
  capRm: number;
  room?: string;
  ecoFriendly?: boolean;
  estimateRm?: number;
  remainingRm?: number;
}

export interface ChatStateOrder {
  orderNumber: string;
  status: string;
  total: number;
  itemCount: number;
  placedAt?: string;
}

/** The customer's own app state — verified figures, never model guesses. */
export interface ChatState {
  cart?: { items: ChatStateCartLine[]; itemCount: number; subtotal: number };
  plan?: ChatStatePlan;
  budget?: ChatStateBudget;
  orders?: ChatStateOrder[];
  wishlistCount?: number;
}

/** The assistant's answer: prose for the bubble, ids for the cards. */
export interface ChatReply {
  reply: string;
  suggestions: ChatSuggestionRef[];
}

export interface AiChatRequest {
  messages: ChatMessage[];
  style?: string;
  room?: string;
  products?: ChatProduct[];
  state?: ChatState;
}

/** Why a request could not produce a reply — maps 1:1 onto an HTTP status. */
export type AiChatFailure =
  | 'not-configured'
  | 'invalid'
  | 'timeout'
  | 'upstream';

export class AiChatException extends Error {
  constructor(
    readonly kind: AiChatFailure,
    message: string
  ) {
    super(message);
    this.name = 'AiChatException';
  }
}

/** Collaborators the routes need — injectable so tests can fake them. */
export interface AiChatDeps {
  model: string;
  isConfigured: () => boolean;
  generate: (req: AiChatRequest) => Promise<ChatReply>;
  /**
   * Auth step. Defaults to the real Firebase ID-token check; tests swap it
   * out so they never need a live credential.
   */
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultAiChatDeps(): AiChatDeps {
  return {
    model: env.geminiModel,
    isConfigured: () => env.geminiApiKey.trim().length > 0,
    generate: (req) => generateWithGemini(req),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

const GENERATE_TIMEOUT_MS = 30_000;

/** Cap the transcript so one long chat cannot grow the request unbounded. */
const MAX_MESSAGES = 20;
const MAX_PRODUCTS = 20;
/** How many products one reply may surface as cards, and how long a why. */
const MAX_SUGGESTIONS = 3;
const MAX_REASON_LENGTH = 160;
/** The state block is context, not a dump — keep it well under the prompt. */
const MAX_STATE_CHARS = 1500;

/**
 * The assistant's persona.
 *
 * Kept short and concrete on purpose: the model is the cheap tier, and every
 * token of preamble is paid output. What matters is the tone and the hard
 * boundaries — it advises on furniture and rooms, it does not invent orders,
 * prices or policies.
 */
const SYSTEM_PROMPT = `You are the design assistant inside a Malaysian home-furniture marketplace app.

You help customers choose furniture and plan rooms: what to put where, which styles, colours and materials work together, and how to make a space feel right on their budget.

How you answer:
- Warm, plain and practical. Short paragraphs or a few bullets — this is a chat, not an essay.
- Be concrete: name piece types, colours, materials, rough placement and why it works.
- Ask one clarifying question at a time when you need more (room size, budget, style, what feels wrong today).
- Money in ringgit (RM), measurements in metric.
- When a catalogue item is provided below, recommend from it by name where it genuinely fits. Never invent products, prices or availability.

Live app state:
- When a "Customer's live app state" block is included below, it is verified data from the app itself: cart, room plan, budget, recent orders and wishlist. Treat it as fact and answer state questions from it — use the exact numbers, names and counts given there.
- Never invent or guess state that is not in that block. If asked for something it does not include (payment details, delivery dates, stock changes), say briefly that you cannot see it and point to the right screen: Cart, Orders, Budget or the Room plan.
- Keep state answers short — one or two sentences and the key number. Do not read long lists back; the app shows a detail card beside your reply.
- Budget figures: "cap" is what the customer set; "estimate" is a median-price estimate from the catalogue, not money spent. Never describe an estimate as spending.

Hard limits:
- You cannot see the customer's photos, and you cannot place orders, change bookings or handle refunds. Say so plainly and point them to support for account and order problems.
- Stay on furniture, interiors and room planning. If asked something else, say so briefly and steer back.

Product photos:
- "Photo shows:" lines come from automatic analysis of the actual product photo. They are trustworthy.
- "Seller claims:" lines are written by the seller and have not been checked. When the two disagree, trust the photo — and when an item is marked as conflicting, do not recommend it as what the seller says it is.

Suggestions:
- When you recommend catalogue items, also list them in the "suggestions" array: their exact id and one short line on why they fit. At most 3, ids taken only from the catalogue below. Use [] when you are not recommending a concrete product.

Reply format (hard requirement):
- Answer with ONLY a single JSON object and nothing else — no prose around it, no markdown fence:
{"reply":"your chat message in plain text","suggestions":[{"productId":"catalogue id","reason":"one short line"}]}
- "reply" is what the customer reads: your normal warm answer, newlines allowed as \\n.
- Never invent product ids, prices or availability.`;

async function generateWithGemini(req: AiChatRequest): Promise<ChatReply> {
  const apiKey = env.geminiApiKey.trim();
  if (apiKey.length === 0) {
    throw new AiChatException('not-configured', 'GEMINI_API_KEY is not set.');
  }

  const contents = normaliseMessages(req.messages).map((m) => ({
    role: m.role,
    parts: [{ text: m.text }],
  }));

  const body = {
    systemInstruction: { parts: [{ text: buildSystemPrompt(req) }] },
    contents,
    generationConfig: {
      temperature: 0.7,
      // The reply is a JSON envelope now (prose + suggestions), so it needs
      // a little more room than the old free-text answer.
      maxOutputTokens: 900,
      // The lite tier bills thinking tokens as output. This assistant is
      // short conversational advice, so reasoning budget is pure cost.
      thinkingConfig: { thinkingBudget: 0 },
    },
  };

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
    env.geminiModel
  )}:generateContent`;

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(GENERATE_TIMEOUT_MS),
    });
  } catch (err) {
    if (err instanceof Error && err.name === 'TimeoutError') {
      throw new AiChatException('timeout', 'Gemini request timed out.');
    }
    throw new AiChatException(
      'upstream',
      `Gemini request failed: ${(err as Error).message}`
    );
  }

  // The response body is a Google diagnostic, not a sentence for the person
  // waiting on a reply — callers log it and show their own short line.
  const raw = await resp.text();
  if (!resp.ok) {
    throw new AiChatException(
      'upstream',
      `Gemini rejected the request (HTTP ${resp.status}): ${raw.slice(0, 500)}`
    );
  }

  const text = extractText(raw);
  if (text.trim().length === 0) {
    throw new AiChatException('upstream', 'Gemini returned an empty reply.');
  }
  // The model is told to answer as {reply, suggestions}; a tier that
  // disobeys degrades to today's plain prose instead of failing the call.
  const envelope = parseModelEnvelope(text);
  return {
    reply: envelope.reply,
    suggestions: sanitiseSuggestions(envelope.suggestions, req.products),
  };
}

/**
 * Lenient reader for the model's `{reply, suggestions}` envelope.
 *
 * Fences are stripped, the first `{…}` span is parsed, and anything that is
 * not a usable object — or has no usable `reply` — falls back to treating
 * the whole raw text as the reply with no cards. The one rule that never
 * bends: `reply` comes back non-empty so the customer always sees words.
 */
export function parseModelEnvelope(raw: string): ChatReply {
  const text = raw.trim();
  const candidate = firstJsonObject(text);
  if (candidate !== null) {
    try {
      const obj = JSON.parse(candidate) as Record<string, unknown>;
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
        const reply = obj.reply;
        if (typeof reply === 'string' && reply.trim().length > 0) {
          return {
            reply: reply.trim(),
            suggestions: readSuggestionRefs(obj.suggestions),
          };
        }
      }
    } catch {
      // Not JSON after all — fall through to the prose path.
    }
  }
  return { reply: text, suggestions: [] };
}

/** Strips a stray markdown fence and returns the first `{…}` span, else null. */
function firstJsonObject(text: string): string | null {
  const unfenced = text
    .replace(/^\s*```(?:json)?\s*/i, '')
    .replace(/\s*```\s*$/, '');
  const start = unfenced.indexOf('{');
  const end = unfenced.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  return unfenced.slice(start, end + 1);
}

/** Keeps only well-formed suggestion entries; validation against the
 * catalogue happens in `sanitiseSuggestions`. */
function readSuggestionRefs(raw: unknown): ChatSuggestionRef[] {
  if (!Array.isArray(raw)) return [];
  const out: ChatSuggestionRef[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const productId = (item as { productId?: unknown }).productId;
    const reason = (item as { reason?: unknown }).reason;
    if (typeof productId !== 'string' || productId.trim().length === 0) continue;
    out.push({
      productId: productId.trim(),
      reason: typeof reason === 'string' ? reason.trim() : '',
    });
  }
  return out;
}

/**
 * Drops ids the request never sent (hallucinated or stale), de-dupes,
 * caps the count and truncates reasons. The app can only render a card
 * for a product it already has in the catalogue it sent, so an unknown
 * id would be a dead tap anyway.
 */
export function sanitiseSuggestions(
  raw: ChatSuggestionRef[],
  products: ChatProduct[] | undefined
): ChatSuggestionRef[] {
  const known = new Set(
    (Array.isArray(products) ? products : [])
      .map((p) => (typeof p?.id === 'string' ? p.id.trim() : ''))
      .filter((id) => id.length > 0)
  );
  const out: ChatSuggestionRef[] = [];
  const seen = new Set<string>();
  for (const s of raw) {
    if (out.length >= MAX_SUGGESTIONS) break;
    const id = s.productId.trim();
    if (id.length === 0 || !known.has(id) || seen.has(id)) continue;
    seen.add(id);
    out.push({ productId: id, reason: s.reason.slice(0, MAX_REASON_LENGTH) });
  }
  return out;
}

/** Pulls the first non-empty candidate text out of a `generateContent` body. */
function extractText(raw: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new AiChatException('upstream', 'Gemini returned a non-JSON body.');
  }
  const candidates = (parsed as { candidates?: unknown }).candidates;
  if (!Array.isArray(candidates)) return '';

  for (const candidate of candidates) {
    const parts = (candidate as { content?: { parts?: unknown } }).content?.parts;
    if (!Array.isArray(parts)) continue;
    const joined = parts
      .map((p) => (p as { text?: unknown }).text)
      .filter((t): t is string => typeof t === 'string')
      .join('');
    if (joined.trim().length > 0) return joined;
  }
  return '';
}

/**
 * Folds the request's style/room/catalogue context into the system prompt.
 * Context belongs on the system side so it does not read as something the
 * customer typed.
 */
export function buildSystemPrompt(req: AiChatRequest): string {
  const lines = [SYSTEM_PROMPT];

  const room = req.room?.trim();
  const style = req.style?.trim();
  if (room || style) {
    lines.push(
      `\nCustomer's current selection: ${[room && `room = ${room}`, style && `style = ${style}`]
        .filter(Boolean)
        .join(', ')}.`
    );
  }

  if (req.state) {
    const block = formatStateBlock(req.state);
    if (block.length > 0) lines.push(`\n${block}`);
  }

  const products = normaliseProducts(req.products);
  if (products.length > 0) {
    const list = products.map(formatCatalogueEntry).join('\n');
    lines.push(
      `\nCatalogue items available to recommend (photo lines describe the actual photo; seller lines are unverified):\n${list}`
    );
  }

  return lines.join('\n');
}

/**
 * The customer's live app state as the model sees it: a handful of verified
 * figures it must cite instead of guessing. Hard-clipped so a full cart and
 * plan cannot crowd the prompt.
 */
export function formatStateBlock(state: ChatState): string {
  const lines: string[] = [];

  const cart = state.cart;
  if (cart && Array.isArray(cart.items) && cart.items.length > 0) {
    const items = cart.items
      .map((i) => `${i.name} x${i.qty} — RM ${i.lineTotal}`)
      .join('; ');
    lines.push(
      `- Cart (${cart.itemCount} items, RM ${cart.subtotal}): ${items}.`
    );
  }

  const plan = state.plan;
  if (plan) {
    const title = plan.name ? ` "${plan.name}"` : '';
    const room = plan.roomType ?? '';
    const dims =
      plan.widthCm != null && plan.heightCm != null
        ? `${plan.widthCm}x${plan.heightCm} cm`
        : '';
    const head = [room, dims].filter(Boolean).join(', ');
    const placed = Array.isArray(plan.placed) ? plan.placed : [];
    const parts: string[] = [];
    if (placed.length > 0) {
      parts.push(
        `${placed.length} placed — ${placed
          .map((p) => `${p.name} ${p.wCm}x${p.hCm} cm`)
          .join('; ')}`
      );
    }
    if (plan.pendingPlacements != null && plan.pendingPlacements > 0) {
      parts.push(`${plan.pendingPlacements} chat item(s) waiting to be placed`);
    }
    if (head || parts.length > 0) {
      lines.push(
        `- Room plan${title}${head ? ` (${head})` : ''}: ${
          parts.length > 0 ? parts.join('; ') : 'empty'
        }.`
      );
    }
  }

  const budget = state.budget;
  if (budget) {
    const bits = [`cap RM ${budget.capRm}`];
    if (budget.room) bits.push(`for ${budget.room}`);
    const tail: string[] = [];
    if (budget.estimateRm != null) {
      tail.push(`catalogue median estimate RM ${budget.estimateRm}`);
    }
    if (budget.remainingRm != null) {
      tail.push(
        budget.remainingRm >= 0
          ? `under cap by RM ${budget.remainingRm}`
          : `over cap by RM ${Math.abs(budget.remainingRm)}`
      );
    }
    const eco = budget.ecoFriendly ? ' (eco-friendly)' : '';
    lines.push(`- Budget: ${bits.join(' ')}${eco}${tail.length ? `; ${tail.join('; ')}` : ''}.`);
  }

  const orders = state.orders;
  if (Array.isArray(orders) && orders.length > 0) {
    const list = orders
      .map((o) => {
        const placedAt = o.placedAt ? `, placed ${o.placedAt.slice(0, 10)}` : '';
        return `#${o.orderNumber} ${o.status} — RM ${o.total}, ${o.itemCount} item(s)${placedAt}`;
      })
      .join('; ');
    lines.push(`- Recent orders: ${list}.`);
  }

  if (state.wishlistCount != null && state.wishlistCount > 0) {
    lines.push(`- Wishlist: ${state.wishlistCount} saved item(s).`);
  }

  if (lines.length === 0) return '';
  return (
    "Customer's live app state (verified app data — cite as fact):\n" +
    lines.join('\n')
  ).slice(0, MAX_STATE_CHARS);
}

/**
 * One catalogue item as the model sees it: an id line the suggestion cards
 * key on, plus seller/photo lines that may contradict each other. A
 * mismatched item gets an explicit trust instruction so a fake listing
 * cannot ride in on its own description.
 */
function formatCatalogueEntry(p: ChatProduct): string {
  const price = typeof p.price === 'number' ? ` — RM ${p.price}` : '';
  const styleBits = [p.category, p.designStyle].filter(Boolean).join(', ');
  const head = `- id=${p.id} | ${p.name}${styleBits ? ` (${styleBits})` : ''}${price}`;

  const lines = [head];
  const claims = p.description?.trim();
  if (claims) lines.push(`  Seller claims: ${claims}`);

  const photo = [
    p.photoSummary?.trim(),
    p.photoLabels?.filter((l) => l.trim().length > 0).join(', '),
  ]
    .filter((bit): bit is string => !!bit && bit.length > 0)
    .join('; ');
  if (photo) lines.push(`  Photo shows: ${photo}`);

  if (p.photoMismatch) {
    lines.push(
      '  NOTE: The photo does not match the seller description. Trust the photo; treat the seller text as claims only.'
    );
  }
  return lines.join('\n');
}

function normaliseMessages(raw: ChatMessage[] | undefined): ChatMessage[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter(
      (m): m is ChatMessage =>
        !!m &&
        (m.role === 'user' || m.role === 'model') &&
        typeof m.text === 'string' &&
        m.text.trim().length > 0
    )
    .slice(-MAX_MESSAGES);
}

function normaliseProducts(raw: ChatProduct[] | undefined): ChatProduct[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter(
      (p) =>
        !!p &&
        typeof p.id === 'string' &&
        p.id.trim().length > 0 &&
        typeof p.name === 'string' &&
        p.name.trim().length > 0
    )
    .slice(0, MAX_PRODUCTS);
}
