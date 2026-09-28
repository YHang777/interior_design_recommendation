import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createVerifyEmailRouter, type VerifyEmailDeps } from './verify-email.routes';
import { verifyVerificationToken } from '../lib/verification-token';

/** Boots the router on an ephemeral port with fully faked collaborators. */
async function withServer(
  deps: Partial<VerifyEmailDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: VerifyEmailDeps = {
    tokenSecret: 'test-secret',
    mailer: {
      isConfigured: true,
      sendVerificationEmail: async () => {},
    },
    isFirebaseConfigured: () => true,
    setEmailVerified: async () => {},
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/verify-email', createVerifyEmailRouter(fullDeps));
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('send → 503 when the flow is not configured', async () => {
  await withServer(
    { tokenSecret: '', mailer: { isConfigured: false, sendVerificationEmail: async () => {} } },
    async (base) => {
      const res = await fetch(`${base}/verify-email/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'a@b.co', uid: 'u1' }),
      });
      assert.equal(res.status, 503);
      const body = (await res.json()) as { error: string };
      assert.equal(body.error, 'Email verification is not configured.');
    }
  );
});

test('send → 400 when email/uid are missing', async () => {
  await withServer({}, async (base) => {
    const res = await fetch(`${base}/verify-email/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'a@b.co' }),
    });
    assert.equal(res.status, 400);
  });
});

test('send → mints a token that verifies and links back to this host', async () => {
  let mailed: { email: string; token: string; baseUrlOverride?: string } | null = null;
  await withServer(
    {
      mailer: {
        isConfigured: true,
        sendVerificationEmail: async (args) => {
          mailed = args as typeof mailed;
        },
      },
    },
    async (base) => {
      const res = await fetch(`${base}/verify-email/send`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-forwarded-proto': 'https',
        },
        body: JSON.stringify({ email: 'a@b.co', uid: 'u1' }),
      });
      assert.equal(res.status, 200);
      assert.deepEqual(await res.json(), { sent: true });

      assert.ok(mailed !== null);
      const payload = verifyVerificationToken(mailed.token, 'test-secret');
      assert.ok(payload !== null);
      assert.equal(payload.uid, 'u1');
      assert.equal(payload.email, 'a@b.co');
      // Link base is derived from the request host, scheme from X-Forwarded-Proto.
      assert.equal(mailed.baseUrlOverride, `https://${new URL(base).host}`);
    }
  );
});

test('send → 502 with a generic message when Brevo fails', async () => {
  const { VerificationEmailException } = await import('../lib/verification-mailer');
  await withServer(
    {
      mailer: {
        isConfigured: true,
        sendVerificationEmail: async () => {
          throw new VerificationEmailException('Brevo HTTP 401: nope');
        },
      },
    },
    async (base) => {
      const res = await fetch(`${base}/verify-email/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'a@b.co', uid: 'u1' }),
      });
      assert.equal(res.status, 502);
      const text = await res.text();
      assert.ok(text.includes('Could not send the verification email'));
      // Exception detail never leaks to the client.
      assert.ok(!text.includes('Brevo HTTP 401'));
    }
  );
});

test('confirm → failure page for a garbage token', async () => {
  await withServer({}, async (base) => {
    const res = await fetch(`${base}/verify-email/confirm?token=garbage`);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') ?? '', /html/);
    const text = await res.text();
    assert.ok(text.includes('Verification failed'));
    assert.ok(text.includes('invalid or has expired'));
  });
});

test('confirm → unavailable page when Firebase is not configured', async () => {
  await withServer({ isFirebaseConfigured: () => false }, async (base) => {
    const { createVerificationToken } = await import('../lib/verification-token');
    const token = createVerificationToken({
      uid: 'u1',
      email: 'a@b.co',
      secret: 'test-secret',
    });
    const res = await fetch(`${base}/verify-email/confirm?token=${encodeURIComponent(token)}`);
    const text = await res.text();
    assert.ok(text.includes('Verification unavailable'));
  });
});

test('confirm → success page and marks the user verified', async () => {
  const seen: string[] = [];
  await withServer(
    {
      setEmailVerified: async (uid) => {
        seen.push(uid);
      },
    },
    async (base) => {
      const { createVerificationToken } = await import('../lib/verification-token');
      const token = createVerificationToken({
        uid: 'u1',
        email: 'a@b.co',
        secret: 'test-secret',
      });
      const res = await fetch(`${base}/verify-email/confirm?token=${encodeURIComponent(token)}`);
      const text = await res.text();
      assert.deepEqual(seen, ['u1']);
      assert.ok(text.includes('Email Verified!'));
      assert.ok(text.includes('a@b.co is now verified.'));
    }
  );
});

test('confirm → unavailable page when Firebase write fails', async () => {
  await withServer(
    {
      setEmailVerified: async () => {
        throw new Error('uid not found');
      },
    },
    async (base) => {
      const { createVerificationToken } = await import('../lib/verification-token');
      const token = createVerificationToken({
        uid: 'u1',
        email: 'a@b.co',
        secret: 'test-secret',
      });
      const res = await fetch(`${base}/verify-email/confirm?token=${encodeURIComponent(token)}`);
      const text = await res.text();
      assert.ok(text.includes('Verification unavailable'));
      // Server exception text must not reach the page.
      assert.ok(!text.includes('uid not found'));
    }
  );
});
