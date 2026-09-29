import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createAiChatRouter } from './ai-chat.routes';
import { ApiError } from '../lib/errors';
import { AiChatException, type AiChatDeps } from '../services/ai-chat.service';

/** Lets the request through — tests exercise the route, not Firebase. */
const allow: RequestHandler = (_req, _res, next) => next();

/** Rejects the request the way the real authenticate middleware does. */
const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

async function withServer(
  deps: Partial<AiChatDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: AiChatDeps = {
    model: 'test-model',
    isConfigured: () => true,
    generate: async () => 'hello from the assistant',
    authorize: allow,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/ai', createAiChatRouter(fullDeps));
  // Mirrors the real errorHandler's JSON shape closely enough to read codes.
  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    const status = (err as { statusCode?: number }).statusCode ?? 500;
    const code = (err as { code?: string }).code ?? 'INTERNAL';
    res.status(status).json({ error: { code, message: (err as Error).message } });
  });

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

async function post(base: string, body: unknown, token = 'fake-token') {
  return fetch(`${base}/api/ai/chat`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

const validBody = {
  messages: [{ role: 'user', text: 'What goes with a grey sofa?' }],
};

test('chat → 503 when GEMINI_API_KEY is not set', async () => {
  await withServer({ isConfigured: () => false }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 503);
    const body = (await res.json()) as { error: { code: string; message: string } };
    assert.equal(body.error.code, 'NOT_CONFIGURED');
    // The sentence the app surfaces — not a config diagnostic.
    assert.equal(body.error.message, 'AI chat is not configured yet.');
  });
});

test('chat → rejects an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 401);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'UNAUTHENTICATED');
  });
});

test('chat → runs the auth step before generating a reply', async () => {
  const order: string[] = [];
  await withServer(
    {
      authorize: (_req, _res, next) => {
        order.push('authorize');
        next();
      },
      generate: async () => {
        order.push('generate');
        return 'ok';
      },
    },
    async (base) => {
      await post(base, validBody);
    }
  );
  assert.deepEqual(order, ['authorize', 'generate']);
});

test('chat → 400 when the message list is empty', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { messages: [] });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('chat → 400 when a message role is not user/model', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { messages: [{ role: 'system', text: 'hi' }] });
    assert.equal(res.status, 400);
  });
});

test('chat → 200 with the assistant reply', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 200);
    const body = (await res.json()) as { reply: string };
    assert.equal(body.reply, 'hello from the assistant');
  });
});

test('chat → forwards the transcript and context to the model', async () => {
  let seen: unknown;
  await withServer(
    {
      generate: async (req) => {
        seen = req;
        return 'ok';
      },
    },
    async (base) => {
      await post(base, {
        messages: [
          { role: 'user', text: 'hi' },
          { role: 'model', text: 'hello' },
          { role: 'user', text: 'ideas for my living room?' },
        ],
        style: 'Scandinavian',
        room: 'Living room',
        products: [{ name: 'Nordic Sofa', price: 1299, category: 'Sofa' }],
      });
    }
  );
  assert.deepEqual(seen, {
    messages: [
      { role: 'user', text: 'hi' },
      { role: 'model', text: 'hello' },
      { role: 'user', text: 'ideas for my living room?' },
    ],
    style: 'Scandinavian',
    room: 'Living room',
    products: [{ name: 'Nordic Sofa', price: 1299, category: 'Sofa' }],
  });
});

test('chat → upstream failure becomes 502 with a short sentence', async () => {
  await withServer(
    {
      generate: async () => {
        throw new AiChatException(
          'upstream',
          'Gemini rejected the request (HTTP 404): model not found'
        );
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 502);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'UPSTREAM_ERROR');
      assert.equal(body.error.message, 'The design assistant could not reply. Try again.');
      // The Google diagnostic must not reach the customer.
      assert.ok(!JSON.stringify(body).includes('HTTP 404'));
    }
  );
});

test('chat → upstream timeout becomes 504', async () => {
  await withServer(
    {
      generate: async () => {
        throw new AiChatException('timeout', 'Gemini request timed out.');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 504);
      const body = (await res.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'UPSTREAM_TIMEOUT');
    }
  );
});

test('chat → an unexpected throw still reaches the error handler', async () => {
  await withServer(
    {
      generate: async () => {
        throw new Error('boom');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 500);
    }
  );
});
