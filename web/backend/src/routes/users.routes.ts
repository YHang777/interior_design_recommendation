import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/authenticate';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody, validateParams, validateQuery } from '../middleware/validate';
import { asyncHandler } from '../lib/errors';
import { getUserDetail, listUsers } from '../services/users.service';
import { setSupplierVerification } from '../services/verification.service';
import { deleteAccount } from '../services/deletion.service';
import { generatePasswordResetLink, setTemporaryPassword } from '../services/identity.service';

/**
 * User administration routes.
 *
 * Chain on every route: authenticate → requireAdmin → validate → handler →
 * (handler delegates to services/, which own Firestore/Auth persistence).
 */

const uidParam = z.object({
  uid: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid Firebase UID.'),
});

const listQuery = z.object({
  role: z.enum(['all', 'homeowner', 'supplier']).default('all'),
  status: z.enum(['verified', 'pending', 'rejected']).optional(),
  q: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

const verificationBody = z.object({
  status: z.enum(['verified', 'pending', 'rejected']),
});

const passwordResetBody = z.object({
  mode: z.enum(['reset_link', 'temp_password']).default('reset_link'),
});

const deleteBody = z.object({
  confirmEmail: z
    .string()
    .trim()
    .min(3)
    .max(254)
    .email('Type the account email exactly to confirm deletion.'),
});

export const usersRouter = Router();

usersRouter.use(authenticate, requireAdmin);

/**
 * GET /api/users?role=&status=&q=&limit=&offset=
 * Customers (role=homeowner), suppliers (role=supplier) or everyone —
 * with product/order counts and search over email/name/business/uid.
 */
usersRouter.get(
  '/',
  validateQuery(listQuery),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as z.infer<typeof listQuery>;
    const result = await listUsers({
      role: q.role,
      status: q.status,
      q: q.q,
      limit: q.limit,
      offset: q.offset,
    });
    res.json(result);
  })
);

/** GET /api/users/:uid — full detail for one account. */
usersRouter.get(
  '/:uid',
  validateParams(uidParam),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as { uid: string };
    const user = await getUserDetail(uid);
    res.json({ user });
  })
);

/**
 * PATCH /api/users/:uid/verification
 * Body: { status: 'verified' | 'pending' | 'rejected' }
 * Approves/rejects a SUPPLIER. Writes users/{uid}.verificationStatus AND
 * syncs products/{id}.supplier.verificationStatus (the copy the buyer
 * marketplace's "Verified sellers only" filter reads).
 */
usersRouter.patch(
  '/:uid/verification',
  validateParams(uidParam),
  validateBody(verificationBody),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as { uid: string };
    const { status } = req.body as z.infer<typeof verificationBody>;
    const result = await setSupplierVerification(uid, status);
    res.json(result);
  })
);

/**
 * POST /api/users/:uid/password-reset
 * Body: { mode?: 'reset_link' | 'temp_password' }
 * - reset_link     → Firebase generatePasswordResetLink (user sets their
 *                    own password); link returned to the admin once.
 * - temp_password  → random one-time password via Admin updateUser;
 *                    returned once, never stored or logged.
 */
usersRouter.post(
  '/:uid/password-reset',
  validateParams(uidParam),
  validateBody(passwordResetBody),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as { uid: string };
    const { mode } = req.body as z.infer<typeof passwordResetBody>;
    if (mode === 'temp_password') {
      const result = await setTemporaryPassword(uid);
      res.json({ mode, email: result.email, tempPassword: result.tempPassword });
      return;
    }
    const result = await generatePasswordResetLink(uid);
    res.json({ mode, email: result.email, link: result.link });
  })
);

/**
 * DELETE /api/users/:uid
 * Body: { confirmEmail } — must match the target account's email exactly
 * (case-insensitive), mirroring the UI's type-to-confirm dialog.
 * Partial failures surface as 500 PARTIAL_DELETE and are retry-safe.
 */
usersRouter.delete(
  '/:uid',
  validateParams(uidParam),
  validateBody(deleteBody),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as { uid: string };
    const { confirmEmail } = req.body as z.infer<typeof deleteBody>;
    const result = await deleteAccount(uid, confirmEmail, req.user!.uid);
    res.json(result);
  })
);
