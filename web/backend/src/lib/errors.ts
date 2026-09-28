/**
 * Single error type for the whole API. Routes/services throw ApiError and
 * the error-handler middleware turns it into a JSON response — no password
 * material or stack traces ever reach the client.
 */
export class ApiError extends Error {
  readonly statusCode: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(statusCode: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

/** Wraps an async Express handler so rejections reach the error middleware
 * (Express 4 does not forward them automatically). */
export function asyncHandler<T extends (req: any, res: any, next: any) => Promise<any>>(fn: T) {
  return (req: any, res: any, next: any) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
