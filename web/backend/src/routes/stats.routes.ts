import { Router } from 'express';
import { authenticate } from '../middleware/authenticate';
import { requireAdmin } from '../middleware/requireAdmin';
import { asyncHandler } from '../lib/errors';
import { getStats } from '../services/users.service';

export const statsRouter = Router();

/**
 * GET /api/stats — auth + admin. Headline counts for the overview page:
 * customers, suppliers (split by verification status), products, orders
 * and the five newest signups.
 */
statsRouter.get(
  '/',
  authenticate,
  requireAdmin,
  asyncHandler(async (_req, res) => {
    res.json(await getStats());
  })
);
