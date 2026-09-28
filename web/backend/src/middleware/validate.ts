import type { Request, Response, NextFunction } from 'express';
import type { ZodSchema } from 'zod';
import { ApiError } from '../lib/errors';

/**
 * Step 3 of the chain — INPUT VALIDATION.
 *
 * Zod-schema factories that parse and REPLACE req.body / req.query /
 * req.params with the typed, stripped result before the handler runs.
 * Failures become a 400 with per-field details.
 */
function run(schema: ZodSchema, value: unknown, where: string, next: NextFunction): void {
  const result = schema.safeParse(value);
  if (!result.success) {
    next(
      new ApiError(
        400,
        'VALIDATION_ERROR',
        `Invalid request ${where}.`,
        result.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message }))
      )
    );
    return;
  }
  next();
}

export const validateBody = (schema: ZodSchema) => (req: Request, _res: Response, next: NextFunction) =>
  run(schema, req.body ?? {}, 'body', next);

export const validateQuery = (schema: ZodSchema) => (req: Request, _res: Response, next: NextFunction) =>
  run(schema, req.query ?? {}, 'query', next);

export const validateParams = (schema: ZodSchema) => (req: Request, _res: Response, next: NextFunction) =>
  run(schema, req.params ?? {}, 'path', next);
