import type { Request, Response, NextFunction } from 'express';
import { ApiError } from '../lib/errors';

/**
 * Step 5 (failure path) of the chain — CENTRAL ERROR HANDLER.
 *
 * Every error thrown anywhere downstream lands here and is rendered as
 * `{ error: { code, message, details? } }`. Request bodies are never
 * logged (they may contain passwords), stacks stay server-side only.
 */
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  if (res.headersSent) {
    return;
  }

  let status = 500;
  let code = 'INTERNAL_ERROR';
  let message = 'Unexpected server error.';
  let details: unknown;

  if (err instanceof ApiError) {
    status = err.statusCode;
    code = err.code;
    message = err.message;
    details = err.details;
  } else if (isZodError(err)) {
    status = 400;
    code = 'VALIDATION_ERROR';
    message = 'Invalid request body.';
    details = err.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
  } else {
    // Unknown error — log it server-side, but send only a generic message.
    console.error(`[error] ${req.method} ${req.originalUrl}:`, err instanceof Error ? err.message : err);
  }

  if (status >= 500 && err instanceof ApiError) {
    console.error(`[error] ${req.method} ${req.originalUrl}: ${err.code}: ${err.message}`);
  }

  res.status(status).json({ error: { code, message, ...(details !== undefined ? { details } : {}) } });
}

function isZodError(err: unknown): err is { name: string; issues: { path: (string | number)[]; message: string }[] } {
  return (
    typeof err === 'object' &&
    err !== null &&
    (err as { name?: string }).name === 'ZodError' &&
    Array.isArray((err as { issues?: unknown }).issues)
  );
}

/** 404 fallback for unknown API paths. */
export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: `No route for ${req.method} ${req.path}` } });
}
