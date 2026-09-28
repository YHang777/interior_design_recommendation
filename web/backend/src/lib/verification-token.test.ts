import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createVerificationToken,
  verifyVerificationToken,
} from './verification-token';

/**
 * Port of `server/test/verification_token_test.dart` — the same seven cases,
 * because this implementation must stay byte-compatible with the Dart server
 * (links minted there are still in users' inboxes).
 */
const secret = 'test-secret';

test('round-trips uid and email', () => {
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
  });
  const payload = verifyVerificationToken(token, secret);
  assert.ok(payload !== null);
  assert.equal(payload.uid, 'abc123');
  assert.equal(payload.email, 'user@example.com');
  assert.equal(typeof payload.exp, 'number');
  assert.ok(Number.isInteger(payload.exp));
});

test('rejects a tampered payload', () => {
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
  });
  const parts = token.split('.');
  // Flip the uid from abc123 to abc124 inside the payload.
  const forgedPayload =
    '{"uid":"abc124","email":"user@example.com","exp":9999999999}';
  const forgedB64 = Buffer.from(forgedPayload, 'utf8')
    .toString('base64url')
    .replace(/=/g, '');
  assert.equal(verifyVerificationToken(`${forgedB64}.${parts[1]}`, secret), null);
});

test('rejects a tampered signature', () => {
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
  });
  const parts = token.split('.');
  const sigBytes = Buffer.from(parts[1], 'base64url');
  sigBytes[0] ^= 0xff;
  const forgedSig = sigBytes.toString('base64url');
  assert.equal(verifyVerificationToken(`${parts[0]}.${forgedSig}`, secret), null);
});

test('rejects a token signed with a different secret', () => {
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
  });
  assert.equal(verifyVerificationToken(token, 'other-secret'), null);
});

test('rejects malformed tokens', () => {
  assert.equal(verifyVerificationToken('', secret), null);
  assert.equal(verifyVerificationToken('onlyone', secret), null);
  assert.equal(verifyVerificationToken('a.b.c', secret), null);
  assert.equal(verifyVerificationToken('!!!.###', secret), null);
});

test('rejects expired tokens', () => {
  const start = new Date(Date.UTC(2026, 0, 1, 12));
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
    clock: () => start,
  });
  // Verify with a clock 25 hours later (ttl is 24h).
  assert.equal(
    verifyVerificationToken(
      token,
      secret,
      () => new Date(start.getTime() + 25 * 3600 * 1000)
    ),
    null
  );
});

test('accepts tokens inside their ttl', () => {
  const start = new Date(Date.UTC(2026, 0, 1, 12));
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
    clock: () => start,
  });
  assert.notEqual(
    verifyVerificationToken(
      token,
      secret,
      () => new Date(start.getTime() + 23 * 3600 * 1000)
    ),
    null
  );
});

test('accepts padded signature variants (Dart base64Url tolerance)', () => {
  const token = createVerificationToken({
    uid: 'abc123',
    email: 'user@example.com',
    secret,
  });
  const [payloadB64, sigB64] = token.split('.');
  const rem = sigB64.length % 4;
  const paddedSig = rem === 0 ? sigB64 : sigB64 + '='.repeat(4 - rem);
  assert.notEqual(verifyVerificationToken(`${payloadB64}.${paddedSig}`, secret), null);
});
