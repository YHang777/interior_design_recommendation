import { randomBytes } from 'node:crypto';
import type { UserRecord } from 'firebase-admin/auth';
import { ApiError } from '../lib/errors';
import { env } from '../config/env';
import { fbAuth } from '../config/firebase';

/**
 * Firebase Identity Toolkit / Auth operations used by the admin API.
 * Everything in this module runs server-side; no password material is ever
 * logged or stored — reset links are generated on demand and temporary
 * passwords are random, returned exactly once, and never persisted.
 */

export interface SignInResult {
  uid: string;
  email: string;
  idToken: string;
  expiresIn: string;
}

/**
 * Password sign-in proxy. The frontend never talks to Firebase: it posts
 * {email, password} here, and the backend calls Identity Toolkit
 * `accounts:signInWithPassword` with the Web API key, returning an ID token
 * that the frontend then presents as a Bearer token on every request.
 */
export async function signInWithPassword(email: string, password: string): Promise<SignInResult> {
  if (!env.webApiKey) {
    throw new ApiError(
      503,
      'LOGIN_NOT_CONFIGURED',
      'FIREBASE_WEB_API_KEY is not configured on the server; password sign-in is unavailable.'
    );
  }
  const resp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(env.webApiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    }
  );
  const body = (await resp.json().catch(() => ({}))) as {
    idToken?: string;
    refreshToken?: string;
    expiresIn?: string;
    localId?: string;
    email?: string;
    error?: { message?: string };
  };
  if (!resp.ok || !body.idToken || !body.localId) {
    // Identity Toolkit error codes like INVALID_PASSWORD — mapped to a
    // generic message so the API never leaks which field was wrong.
    const fbCode = body.error?.message ?? 'UNKNOWN';
    if (fbCode === 'EMAIL_NOT_FOUND' || fbCode === 'INVALID_PASSWORD' || fbCode === 'INVALID_LOGIN_CREDENTIALS') {
      throw new ApiError(401, 'BAD_CREDENTIALS', 'Incorrect email or password.');
    }
    if (fbCode === 'USER_DISABLED') {
      throw new ApiError(403, 'ACCOUNT_DISABLED', 'This account has been disabled.');
    }
    if (fbCode === 'TOO_MANY_ATTEMPTS_TRY_LATER') {
      throw new ApiError(429, 'RATE_LIMITED', 'Too many sign-in attempts. Try again later.');
    }
    console.error(`[auth] sign-in failed: ${fbCode}`);
    throw new ApiError(502, 'IDENTITY_TOOLKIT_ERROR', 'Sign-in failed upstream. Try again shortly.');
  }
  return {
    uid: body.localId,
    email: body.email ?? email,
    idToken: body.idToken,
    expiresIn: body.expiresIn ?? '3600',
  };
}

/** Fetch an Auth user record; null when the account does not exist. */
export async function getAuthUserOrNull(uid: string): Promise<UserRecord | null> {
  try {
    return await fbAuth().getUser(uid);
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === 'auth/user-not-found') return null;
    throw err;
  }
}

/**
 * Admin-initiated "help me change my password" — generates a Firebase
 * password-reset link (the user sets their own new password through it).
 * The plaintext link is returned to the admin to forward; it is not stored.
 */
export async function generatePasswordResetLink(uid: string): Promise<{ email: string; link: string }> {
  const user = await fbAuth().getUser(uid);
  if (!user.email) {
    throw new ApiError(400, 'NO_EMAIL', 'This account has no email address; a reset link cannot be sent.');
  }
  const link = await fbAuth().generatePasswordResetLink(user.email);
  return { email: user.email, link };
}

/**
 * Alternative mode: set a NEW random one-time password directly via
 * `updateUser({ password })`. The password is generated here, returned once
 * in the response, and never written to disk or logs.
 */
export async function setTemporaryPassword(uid: string): Promise<{ email: string; tempPassword: string }> {
  const user = await fbAuth().getUser(uid);
  if (!user.email) {
    throw new ApiError(400, 'NO_EMAIL', 'This account has no email address.');
  }
  const tempPassword = generateStrongPassword();
  try {
    await fbAuth().updateUser(uid, { password: tempPassword });
  } catch (err) {
    // The transient password existed only in memory — nothing to clean up.
    throw err;
  }
  return { email: user.email, tempPassword };
}

/** 24-char random password: lower + upper + digit + symbol guaranteed. */
function generateStrongPassword(): string {
  const lowers = 'abcdefghijkmnopqrstuvwxyz';
  const uppers = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const symbols = '!@#$%^&*?-_=+';
  const all = lowers + uppers + digits + symbols;
  const bytes = randomBytes(48);
  const pick = (set: string, offset: number) => set[bytes[offset] % set.length];
  const chars: string[] = [
    pick(lowers, 0),
    pick(uppers, 1),
    pick(digits, 2),
    pick(symbols, 3),
  ];
  for (let i = 4; i < 24; i++) chars.push(pick(all, i));
  // Fisher-Yates shuffle with the same byte stream.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = bytes[i + 8] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

/**
 * Deletes the Firebase Auth account. Returns true when an account existed
 * and was deleted, false when it was already gone (idempotent — lets the
 * admin retry a partially-failed delete).
 */
export async function deleteAuthUser(uid: string): Promise<boolean> {
  try {
    await fbAuth().deleteUser(uid);
    return true;
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code === 'auth/user-not-found') return false;
    throw err;
  }
}
