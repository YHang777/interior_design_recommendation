import { Router } from 'express';
import { authRouter } from './auth.routes';
import { usersRouter } from './users.routes';
import { statsRouter } from './stats.routes';
import { verificationRouter } from './verification.routes';
import { createProductFlagsRouter } from './product-flags.routes';
import { defaultProductFlagsDeps } from '../services/product-flags.service';
import { createProductsRouter } from './products.routes';
import { defaultProductsDeps } from '../services/products.service';
import { createOrdersRouter } from './orders.routes';
import { defaultOrdersDeps } from '../services/orders.service';
import { createSettingsRouter } from './settings.routes';
import { defaultSettingsDeps } from '../services/settings.service';
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
// Photo-vs-claim review queue — authenticate + requireAdmin applied inside.
apiRouter.use('/products', createProductFlagsRouter(defaultProductFlagsDeps()));
// Catalogue CRUD — mounted AFTER the flags router so /products/flags* keeps
// winning the match; this router owns GET / and GET|PATCH|DELETE /:id.
apiRouter.use('/products', createProductsRouter(defaultProductsDeps()));
// Order list/detail/status — authenticate + requireAdmin applied inside.
apiRouter.use('/orders', createOrdersRouter(defaultOrdersDeps()));
// Marketplace-wide settings (tax rate) — authenticate + requireAdmin applied inside.
apiRouter.use('/settings', createSettingsRouter(defaultSettingsDeps()));
