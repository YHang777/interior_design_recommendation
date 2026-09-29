import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createTripoRouter } from './tripo.routes';
import { ApiError } from '../lib/errors';
import {
  TripoException,
  type TripoDeps,
  type TripoPassthrough,
} from '../services/tripo.service';

/** Lets the request through — tests exercise the route, not Firebase. */
const allow: RequestHandler = (_req, _res, next) => next();

/** Rejects the request the way the real authenticate middleware does. */
const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

const ok: TripoPassthrough = {
  statusCode: 200,
  body: JSON.stringify({ code: 0, data: { task_id: 'task_abc123' } }),
  contentType: 'application/json',
};

async function withServer(
  deps: Partial<TripoDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: TripoDeps = {
    isConfigured: () => true,
    submit: async () => ok,
    query: async () => ok,
    authorize: allow,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/tripo', createTripoRouter(fullDeps));
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
  return fetch(`${base}/api/tripo/generation/image-to-model`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

async function getTask(base: string, taskId = 'task_abc123', token = 'fake-token') {
  return fetch(`${base}/api/tripo/tasks/${taskId}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
}

const validBody = {
  input: 'https://res.cloudinary.com/demo/image/upload/sofa.jpg',
  texture: true,
  pbr: true,
  face_limit: 100000,
  auto_size: true,
};

test('tripo submit → 503 when TRIPO_API_KEY is not set', async () => {
  await withServer({ isConfigured: () => false }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 503);
    const body = (await res.json()) as { error: { code: string; message: string } };
    assert.equal(body.error.code, 'NOT_CONFIGURED');
    // The sentence the app surfaces — not a config diagnostic.
    assert.equal(
      body.error.message,
      '3D generation is not set up yet. Try again later.'
    );
  });
});

test('tripo query → 503 when TRIPO_API_KEY is not set', async () => {
  await withServer({ isConfigured: () => false }, async (base) => {
    const res = await getTask(base);
    assert.equal(res.status, 503);
  });
});

test('tripo submit → rejects an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 401);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'UNAUTHENTICATED');
  });
});

test('tripo query → rejects an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await getTask(base);
    assert.equal(res.status, 401);
  });
});

test('tripo submit → runs the auth step before calling Tripo', async () => {
  const order: string[] = [];
  await withServer(
    {
      authorize: (_req, _res, next) => {
        order.push('authorize');
        next();
      },
      submit: async () => {
        order.push('submit');
        return ok;
      },
    },
    async (base) => {
      await post(base, validBody);
    }
  );
  assert.deepEqual(order, ['authorize', 'submit']);
});

test('tripo submit → 400 when the image URL is missing or malformed', async () => {
  await withServer({}, async (base) => {
    for (const bad of [{}, { input: 'not-a-url' }, { input: '' }]) {
      const res = await post(base, bad);
      assert.equal(res.status, 400);
      const body = (await res.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'VALIDATION_ERROR');
    }
  });
});

test('tripo query → 400 when the task id is not URL-safe', async () => {
  await withServer({}, async (base) => {
    // A crafted id must never reach `encodeURIComponent`-less upstream path
    // building; the schema rejects it first.
    for (const bad of ['../../admin', 'task abc', 'task/xyz', 'a/b']) {
      const res = await getTask(base, encodeURIComponent(bad));
      assert.equal(res.status, 400, `expected 400 for task id ${JSON.stringify(bad)}`);
    }
  });
});

test('tripo submit → forwards the typed request upstream', async () => {
  let seen: unknown;
  await withServer(
    {
      submit: async (req) => {
        seen = req;
        return ok;
      },
    },
    async (base) => {
      await post(base, validBody);
    }
  );
  assert.deepEqual(seen, {
    input: validBody.input,
    texture: true,
    pbr: true,
    faceLimit: 100000,
    autoSize: true,
  });
});

test('tripo query → passes the task id through', async () => {
  let seen: string | undefined;
  await withServer(
    {
      query: async (taskId) => {
        seen = taskId;
        return ok;
      },
    },
    async (base) => {
      await getTask(base, 'task_deadbeef');
    }
  );
  assert.equal(seen, 'task_deadbeef');
});

test('tripo → a 200 upstream reply is passed through verbatim', async () => {
  const upstream: TripoPassthrough = {
    statusCode: 200,
    body: JSON.stringify({
      code: 0,
      data: {
        status: 'success',
        output: { model_url: 'https://cdn.tripo3d.ai/x.glb' },
        credits_consumed: 4,
      },
    }),
    contentType: 'application/json',
  };
  await withServer({ submit: async () => upstream }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 200);
    // Express appends `; charset=utf-8` to text-ish types; the media type is
    // what must survive the hop.
    assert.match(res.headers.get('content-type') ?? '', /^application\/json/);
    // Byte-for-byte: the client unwraps `{code, data}` itself and reads
    // `output.model_url` off it, so the proxy must not reshape anything.
    assert.equal(await res.text(), upstream.body);
  });
});

test('tripo → an upstream 4xx status and body are forwarded, not collapsed', async () => {
  // The client's retry policy keys off these: 402 = out of credits (terminal),
  // 429 = rate-limited (retryable). Mapping either to 500 would break it.
  const upstream: TripoPassthrough = {
    statusCode: 402,
    body: JSON.stringify({ code: 1200, message: 'insufficient credit' }),
    contentType: 'application/json',
  };
  await withServer({ submit: async () => upstream }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 402);
    assert.equal(await res.text(), upstream.body);
  });
});

test('tripo → upstream 429 is forwarded too', async () => {
  const upstream: TripoPassthrough = {
    statusCode: 429,
    body: JSON.stringify({ code: 429, message: 'too many requests' }),
    contentType: 'application/json',
  };
  await withServer({ query: async () => upstream }, async (base) => {
    const res = await getTask(base);
    assert.equal(res.status, 429);
    assert.equal(await res.text(), upstream.body);
  });
});

test('tripo → a network failure becomes 502 with a short sentence', async () => {
  await withServer(
    {
      submit: async () => {
        throw new TripoException('upstream', 'Tripo request failed: ECONNRESET 1.2.3.4');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 502);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'UPSTREAM_ERROR');
      assert.equal(
        body.error.message,
        '3D generation could not be reached. Try again.'
      );
      // The socket diagnostic must not reach the seller.
      assert.ok(!JSON.stringify(body).includes('ECONNRESET'));
    }
  );
});

test('tripo → upstream timeout becomes 504', async () => {
  await withServer(
    {
      query: async () => {
        throw new TripoException('timeout', 'Tripo request timed out.');
      },
    },
    async (base) => {
      const res = await getTask(base);
      assert.equal(res.status, 504);
      const body = (await res.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'UPSTREAM_TIMEOUT');
    }
  );
});

test('tripo → an unexpected throw still reaches the error handler', async () => {
  await withServer(
    {
      submit: async () => {
        throw new Error('boom');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 500);
    }
  );
});
