import path from 'node:path';
import fs from 'node:fs';
import express from 'express';
import cors from 'cors';
import { apiRouter } from './routes/index';
import { createVerifyEmailRouter } from './routes/verify-email.routes';
import { defaultVerifyEmailDeps } from './services/verification-email.service';
import { createAiChatRouter } from './routes/ai-chat.routes';
import { defaultAiChatDeps } from './services/ai-chat.service';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import { env } from './config/env';

/** Where the built admin SPA lives (shared by the mounts and the boot log). */
export function resolveAdminStaticDir(): string {
  return env.adminStaticDir || path.resolve(__dirname, '../../frontend/dist');
}

/**
 * Express app assembly for the UNIFIED Intellar web host — one service, one
 * URL (this process owns `interior-design-recommendation.onrender.com`):
 *
 *   /verify-email/*   email verification API + confirm page (the flow the
 *                     mobile app calls; port of the Dart server's routes)
 *   /api/ai/*         design assistant for the mobile app (authenticated
 *                     proxy onto Gemini — the API key stays server-side)
 *   /admin            the React admin console (static SPA)
 *   /admin/api/*      admin API (auth, users, stats, IC review)
 *   /api/*            same admin API — kept as an alias for local dev and
 *                     Render health checks
 *   /                 redirects to /admin
 *
 * Middleware order IS the chain:
 *
 *   CORS (locked to FRONTEND_ORIGIN; only matters for split-origin dev)
 *     → JSON body parsing
 *       → /verify-email routes
 *         → /api/ai routes (authenticate → validate → Gemini)
 *           → /api + /admin/api routes (each composed of authenticate →
 *             requireAdmin → validate → handler → services/ persistence)
 *             → SPA static + fallback → 404 → central error handler
 */
export function createApp(): express.Express {
  const app = express();

  app.disable('x-powered-by');
  app.use(
    cors({
      // Exact-match lock: the CORS header is only issued for the configured
      // frontend origin — any other origin gets no ACAO header at all.
      // (Same-origin requests — the deployed SPA talking to /admin/api on its
      // own host — never need CORS headers either way.)
      origin: (origin, callback) => {
        if (origin && origin === env.frontendOrigin) {
          callback(null, origin);
        } else {
          callback(null, false);
        }
      },
      methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    })
  );
  app.use(express.json({ limit: '128kb' }));

  // Email verification for the mobile app (registration flow).
  app.use('/verify-email', createVerifyEmailRouter(defaultVerifyEmailDeps()));

  // Design assistant for the mobile app. Mounted ahead of the admin /api
  // alias so the path is claimed explicitly, and authenticated: it is a
  // proxy onto a paid model, so it is never left open.
  app.use('/api/ai', createAiChatRouter(defaultAiChatDeps()));

  // Admin API — mounted at the unified path AND the plain /api alias.
  app.use('/api', apiRouter);
  app.use('/admin/api', apiRouter);

  // Root: a human typing the bare URL lands on the admin console.
  app.get('/', (_req, res) => {
    res.redirect('/admin');
  });

  // Admin SPA (built web/frontend → Vite dist). Optional at runtime so the
  // API can run standalone (e.g. local backend-only dev).
  const staticDir = resolveAdminStaticDir();
  const indexHtml = path.join(staticDir, 'index.html');
  if (fs.existsSync(indexHtml)) {
    // Exact /admin first — express.static would otherwise redirect it to
    // /admin/ before serving the shell.
    app.get('/admin', (_req, res) => {
      res.sendFile(indexHtml);
    });
    app.use('/admin', express.static(staticDir, { index: 'index.html' }));
    // SPA fallback: any /admin/… path that is not /admin/api/… and not a real
    // file serves the console shell (future-proof for client-side routes).
    app.get('/admin/*', (req, res, next) => {
      if (req.path.startsWith('/admin/api')) return next();
      res.sendFile(indexHtml);
    });
  } else {
    app.get('/admin', (_req, res) => {
      res
        .status(503)
        .type('text')
        .send(
          'Admin console assets are not built. Run `npm run build` in web/frontend ' +
            '(or build the unified Docker image, which does it for you). ' +
            `Looked for: ${indexHtml}`
        );
    });
  }

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
