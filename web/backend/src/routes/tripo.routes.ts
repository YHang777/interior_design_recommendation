import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody, validateParams } from '../middleware/validate';
import {
  TripoException,
  type TripoDeps,
  type TripoPassthrough,
  type TripoSubmitRequest,
} from '../services/tripo.service';

/**
 * `/api/tripo/*` — the 3D-generation proxy used by the mobile app.
 *
 *   POST /api/tripo/generation/image-to-model  {input, …} → Tripo's reply
 *   GET  /api/tripo/tasks/:taskId                        → Tripo's reply
 *
 * AUTHENTICATED, for the same reason `/api/ai/chat` is: Tripo is pay-as-you-go
 * (~US$0.30 per textured model) and an open relay is a bill waiting to happen.
 * The key never leaves this server — the app sends a public photo URL and
 * receives task state.
 *
 * The two JSON routes are pass-throughs on purpose (see tripo.service.ts): the
 * app's retry policy reads Tripo's HTTP status and its `{code, data}` envelope,
 * so both are forwarded verbatim. What THIS layer owns is the contract in
 * front of Tripo — who may call, what they may send, and which model version
 * gets billed.
 */

const submitBodySchema = z.object({
  /** PUBLIC image URL. Tripo fetches it server-side; there is no upload API. */
  input: z.string().url().max(2_000),
  texture: z.boolean().optional(),
  pbr: z.boolean().optional(),
  face_limit: z.number().int().positive().max(500_000).optional(),
  auto_size: z.boolean().optional(),
});

/**
 * Tripo task ids are `task_` + an opaque token. Locked down to URL-safe
 * characters so a crafted id cannot path-traverse the upstream URL.
 */
const taskParamsSchema = z.object({
  taskId: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Invalid task id.'),
});

export function createTripoRouter(deps: TripoDeps): Router {
  const router = Router();

  router.post(
    '/generation/image-to-model',
    deps.authorize,
    validateBody(submitBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      if (!deps.isConfigured()) {
        throw new ApiError(
          503,
          'NOT_CONFIGURED',
          '3D generation is not set up yet. Try again later.'
        );
      }

      const parsed = submitBodySchema.parse(req.body ?? {});
      const request: TripoSubmitRequest = {
        input: parsed.input,
        texture: parsed.texture,
        pbr: parsed.pbr,
        faceLimit: parsed.face_limit,
        autoSize: parsed.auto_size,
      };

      deps.log?.(`[tripo] submit image-to-model for ${redactUrl(parsed.input)}`);
      sendPassthrough(res, await runOrThrow(deps, () => deps.submit(request)));
    })
  );

  router.get(
    '/tasks/:taskId',
    deps.authorize,
    validateParams(taskParamsSchema),
    asyncHandler(async (req: Request, res: Response) => {
      if (!deps.isConfigured()) {
        throw new ApiError(
          503,
          'NOT_CONFIGURED',
          '3D generation is not set up yet. Try again later.'
        );
      }

      const { taskId } = taskParamsSchema.parse(req.params ?? {});
      sendPassthrough(res, await runOrThrow(deps, () => deps.query(taskId)));
    })
  );

  return router;
}

/**
 * Runs an upstream call and maps a service failure onto an HTTP status with a
 * sentence for the seller waiting on a model. The Tripo diagnostic stays in
 * the log — it names keys and HTTP codes, which mean nothing to a seller.
 */
async function runOrThrow(
  deps: TripoDeps,
  call: () => Promise<TripoPassthrough>
): Promise<TripoPassthrough> {
  try {
    return await call();
  } catch (err) {
    if (err instanceof TripoException) {
      deps.log?.(`[tripo] ${err.kind}: ${err.message}`);
      throw toApiError(err);
    }
    throw err;
  }
}

function toApiError(err: TripoException): ApiError {
  switch (err.kind) {
    case 'not-configured':
      return new ApiError(
        503,
        'NOT_CONFIGURED',
        '3D generation is not set up yet. Try again later.'
      );
    case 'timeout':
      return new ApiError(
        504,
        'UPSTREAM_TIMEOUT',
        '3D generation took too long to respond. Try again.'
      );
    case 'invalid':
      return new ApiError(400, 'VALIDATION_ERROR', 'Invalid 3D generation request.');
    case 'upstream':
      return new ApiError(
        502,
        'UPSTREAM_ERROR',
        '3D generation could not be reached. Try again.'
      );
  }
}

/**
 * Forwards an upstream reply untouched. Status and body are load-bearing for
 * the client (see the module doc) — only the content type is normalised, and
 * only when Tripo omitted one.
 */
function sendPassthrough(res: Response, upstream: TripoPassthrough): void {
  res.status(upstream.statusCode);
  res.set('Content-Type', upstream.contentType);
  res.send(upstream.body);
}

/**
 * Host + path only. The `input` is a product photo URL the seller already
 * published; the query string can carry signed tokens, so it never reaches the
 * log.
 */
function redactUrl(raw: string): string {
  try {
    const u = new URL(raw);
    return `${u.host}${u.pathname}`;
  } catch {
    return '(unparseable url)';
  }
}
