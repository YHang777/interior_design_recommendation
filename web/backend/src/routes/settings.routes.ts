import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { ApiError, asyncHandler } from '../lib/errors';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody } from '../middleware/validate';
import type { SettingsDeps } from '../services/settings.service';

const updateBody = z.object({
  taxRate: z
    .number({ invalid_type_error: 'Tax rate must be a number between 0 and 1.' })
    .finite('Tax rate must be a number between 0 and 1.')
    .min(0, 'Tax rate must be between 0 and 1.')
    .max(1, 'Tax rate must be between 0 and 1.'),
});

export function createSettingsRouter(deps: SettingsDeps): Router {
  const router = Router();

  router.use(deps.authorize, requireAdmin);

  router.get(
    '/',
    asyncHandler(async (_req: Request, res: Response) => {
      res.json({ settings: await deps.get() });
    })
  );

  router.patch(
    '/',
    validateBody(updateBody),
    asyncHandler(async (req: Request, res: Response) => {
      const { taxRate } = updateBody.parse(req.body ?? {});
      const uid = req.user?.uid;
      if (!uid) {
        throw new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.');
      }
      res.json({ settings: await deps.update(taxRate, uid) });
    })
  );

  return router;
}
