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
  name: string;
  price?: number;
  category?: string;
}

export interface AiChatRequest {
  messages: ChatMessage[];
  style?: string;
  room?: string;
  products?: ChatProduct[];
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
  generate: (req: AiChatRequest) => Promise<string>;
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

Hard limits:
- You cannot see the customer's photos, floor plan or cart, and you cannot place orders, change bookings or handle refunds. Say so plainly and point them to support for account and order problems.
- Stay on furniture, interiors and room planning. If asked something else, say so briefly and steer back.`;

async function generateWithGemini(req: AiChatRequest): Promise<string> {
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
      maxOutputTokens: 700,
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
  return text.trim();
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
function buildSystemPrompt(req: AiChatRequest): string {
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

  const products = normaliseProducts(req.products);
  if (products.length > 0) {
    const list = products
      .map((p) => {
        const price = typeof p.price === 'number' ? ` — RM ${p.price}` : '';
        const cat = p.category ? ` (${p.category})` : '';
        return `- ${p.name}${cat}${price}`;
      })
      .join('\n');
    lines.push(`\nCatalogue items available to recommend:\n${list}`);
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
    .filter((p) => !!p && typeof p.name === 'string' && p.name.trim().length > 0)
    .slice(0, MAX_PRODUCTS);
}
