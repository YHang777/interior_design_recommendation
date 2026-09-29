import type { RequestHandler } from 'express';
import { env } from '../config/env';
import { authenticate } from '../middleware/authenticate';

/**
 * Server-side Tripo 3D calls behind `/api/tripo/*`.
 *
 * The API key lives HERE and only here. The Flutter app used to hold it in
 * `lib/config/local_config.dart`, which meant every built APK shipped a copy
 * of a paid credential — anything compiled into a mobile binary can be pulled
 * out of it. Now the app sends a photo URL and gets task state back; it never
 * sees the key, the Tripo host or the model version.
 *
 * Deliberately a THIN pass-through for the two JSON endpoints: Tripo's reply
 * body (`{code, data}`) and its HTTP status go back to the app verbatim. The
 * client's retry policy keys off those statuses (429/5xx = worth retrying,
 * 401/402/4xx = not), so collapsing them into a generic 500 would break both
 * the error messages and the "re-polling is free, re-submitting is billed"
 * rule the generator depends on. Proxy-level failures (no key, bad token, bad
 * request) are the only ones this file shapes itself.
 */

/** One image-to-model submission, as the app sends it. */
export interface TripoSubmitRequest {
  /** PUBLIC image URL — Tripo fetches it server-side; no file upload exists. */
  input: string;
  texture?: boolean;
  pbr?: boolean;
  faceLimit?: number;
  autoSize?: boolean;
}

/**
 * Raw upstream reply, forwarded untouched. Only the shape the proxy itself
 * needs is declared; everything else rides along in the body.
 */
export interface TripoPassthrough {
  statusCode: number;
  /** Raw response body, forwarded byte-for-byte (JSON text). */
  body: string;
  contentType: string;
}

/** Why a request could not reach Tripo at all — maps 1:1 onto an HTTP status. */
export type TripoFailure = 'not-configured' | 'invalid' | 'timeout' | 'upstream';

export class TripoException extends Error {
  constructor(
    readonly kind: TripoFailure,
    message: string
  ) {
    super(message);
    this.name = 'TripoException';
  }
}

/** Collaborators the routes need — injectable so tests can fake them. */
export interface TripoDeps {
  isConfigured: () => boolean;
  /** POST /generation/image-to-model → raw upstream reply. */
  submit: (req: TripoSubmitRequest) => Promise<TripoPassthrough>;
  /** GET /tasks/{taskId} → raw upstream reply. */
  query: (taskId: string) => Promise<TripoPassthrough>;
  /**
   * Auth step. Defaults to the real Firebase ID-token check; tests swap it
   * out so they never need a live credential.
   */
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultTripoDeps(): TripoDeps {
  return {
    isConfigured: () => env.tripoApiKey.trim().length > 0,
    submit: (req) => submitImageToModel(req),
    query: (taskId) => queryTask(taskId),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

/** Tripo holds a task open for minutes; the client polls every 5s. */
const UPSTREAM_TIMEOUT_MS = 30_000;

async function submitImageToModel(req: TripoSubmitRequest): Promise<TripoPassthrough> {
  // `model` is server-owned: a Tripo version bump is one env var on Render,
  // not an app release, and the client has no say in what gets billed.
  const body = {
    input: req.input,
    texture: req.texture ?? true,
    pbr: req.pbr ?? true,
    face_limit: req.faceLimit ?? 100_000,
    auto_size: req.autoSize ?? true,
    model: env.tripoModelVersion,
  };
  return forward('POST', '/generation/image-to-model', body);
}

async function queryTask(taskId: string): Promise<TripoPassthrough> {
  return forward('GET', `/tasks/${encodeURIComponent(taskId)}`);
}

/**
 * One hop to Tripo. The auth header is added HERE — the only place the key
 * exists — and the upstream status/body are handed back untouched.
 */
async function forward(
  method: 'GET' | 'POST',
  path: string,
  body?: unknown
): Promise<TripoPassthrough> {
  const apiKey = env.tripoApiKey.trim();
  if (apiKey.length === 0) {
    throw new TripoException('not-configured', 'TRIPO_API_KEY is not set.');
  }

  const url = `${env.tripoBaseUrl.replace(/\/+$/, '')}${path}`;

  let resp: Response;
  try {
    resp = await fetch(url, {
      method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (err) {
    if (err instanceof Error && err.name === 'TimeoutError') {
      throw new TripoException('timeout', 'Tripo request timed out.');
    }
    throw new TripoException(
      'upstream',
      `Tripo request failed: ${(err as Error).message}`
    );
  }

  // The body is forwarded byte-for-byte. On a non-2xx it is a Tripo
  // diagnostic for the logs, not a sentence for the seller waiting on a
  // model — the client maps the HTTP status to its own short message.
  const text = await resp.text();
  const contentType =
    resp.headers.get('content-type') ??
    (text.trimStart().startsWith('{') ? 'application/json' : 'text/plain');

  return { statusCode: resp.status, body: text, contentType };
}
