import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody, validateParams, validateQuery } from '../middleware/validate';
import type { ProductsDeps } from '../services/products.service';

const productIdParams = z.object({
  id: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid product id.'),
});

const listQuery = z.object({
  q: z.string().max(200).optional(),
  category: z.string().max(100).optional(),
  status: z.enum(['all', 'active', 'inactive']).default('all'),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const CATEGORIES = [
  'Furniture',
  'Lighting',
  'Decor',
  'Paint',
  'Flooring',
  'Textiles',
  'Wall Covering',
] as const;

const STYLES = [
  'Modern',
  'Classic',
  'Industrial',
  'Scandinavian',
  'Bohemian',
  'Minimalist',
] as const;

const updateBody = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    description: z.string().trim().max(4000).optional(),
    category: z.enum(CATEGORIES).optional(),
    designStyle: z.enum(STYLES).optional(),
    price: z.number().int().min(0).max(10_000_000).optional(),
    originalPrice: z.number().int().min(0).max(10_000_000).nullable().optional(),
    stock: z.number().int().min(0).max(1_000_000).optional(),
    isActive: z.boolean().optional(),
    isEcoFriendly: z.boolean().optional(),
    shippingEnabled: z.boolean().optional(),
    shippingFee: z.number().int().min(0).max(100_000).optional(),
    shippingLongDistanceNotice: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: 'Provide at least one field to update.',
  });

export function createProductsRouter(deps: ProductsDeps): Router {
  const router = Router();

  router.use(deps.authorize, requireAdmin);

  router.get(
    '/',
    validateQuery(listQuery),
    asyncHandler(async (req: Request, res: Response) => {
      const q = listQuery.parse(req.query);
      res.json(
        await deps.list({
          q: q.q,
          category: q.category,
          status: q.status,
          limit: q.limit,
          offset: q.offset,
        })
      );
    })
  );

  router.get(
    '/:id',
    validateParams(productIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      res.json({ product: await deps.get(id) });
    })
  );

  router.patch(
    '/:id',
    validateParams(productIdParams),
    validateBody(updateBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      const patch = updateBody.parse(req.body ?? {});
      res.json({ product: await deps.update(id, patch) });
    })
  );

  router.delete(
    '/:id',
    validateParams(productIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      res.json(await deps.remove(id));
    })
  );

  return router;
}
