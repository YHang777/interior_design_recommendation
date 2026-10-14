import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody, validateParams, validateQuery } from '../middleware/validate';
import {
  type ProductFlagsDeps,
  type ProductFlagStatusFilter,
} from '../services/product-flags.service';

/**
 * `/api/products/flags` — the admin console's photo-vs-claim review queue.
 *
 *   GET   /api/products/flags?status=open|resolved|all → {items, total}
 *   PATCH /api/products/flags/:productId  {status, note?} → {item}
 *
 * Chain: authenticate → requireAdmin → validate → handler. Buyers and
 * sellers never reach these handlers: the rows contain seller copy and the
 * PATCH writes a server-owned field (`vision.review`) that decides whether
 * a listing stays under review.
 */

const productIdParams = z.object({
  productId: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid product id.'),
});

const listQuery = z.object({
  status: z.enum(['open', 'resolved', 'all']).default('open'),
});

const reviewBody = z.object({
  status: z.enum(['resolved', 'open']),
  note: z.string().trim().max(1000, 'Review notes are capped at 1000 characters.').optional(),
});

const STATUSES: ProductFlagStatusFilter[] = ['open', 'resolved', 'all'];

export function createProductFlagsRouter(deps: ProductFlagsDeps): Router {
  const router = Router();

  router.use(deps.authorize, requireAdmin);

  /**
   * GET /api/products/flags?status=…
   * The query middleware validates; the raw Express query stays strings,
   * so the handler normalises it against the same three values.
   */
  router.get(
    '/flags',
    validateQuery(listQuery),
    asyncHandler(async (req: Request, res: Response) => {
      const raw = typeof req.query.status === 'string' ? req.query.status : 'open';
      const status = (STATUSES as string[]).includes(raw)
        ? (raw as ProductFlagStatusFilter)
        : 'open';
      res.json(await deps.list(status));
    })
  );

  /** PATCH /api/products/flags/:productId — resolve or reopen one flag. */
  router.patch(
    '/flags/:productId',
    validateParams(productIdParams),
    validateBody(reviewBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { productId } = req.params as { productId: string };
      const body = reviewBody.parse(req.body ?? {});
      const adminUid = req.user?.uid;
      if (!adminUid) {
        // requireAdmin already guarantees a user — belt and braces so the
        // reviewedBy stamp can never be blank.
        throw new ApiError(401, 'UNAUTHENTICATED', 'Authentication required.');
      }
      try {
        const item = await deps.setReview(
          productId,
          body.status,
          body.note,
          adminUid
        );
        res.json({ item });
      } catch (err) {
        if (err instanceof ApiError) throw err;
        deps.log?.(`[product-flags] review write failed: ${(err as Error).message}`);
        throw new ApiError(
          500,
          'REVIEW_WRITE_FAILED',
          'We could not save that review. Try again.'
        );
      }
    })
  );

  return router;
}
