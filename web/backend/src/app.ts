import express from 'express';
import cors from 'cors';
import { apiRouter } from './routes/index';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import { env } from './config/env';

/**
 * Express app assembly. Middleware order IS the chain:
 *
 *   CORS (locked to FRONTEND_ORIGIN)
 *     → JSON body parsing
 *       → /api routes (each composed of authenticate → requireAdmin →
 *         validate → handler → services/ persistence)
 *         → 404 → central error handler
 */
export function createApp(): express.Express {
  const app = express();

  app.disable('x-powered-by');
  app.use(
    cors({
      // Exact-match lock: the CORS header is only issued for the configured
      // frontend origin — any other origin gets no ACAO header at all.
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

  app.use('/api', apiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
