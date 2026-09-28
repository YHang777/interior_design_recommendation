import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/authenticate';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody } from '../middleware/validate';
import { asyncHandler, ApiError } from '../lib/errors';
import { fbAuth, fbDb } from '../config/firebase';
import { signInWithPassword } from '../services/identity.service';
import { env } from '../config/env';

const loginSchema = z.object({
  email: z.string().trim().min(3).max(254).email('A valid email is required.'),
  password: z.string().min(1, 'Password is required.').max(128),
});

export const authRouter = Router();

/**
 * POST /api/auth/login — PUBLIC.
 * The frontend's only unauthenticated endpoint: proxies the password to
 * Identity Toolkit and returns a Firebase ID token IF the account is an
 * admin (allowlist or custom claim). The frontend never touches Firebase.
 */
authRouter.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const { email, password } = req.body as z.infer<typeof loginSchema>;
    const signIn = await signInWithPassword(email, password);

    let adminClaim = false;
    try {
      const decoded = await fbAuth().verifyIdToken(signIn.idToken);
      adminClaim = decoded.admin === true;
      const isAdmin = adminClaim || env.adminUids.includes(decoded.uid);
      if (!isAdmin) {
        throw new ApiError(403, 'NOT_ADMIN', 'This account is not an administrator.');
      }
      const profileSnap = await fbDb().collection('users').doc(decoded.uid).get();
      res.json({
        uid: decoded.uid,
        email: signIn.email,
        idToken: signIn.idToken,
        expiresIn: signIn.expiresIn,
        isAdmin: true,
        profile: profileSnap.exists ? profileSnap.data() : null,
      });
    } catch (err) {
      if (err instanceof ApiError) throw err;
      const message = (err as Error).message ?? '';
      if (message.includes('credential') || message.includes('not configured')) {
        throw new ApiError(503, 'FIREBASE_NOT_CONFIGURED', message);
      }
      throw new ApiError(502, 'IDENTITY_TOOLKIT_ERROR', 'Could not complete sign-in.');
    }
  })
);

/**
 * GET /api/auth/me — auth + admin. Validates the stored token and returns
 * who the caller is.
 */
authRouter.get(
  '/me',
  authenticate,
  requireAdmin,
  asyncHandler(async (req, res) => {
    const user = req.user!;
    const profileSnap = await fbDb().collection('users').doc(user.uid).get();
    res.json({
      uid: user.uid,
      email: user.email,
      name: user.name,
      isAdmin: true,
      adminViaClaim: user.adminClaim,
      profile: profileSnap.exists ? profileSnap.data() : null,
    });
  })
);
