import type { Request } from 'express';

/** Identity attached by the `authenticate` middleware after a successful
 * Firebase ID-token verification. */
export interface AuthedUser {
  uid: string;
  email: string | null;
  name: string | null;
  /** True when the Firebase custom claim `{ admin: true }` is present. */
  adminClaim: boolean;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthedUser;
    }
  }
}

/** Narrow an Express request to one that passed `authenticate`. */
export function requireUser(req: Request): AuthedUser {
  if (!req.user) {
    throw new Error('requireUser called before authenticate middleware');
  }
  return req.user;
}

export {};
