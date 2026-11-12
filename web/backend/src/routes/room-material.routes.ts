import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { requireUser } from '../middleware/types';
import type { RoomMaterialDeps } from '../services/room-material.service';

/**
 * `/api/ai/analyze-room-material` — material scan for the room scanner.
 *
 *   POST /api/ai/analyze-room-material   {imageBase64, mimeType?} →
 *     {status, message?, floor?, wall?}
 *
 * The body carries the camera still itself (base64 — no third-party key or
 * upload service may live in the app). Authenticated (Firebase ID token),
 * and never a scan blocker: every analysis outcome is a 200 with
 * `status: 'ok' | 'failed'`, and unknown surfaces are omitted.
 */

const analyzeBodySchema = z.object({
  imageBase64: z
    .string()
    .trim()
    .min(8)
    .max(14_000_000),
  mimeType: z
    .enum(['image/jpeg', 'image/png', 'image/webp'])
    .optional(),
});

export function createRoomMaterialRouter(deps: RoomMaterialDeps): Router {
  const router = Router();

  router.post(
    '/analyze-room-material',
    deps.authorize,
    validateBody(analyzeBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      if (!deps.isConfigured()) {
        throw new ApiError(
          503,
          'NOT_CONFIGURED',
          'Room material scan is not configured yet.'
        );
      }

      const { imageBase64, mimeType } = analyzeBodySchema.parse(req.body ?? {});
      // Authenticated principal required — the analyzer runs on the caller's
      // own frame, so there is nothing else to authorize.
      requireUser(req);

      let result;
      try {
        result = await deps.analyze(imageBase64, mimeType ?? 'image/jpeg');
      } catch (err) {
        if (err instanceof ApiError) throw err;
        deps.log?.(`[room-material] analyze threw: ${(err as Error).message}`);
        throw new ApiError(
          500,
          'ANALYSIS_FAILED',
          'We could not read the room materials right now.'
        );
      }

      res.json(result);
    })
  );

  return router;
}
