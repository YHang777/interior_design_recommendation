import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/errors';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody, validateParams, validateQuery } from '../middleware/validate';
import type { OrdersDeps } from '../services/orders.service';

const orderIdParams = z.object({
  id: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid order id.'),
});

const listQuery = z.object({
  status: z.enum(['pending', 'confirmed', 'shipped', 'delivered', 'cancelled']).optional(),
  q: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const statusBody = z.object({
  status: z.enum(['pending', 'confirmed', 'shipped', 'delivered', 'cancelled']),
});

export function createOrdersRouter(deps: OrdersDeps): Router {
  const router = Router();

  router.use(deps.authorize, requireAdmin);

  router.get(
    '/',
    validateQuery(listQuery),
    asyncHandler(async (req: Request, res: Response) => {
      const q = listQuery.parse(req.query);
      res.json(
        await deps.list({
          status: q.status,
          q: q.q,
          limit: q.limit,
          offset: q.offset,
        })
      );
    })
  );

  router.get(
    '/:id',
    validateParams(orderIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      res.json({ order: await deps.get(id) });
    })
  );

  router.patch(
    '/:id',
    validateParams(orderIdParams),
    validateBody(statusBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      const { status } = statusBody.parse(req.body ?? {});
      res.json({ order: await deps.setStatus(id, status) });
    })
  );

  return router;
}
