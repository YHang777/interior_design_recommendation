import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { asyncHandler, ApiError } from '../lib/errors';
import { validateBody, validateParams } from '../middleware/validate';
import type { CheckoutDeps } from '../services/checkout.service';
import { stripeConfigured } from '../services/checkout.service';

const orderIdParams = z.object({
  id: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid order id.'),
});

const intentBody = z.object({
  items: z
    .array(
      z.object({
        productId: z.string().min(1).max(128),
        quantity: z.number().int().min(1).max(99),
      })
    )
    .min(1)
    .max(50),
  customerName: z.string().trim().min(1).max(120),
  customerPhone: z.string().trim().min(6).max(32),
  membershipTier: z.string().trim().max(40).optional(),
});

function ensureStripe(): void {
  if (!stripeConfigured()) {
    throw new ApiError(
      503,
      'STRIPE_NOT_CONFIGURED',
      'Payments are not configured on this server yet.'
    );
  }
}

export function createCheckoutRouter(deps: CheckoutDeps): Router {
  const router = Router();

  // The app-authenticated checkout API. The Stripe webhook lives in app.ts
  // (it needs the raw body for signature verification, not express.json).
  router.use(deps.authorize);

  router.post(
    '/intents',
    validateBody(intentBody),
    asyncHandler(async (req: Request, res: Response) => {
      ensureStripe();
      const body = intentBody.parse(req.body ?? {});
      const user = req.user;
      if (!user) throw new ApiError(401, 'UNAUTHENTICATED', 'Sign in first.');
      const result = await deps.createIntent(
        user.uid,
        user.email,
        body.items,
        body.customerName,
        body.customerPhone
      );
      res.status(201).json(result);
    })
  );

  router.post(
    '/orders/:id/verify',
    validateParams(orderIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      const user = req.user;
      if (!user) throw new ApiError(401, 'UNAUTHENTICATED', 'Sign in first.');
      res.json(await deps.verify(user.uid, id));
    })
  );

  router.post(
    '/orders/:id/abandon',
    validateParams(orderIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      const { id } = req.params as { id: string };
      const user = req.user;
      if (!user) throw new ApiError(401, 'UNAUTHENTICATED', 'Sign in first.');
      await deps.abandon(user.uid, id);
      res.json({ ok: true });
    })
  );

  router.post(
    '/orders/:id/cancel',
    validateParams(orderIdParams),
    asyncHandler(async (req: Request, res: Response) => {
      ensureStripe();
      const { id } = req.params as { id: string };
      const user = req.user;
      if (!user) throw new ApiError(401, 'UNAUTHENTICATED', 'Sign in first.');
      res.json(await deps.cancel(user.uid, id));
    })
  );

  return router;
}
