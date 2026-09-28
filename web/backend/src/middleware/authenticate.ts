import type { Request, Response, NextFunction } from 'express';
import { ApiError } from '../lib/errors';
import { fbAuth } from '../config/firebase';

/**
 * Step 1 of the chain — AUTH CHECK.
 *
 * Verifies the `Authorization: Bearer <firebase-id-token>` header with the
 * Firebase Admin SDK and attaches the decoded identity to `req.user`.
 * Every route except `/api/health` and `/api/auth/login` runs this.
 */
export async function authenticate(req: Request, _res: Response, next: NextFunction): Promise<void> {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));
    return;
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));
    return;
  }
  try {
    const decoded = await fbAuth().verifyIdToken(token);
    req.user = {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: decoded.name ?? null,
      adminClaim: decoded.admin === true,
    };
    next();
  } catch (err) {
    if (err instanceof ApiError && err.code === 'FIREBASE_NOT_CONFIGURED') {
      next(err);
      return;
    }
    const message = (err as Error).message ?? '';
    if (message.includes('credential') || message.includes('not configured')) {
      next(new ApiError(503, 'FIREBASE_NOT_CONFIGURED', message));
      return;
    }
    // Token invalid/expired — never echo token material back.
    next(new ApiError(401, 'UNAUTHENTICATED', 'Invalid or expired sign-in token.'));
  }
}
