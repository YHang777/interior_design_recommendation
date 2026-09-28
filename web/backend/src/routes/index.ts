import { Router } from 'express';
import { authRouter } from './auth.routes';
import { usersRouter } from './users.routes';
import { statsRouter } from './stats.routes';
import { verificationRouter } from './verification.routes';
import { firebaseConfigured } from '../config/firebase';
import { verificationEmailConfigured } from '../services/verification-email.service';

export const apiRouter = Router();

/** GET /api/health (also /admin/api/health) — public liveness probe (no user data). */
apiRouter.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'interior-design-admin-api',
    firebaseConfigured: firebaseConfigured(),
    verificationEmailConfigured: verificationEmailConfigured(),
  });
});

apiRouter.use('/auth', authRouter);
apiRouter.use('/users', usersRouter);
apiRouter.use('/stats', statsRouter);
// IC + supporting documents — authenticate + requireAdmin applied inside.
apiRouter.use('/verification', verificationRouter);
