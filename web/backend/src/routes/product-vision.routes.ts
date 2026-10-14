import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { validateBody } from '../middleware/validate';
import { requireUser } from '../middleware/types';
import { env } from '../config/env';
import type { ProductVisionDeps } from '../services/product-vision.service';

/**
 * `/api/ai/analyze-product` — upload-time photo verification for listings.
 *
 *   POST /api/ai/analyze-product   {productId} → {status, message?, vision}
 *
 * The body carries ONLY the product id: claims and photos are read from
 * Firestore inside the service, so a caller cannot smuggle alternate text or
 * images past the check. Authenticated (Firebase ID token), ownership-checked
 * (supplier owns the product, or an admin), and never a save blocker — every
 * analysis outcome is a 200 with `status: 'ok' | 'failed'`.
 */

const analyzeBodySchema = z.object({
  productId: z
    .string()
    .trim()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Unexpected product id format.'),
});

export function createProductVisionRouter(deps: ProductVisionDeps): Router {
  const router = Router();

  router.post(
    '/analyze-product',
    deps.authorize,
    validateBody(analyzeBodySchema),
    asyncHandler(async (req: Request, res: Response) => {
      if (!deps.isConfigured()) {
        throw new ApiError(
          503,
          'NOT_CONFIGURED',
          'Photo analysis is not configured yet.'
        );
      }

      const { productId } = analyzeBodySchema.parse(req.body ?? {});
      const user = requireUser(req);
      const isAdmin =
        user.adminClaim || env.adminUids.includes(user.uid);

      let result;
      try {
        result = await deps.analyze(productId, user.uid, isAdmin);
      } catch (err) {
        if (err instanceof ApiError) throw err; // 404 / 403 pass through
        deps.log?.(`[product-vision] analyze threw: ${(err as Error).message}`);
        throw new ApiError(
          500,
          'ANALYSIS_FAILED',
          'We could not check this photo right now.'
        );
      }

      res.json(result);
    })
  );

  return router;
}
