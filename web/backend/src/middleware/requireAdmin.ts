import type { Request, Response, NextFunction } from 'express';
import { ApiError } from '../lib/errors';
import { env } from '../config/env';

/**
 * Step 2 of the chain — ADMIN ROLE CHECK.
 *
 * The caller is an admin when EITHER:
 *   - the ID token carries the custom claim `{ admin: true }` (set with
 *     `npm run claim-admin -- <uid>`), OR
 *   - the UID is listed in the `ADMIN_UIDS` env allowlist.
 *
 * Applied to every authenticated route — reads (user PII) and writes alike.
 */
export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  const user = req.user;
  if (!user) {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Authentication required.'));
    return;
  }
  if (user.adminClaim || env.adminUids.includes(user.uid)) {
    next();
    return;
  }
  next(
    new ApiError(
      403,
      'NOT_ADMIN',
      'This account is not an administrator. Add its UID to ADMIN_UIDS or grant the admin custom claim.'
    )
  );
}
