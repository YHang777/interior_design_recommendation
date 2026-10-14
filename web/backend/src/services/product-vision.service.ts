import type { RequestHandler } from 'express';
import { env } from '../config/env';
import { fbDb } from '../config/firebase';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';

/**
 * Upload-time photo analysis for marketplace listings (`POST /api/ai/analyze-product`).
 *
 * A seller can write anything into a listing's name/description, and the chat
 * assistant used to see ONLY that text — so a fake photo + confident claims
 * became a confident recommendation. This service closes that gap: it reads
 * the product as stored (so the verdict always matches what buyers see),
 * sends the actual photos to Gemini vision, and records what the photos show.
 *
 * Same key rule as chat/Tripo: the Gemini key lives HERE only. The result is
 * written to `products/{id}.vision` by firebase-admin, so a client cannot
 * forge a "verified" verdict by writing Firestore directly.
 *
 * The contract is deliberately never-blocking: after auth, every analysis
 * outcome returns 200 with `status: 'ok' | 'failed'` — a dead photo URL or a
 * model hiccup must never stop a seller from publishing. Failures prefer
 * false negatives (no flag) over false flags: unparseable model output
 * becomes `failed` + `mismatch.flagged = false`.
 */

/** Server-owned verdict stored on `products/{id}.vision`. */
export interface ProductVision {
  status: 'ok' | 'failed';
  /** ≤ 8 short noun phrases of what the photos show. */
  labels: string[];
  /** What the photo actually is (may contradict the seller's category). */
  visualCategory: string;
  visualStyle: string;
  /** One sentence, ≤ 200 chars. */
  summary: string;
  mismatch: { flagged: boolean; reason: string };
  /** ISO-8601. */
  analyzedAt: string;
  /** Model id — diagnostics only. */
  model: string;
}

export interface AnalyzeProductResult {
  status: 'ok' | 'failed';
  /** Short user-safe sentence; only present when `status` is `failed`. */
  message?: string;
  vision: ProductVision;
}

/** Collaborators the route needs — injectable so tests never touch Gemini/Firestore. */
export interface ProductVisionDeps {
  isConfigured: () => boolean;
  analyze: (
    productId: string,
    uid: string,
    isAdmin: boolean
  ) => Promise<AnalyzeProductResult>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultProductVisionDeps(): ProductVisionDeps {
  return {
    isConfigured: () => env.geminiApiKey.trim().length > 0,
    analyze: (productId, uid, isAdmin) => analyzeProduct(productId, uid, isAdmin),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

const MAX_IMAGES = 3;
const IMAGE_FETCH_TIMEOUT_MS = 10_000;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const VISION_TIMEOUT_MS = 30_000;

/** A verdict as parsed out of the model's JSON. */
export interface VisionVerdict {
  summary: string;
  labels: string[];
  visualCategory: string;
  visualStyle: string;
  mismatchFlagged: boolean;
  mismatchReason: string;
}

// ─── Pipeline ────────────────────────────────────────────────────────────────

async function analyzeProduct(
  productId: string,
  uid: string,
  isAdmin: boolean
): Promise<AnalyzeProductResult> {
  const snap = await fbDb().collection('products').doc(productId).get();
  if (!snap.exists) {
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }
  const data = snap.data() ?? {};
  const supplierId = typeof data.supplierId === 'string' ? data.supplierId : '';
  if (!isAdmin && (supplierId.length === 0 || supplierId !== uid)) {
    throw new ApiError(403, 'PRODUCT_NOT_OWNED', 'You can only check your own products.');
  }

  const model = visionModel();
  const urls = collectImageUrls(data);

  // A listing with no usable photo is a quiet `failed` — never a save error.
  const imageParts = await fetchImageParts(urls);
  if (imageParts.length === 0) {
    const vision = failedVision(model, 'no usable photo');
    await writeVision(productId, vision);
    return {
      status: 'failed',
      message: 'We could not read this photo. Your listing is saved as usual.',
      vision,
    };
  }

  let verdict: VisionVerdict | null = null;
  try {
    verdict = await callVisionModel(model, claimsOf(data), imageParts);
  } catch (err) {
    // Google diagnostics are for the log, never the seller.
    log(`[product-vision] upstream failed for ${productId}: ${(err as Error).message}`);
  }

  if (!verdict) {
    const vision = failedVision(model, 'model returned no usable verdict');
    await writeVision(productId, vision);
    return {
      status: 'failed',
      message: 'We could not check this photo right now. Your listing is saved as usual.',
      vision,
    };
  }

  const vision: ProductVision = {
    status: 'ok',
    labels: verdict.labels,
    visualCategory: verdict.visualCategory,
    visualStyle: verdict.visualStyle,
    summary: verdict.summary,
    mismatch: { flagged: verdict.mismatchFlagged, reason: verdict.mismatchReason },
    analyzedAt: new Date().toISOString(),
    model,
  };
  await writeVision(productId, vision);
  return { status: 'ok', vision };
}

interface SellerClaims {
  name: string;
  category: string;
  style: string;
  description: string;
}

function claimsOf(data: Record<string, unknown>): SellerClaims {
  const str = (v: unknown, max: number) =>
    typeof v === 'string' ? v.trim().slice(0, max) : '';
  return {
    name: str(data.name, 200),
    category: str(data.category, 120),
    style: str(data.designStyle, 120),
    description: str(data.description, 400),
  };
}

/** Up to [MAX_IMAGES] https image urls: gallery first, primary last resort. */
export function collectImageUrls(data: Record<string, unknown>): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const push = (v: unknown) => {
    if (out.length >= MAX_IMAGES) return;
    if (typeof v !== 'string') return;
    const url = v.trim();
    if (!url.startsWith('https://') || seen.has(url)) return;
    seen.add(url);
    out.push(url);
  };
  if (Array.isArray(data.images)) data.images.forEach(push);
  push(data.image);
  return out;
}

async function fetchImageParts(
  urls: string[]
): Promise<Array<{ mimeType: string; data: string }>> {
  const parts: Array<{ mimeType: string; data: string }> = [];
  for (const url of urls) {
    try {
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(IMAGE_FETCH_TIMEOUT_MS),
      });
      if (!resp.ok) continue;
      const mimeType = (resp.headers.get('content-type') ?? '')
        .split(';')[0]
        .trim();
      if (!mimeType.startsWith('image/')) continue;
      const bytes = Buffer.from(await resp.arrayBuffer());
      if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) continue;
      parts.push({ mimeType, data: bytes.toString('base64') });
    } catch {
      continue; // one dead URL must not sink the analysis
    }
  }
  return parts;
}

function visionModel(): string {
  return env.geminiVisionModel.trim() || env.geminiModel;
}

// ─── Model call ──────────────────────────────────────────────────────────────

export function buildVisionPrompt(c: SellerClaims): string {
  return `You are verifying a marketplace listing photo for a furniture app.
Seller claims: name="${c.name}", category="${c.category}", style="${c.style}", description="${c.description}".
Describe ONLY what the photos actually show. Return ONLY a JSON object:
{"summary":"...","labels":["..."],"visualCategory":"...","visualStyle":"...","mismatch":{"flagged":false,"reason":"..."}}
Rules:
- Set mismatch.flagged to true ONLY when the photos clearly show a different product type or category than the seller claims (for example a wallpaper photo listed as paint). Never flag styling, colour or minor detail differences.
- summary: one sentence, at most 200 characters, of what the photo shows.
- labels: at most 8 short noun phrases of visible things.
- visualCategory / visualStyle: what the item actually is, in the app's category/style terms where possible.
- reason: at most 200 characters.`;
}

async function callVisionModel(
  model: string,
  claims: SellerClaims,
  imageParts: Array<{ mimeType: string; data: string }>
): Promise<VisionVerdict | null> {
  const body = {
    contents: [
      {
        parts: [
          { text: buildVisionPrompt(claims) },
          ...imageParts.map((p) => ({
            inlineData: { mimeType: p.mimeType, data: p.data },
          })),
        ],
      },
    ],
    generationConfig: {
      maxOutputTokens: 500,
      // The lite tier bills thinking as output; this is a label task.
      thinkingConfig: { thinkingBudget: 0 },
    },
  };

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
      model
    )}:generateContent`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': env.geminiApiKey.trim(),
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(VISION_TIMEOUT_MS),
    }
  );
  const raw = await resp.text();
  if (!resp.ok) {
    throw new Error(`Gemini rejected the request (HTTP ${resp.status}): ${raw.slice(0, 500)}`);
  }
  return parseVisionJson(extractText(raw));
}

/** Pulls the first non-empty candidate text out of a `generateContent` body. */
function extractText(raw: string): string {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return '';
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
 * Lenient JSON verdict parse — the whole reason a capability hiccup degrades
 * to `failed` instead of a 502: strip fences, take the first {…} span, coerce
 * defensively. Anything unusable (no JSON, no summary and no labels) → null,
 * and null never invents a mismatch flag.
 */
export function parseVisionJson(raw: string): VisionVerdict | null {
  const stripped = raw.replace(/```[a-z]*/gi, '');
  const start = stripped.indexOf('{');
  const end = stripped.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripped.slice(start, end + 1));
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return null;
  }
  const o = parsed as Record<string, unknown>;

  const labels = Array.isArray(o.labels)
    ? o.labels
        .filter((l): l is string => typeof l === 'string')
        .map((l) => l.trim())
        .filter((l) => l.length > 0)
        .slice(0, 8)
        .map((l) => (l.length > 60 ? l.slice(0, 60) : l))
    : [];

  const summary = typeof o.summary === 'string' ? o.summary.trim().slice(0, 200) : '';
  if (summary.length === 0 && labels.length === 0) return null; // unusable

  const m =
    typeof o.mismatch === 'object' && o.mismatch !== null && !Array.isArray(o.mismatch)
      ? (o.mismatch as Record<string, unknown>)
      : {};

  return {
    summary,
    labels,
    visualCategory:
      typeof o.visualCategory === 'string' ? o.visualCategory.trim().slice(0, 120) : '',
    visualStyle: typeof o.visualStyle === 'string' ? o.visualStyle.trim().slice(0, 120) : '',
    // Never coerce truthy garbage into a flag — false negatives over false flags.
    mismatchFlagged: m.flagged === true,
    mismatchReason:
      typeof m.reason === 'string' ? m.reason.trim().slice(0, 200) : '',
  };
}

// ─── Persistence ─────────────────────────────────────────────────────────────

function failedVision(model: string, why: string): ProductVision {
  log(`[product-vision] ${why}`);
  return {
    status: 'failed',
    labels: [],
    visualCategory: '',
    visualStyle: '',
    summary: '',
    mismatch: { flagged: false, reason: '' },
    analyzedAt: new Date().toISOString(),
    model,
  };
}

/** Partial update only — never a full-doc write (same rule as `ar3d`). */
async function writeVision(productId: string, vision: ProductVision): Promise<void> {
  await fbDb().collection('products').doc(productId).update({ vision });
}

function log(message: string): void {
  console.log(message);
}
