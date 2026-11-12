import type { RequestHandler } from 'express';
import { env } from '../config/env';
import { authenticate } from '../middleware/authenticate';

/**
 * Room-finish recognition for the scanner (`POST /api/ai/analyze-room-material`).
 *
 * The app's material scan used to throw away exactly the surface labels ML Kit
 * saw. This endpoint is the replacement: one camera still goes to Gemini
 * vision and comes back as the app's own finish vocabulary, so the client can
 * match `RoomFinishCatalog` and apply it. Same key rule as chat/Tripo/product
 * vision: the Gemini key lives HERE only.
 *
 * The contract is never-blocking: after auth every outcome is a 200 with
 * `status: 'ok' | 'failed'` — a model hiccup must never break the scan flow.
 * Unknown surfaces are omitted, never invented: an absent floor means "keep
 * what the room has".
 */

export type FloorMaterial = 'woodPlanks' | 'cement' | 'ceramicTiles' | 'parquet';
export type WallMaterial = 'paint' | 'woodPanels' | 'brick';

export interface RoomSurfaceGuess<T> {
  material: T;
  /** Dominant surface colour, `#RRGGBB` when the model gave a usable one. */
  hex?: string;
}

export interface AnalyzeRoomMaterialResult {
  status: 'ok' | 'failed';
  /** Short user-safe sentence; only present when `status` is `failed`. */
  message?: string;
  floor?: RoomSurfaceGuess<FloorMaterial>;
  wall?: RoomSurfaceGuess<WallMaterial>;
}

/** Collaborators the route needs — injectable so tests never touch Gemini. */
export interface RoomMaterialDeps {
  isConfigured: () => boolean;
  analyze: (imageBase64: string, mimeType: string) => Promise<AnalyzeRoomMaterialResult>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultRoomMaterialDeps(): RoomMaterialDeps {
  return {
    isConfigured: () => env.geminiApiKey.trim().length > 0,
    analyze: (imageBase64, mimeType) => analyzeRoomMaterial(imageBase64, mimeType),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

const VISION_TIMEOUT_MS = 30_000;

// ─── Pipeline ────────────────────────────────────────────────────────────────

async function analyzeRoomMaterial(
  imageBase64: string,
  mimeType: string
): Promise<AnalyzeRoomMaterialResult> {
  const model = visionModel();

  let parsed: MaterialJson | null = null;
  try {
    parsed = await callVisionModel(model, imageBase64, mimeType);
  } catch (err) {
    // Google diagnostics are for the log, never the caller.
    log(`[room-material] upstream failed: ${(err as Error).message}`);
  }

  const floor = parsed ? normalizeFloor(parsed.floor) : undefined;
  const wall = parsed ? normalizeWall(parsed.wall) : undefined;
  if (floor || wall) {
    return { status: 'ok', floor, wall };
  }
  return {
    status: 'failed',
    message: 'We could not read the floor and wall in this frame.',
  };
}

function visionModel(): string {
  return env.geminiVisionModel.trim() || env.geminiModel;
}

// ─── Model call ──────────────────────────────────────────────────────────────

export function buildRoomMaterialPrompt(): string {
  return `You are identifying room finishes in a photo taken inside a home, for an interior-design app that can restyle the floor and walls.
Return ONLY a JSON object:
{"floor":{"material":"woodPlanks|cement|ceramicTiles|parquet|unknown","hex":"#RRGGBB"},"wall":{"material":"paint|woodPanels|brick|unknown","hex":"#RRGGBB"}}
Rules:
- floor.material: woodPlanks for plank boards, parquet for parquet blocks, ceramicTiles for tiles or stone tiles, cement for concrete or polished cement. Use "unknown" when the floor is not visible or none of these.
- wall.material: paint for plain painted walls, woodPanels for wood paneling or cladding, brick for exposed brick. Use "unknown" when no wall is visible or none of these.
- hex: the dominant colour of that surface as #RRGGBB.
- Describe the SURFACES only — ignore furniture, rugs, curtains and decor.`;
}

async function callVisionModel(
  model: string,
  imageBase64: string,
  mimeType: string
): Promise<MaterialJson | null> {
  const body = {
    contents: [
      {
        parts: [
          { text: buildRoomMaterialPrompt() },
          { inlineData: { mimeType, data: imageBase64 } },
        ],
      },
    ],
    generationConfig: {
      maxOutputTokens: 300,
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
  return parseMaterialJson(extractText(raw));
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

// ─── Lenient parse + vocabulary normalization ────────────────────────────────

export interface MaterialJson {
  floor: { material: string; hex: string } | null;
  wall: { material: string; hex: string } | null;
}

/**
 * Lenient parse — strip fences, take the first {…} span, coerce defensively.
 * Anything unusable returns nulls (never an invented surface).
 */
export function parseMaterialJson(raw: string): MaterialJson | null {
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
  return {
    floor: surfaceOf(o.floor),
    wall: surfaceOf(o.wall),
  };
}

function surfaceOf(v: unknown): { material: string; hex: string } | null {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return null;
  const s = v as Record<string, unknown>;
  const material = typeof s.material === 'string' ? s.material : '';
  const hex = typeof s.hex === 'string' ? s.hex : '';
  if (material.trim().length === 0 && hex.trim().length === 0) return null;
  return { material, hex };
}

const FLOOR_ALIASES: Record<string, FloorMaterial> = {
  woodplanks: 'woodPlanks',
  wood: 'woodPlanks',
  hardwood: 'woodPlanks',
  plank: 'woodPlanks',
  planks: 'woodPlanks',
  woodfloor: 'woodPlanks',
  woodfloors: 'woodPlanks',
  laminate: 'woodPlanks',
  timber: 'woodPlanks',
  cement: 'cement',
  concrete: 'cement',
  polishedconcrete: 'cement',
  polishedcement: 'cement',
  ceramictiles: 'ceramicTiles',
  ceramic: 'ceramicTiles',
  tile: 'ceramicTiles',
  tiles: 'ceramicTiles',
  porcelain: 'ceramicTiles',
  stone: 'ceramicTiles',
  stonetiles: 'ceramicTiles',
  parquet: 'parquet',
  parquetfloor: 'parquet',
  parquetflooring: 'parquet',
};

const WALL_ALIASES: Record<string, WallMaterial> = {
  paint: 'paint',
  painted: 'paint',
  paintedwall: 'paint',
  paintedwalls: 'paint',
  plaster: 'paint',
  drywall: 'paint',
  woodpanels: 'woodPanels',
  woodpanel: 'woodPanels',
  panelling: 'woodPanels',
  paneling: 'woodPanels',
  woodpaneling: 'woodPanels',
  woodpanelling: 'woodPanels',
  woodcladding: 'woodPanels',
  cladding: 'woodPanels',
  wainscoting: 'woodPanels',
  brick: 'brick',
  exposedbrick: 'brick',
  masonry: 'brick',
};

function foldToken(v: string): string {
  return v.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function normalizeFloorMaterial(raw: string): FloorMaterial | null {
  return FLOOR_ALIASES[foldToken(raw)] ?? null;
}

export function normalizeWallMaterial(raw: string): WallMaterial | null {
  return WALL_ALIASES[foldToken(raw)] ?? null;
}

/** `#RGB` / `#RRGGBB` (any case) → `#RRGGBB`; anything else → undefined. */
export function normalizeHex(raw: string): string | undefined {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(raw.trim());
  if (!m) return undefined;
  let hex = m[1].toUpperCase();
  if (hex.length === 3) {
    hex = hex
      .split('')
      .map((c) => c + c)
      .join('');
  }
  return `#${hex}`;
}

function normalizeFloor(
  s: { material: string; hex: string } | null
): RoomSurfaceGuess<FloorMaterial> | undefined {
  if (!s) return undefined;
  const material = normalizeFloorMaterial(s.material);
  if (!material) return undefined;
  const hex = normalizeHex(s.hex);
  return hex ? { material, hex } : { material };
}

function normalizeWall(
  s: { material: string; hex: string } | null
): RoomSurfaceGuess<WallMaterial> | undefined {
  if (!s) return undefined;
  const material = normalizeWallMaterial(s.material);
  if (!material) return undefined;
  const hex = normalizeHex(s.hex);
  return hex ? { material, hex } : { material };
}

function log(message: string): void {
  console.log(message);
}
