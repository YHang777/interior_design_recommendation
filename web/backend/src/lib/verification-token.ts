import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Stateless HMAC-SHA256 verification token — faithful port of
 * `server/lib/verification_token.dart` (the Dart server that previously
 * hosted this flow).
 *
 * Format: `base64url(payloadJson) + '.' + base64url(hmacSha256(secret, payloadB64))`
 * where payloadJson is `{"uid": ..., "email": ..., "exp": <epochSeconds>}`.
 *
 * Byte-compatibility matters: links already sitting in users' inboxes were
 * minted by the Dart server. `base64url` here is UNPADDED (same as the Dart
 * `_b64url` helper that strips `=`), signatures are over the padded-or-not
 * payload string exactly as received, and `exp` is epoch seconds. A token
 * minted by either implementation must verify on the other.
 *
 * No server-side storage is involved — the token is unforgeable without
 * `secret` and self-expiring via `exp`, so a still-valid link can always be
 * retried (idempotent) and an old one can never be replayed past its TTL.
 */
export const DEFAULT_TOKEN_TTL_SECONDS = 24 * 60 * 60;

export interface VerificationTokenPayload {
  uid: string;
  email: string;
  exp: number;
}

/** Injectable clock (tests); defaults to `new Date()`. */
export type Clock = () => Date;

export function createVerificationToken({
  uid,
  email,
  secret,
  clock,
  ttlSeconds = DEFAULT_TOKEN_TTL_SECONDS,
}: {
  uid: string;
  email: string;
  secret: string;
  clock?: Clock;
  ttlSeconds?: number;
}): string {
  const now = clock ? clock() : new Date();
  const payload = JSON.stringify({
    uid,
    email,
    exp: Math.floor(now.getTime() / 1000) + ttlSeconds,
  });
  const payloadB64 = b64url(Buffer.from(payload, 'utf8'));
  const sigB64 = b64url(sign(payloadB64, secret));
  return `${payloadB64}.${sigB64}`;
}

/**
 * Decodes and validates `token`. Returns `{uid, email, exp}` or null when
 * the token is malformed, tampered with, or expired.
 */
export function verifyVerificationToken(
  token: string,
  secret: string,
  clock?: Clock
): VerificationTokenPayload | null {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payloadB64, sigB64] = parts;
  if (!payloadB64 || !sigB64) return null;

  // Recompute-and-compare (constant-time once lengths match).
  const expected = sign(payloadB64, secret);
  const actual = decodeB64url(sigB64);
  if (actual === null) return null;
  if (actual.length !== expected.length) return null;
  if (!timingSafeEqual(actual, expected)) return null;

  let payload: unknown;
  try {
    const raw = decodeB64url(payloadB64);
    if (raw === null) return null;
    payload = JSON.parse(raw.toString('utf8'));
  } catch {
    return null;
  }
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    return null;
  }
  const { uid, email, exp } = payload as Record<string, unknown>;
  if (typeof uid !== 'string' || uid.length === 0) return null;
  if (typeof email !== 'string' || email.length === 0) return null;
  if (typeof exp !== 'number' || !Number.isInteger(exp)) return null;
  const now = clock ? clock() : new Date();
  if (exp <= Math.floor(now.getTime() / 1000)) return null;
  return { uid, email, exp };
}

function sign(payloadB64: string, secret: string): Buffer {
  return createHmac('sha256', secret).update(payloadB64, 'utf8').digest();
}

/** base64url WITHOUT padding (matches the Dart `_b64url` helper). */
function b64url(bytes: Buffer): string {
  return bytes.toString('base64url');
}

/**
 * Lenient base64url decode (re-pads first, like the Dart `_padB64` helper).
 * Returns null for garbage instead of throwing.
 */
function decodeB64url(s: string): Buffer | null {
  try {
    const rem = s.length % 4;
    const padded = rem === 0 ? s : s + '='.repeat(4 - rem);
    return Buffer.from(padded, 'base64url');
  } catch {
    return null;
  }
}
