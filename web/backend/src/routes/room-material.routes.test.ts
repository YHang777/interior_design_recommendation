import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createRoomMaterialRouter } from './room-material.routes';
import { ApiError } from '../lib/errors';
import type {
  AnalyzeRoomMaterialResult,
  RoomMaterialDeps,
} from '../services/room-material.service';

/** Lets the request through with a fake identity — tests exercise the route, not Firebase. */
const allow: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'test-user', email: null, name: null, adminClaim: false };
  next();
};

/** Rejects the request the way the real authenticate middleware does. */
const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

const okResult: AnalyzeRoomMaterialResult = {
  status: 'ok',
  floor: { material: 'woodPlanks', hex: '#B08D6B' },
  wall: { material: 'paint', hex: '#F5F3EE' },
};

async function withServer(
  deps: Partial<RoomMaterialDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: RoomMaterialDeps = {
    isConfigured: () => true,
    analyze: async () => okResult,
    authorize: allow,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '16mb' }));
  app.use('/api/ai', createRoomMaterialRouter(fullDeps));
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
  return fetch(`${base}/api/ai/analyze-room-material`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

const validBody = { imageBase64: 'YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo=' };

test('analyze → 503 when the Gemini key is not set', async () => {
  await withServer({ isConfigured: () => false }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 503);
    const body = (await res.json()) as { error: { code: string; message: string } };
    assert.equal(body.error.code, 'NOT_CONFIGURED');
    // A config diagnostic never reaches the caller.
    assert.equal(body.error.message, 'Room material scan is not configured yet.');
  });
});

test('analyze → rejects an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 401);
  });
});

test('analyze → 400 on an empty image', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { imageBase64: '' });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('analyze → 400 on a non-image mimeType', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { ...validBody, mimeType: 'text/html' });
    assert.equal(res.status, 400);
  });
});

test('analyze → forwards the frame and defaults the mimeType', async () => {
  let seen: { imageBase64: string; mimeType: string } | null = null;
  await withServer(
    {
      analyze: async (imageBase64, mimeType) => {
        seen = { imageBase64, mimeType };
        return okResult;
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 200);
    }
  );
  assert.deepEqual(seen, {
    imageBase64: validBody.imageBase64,
    mimeType: 'image/jpeg',
  });
});

test('analyze → 200 returns the verdict verbatim', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 200);
    const body = (await res.json()) as AnalyzeRoomMaterialResult;
    assert.deepEqual(body, okResult);
  });
});

test('analyze → an unreadable frame is still 200 (never blocks the scan)', async () => {
  await withServer(
    {
      analyze: async () => ({
        status: 'failed',
        message: 'We could not read the floor and wall in this frame.',
      }),
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 200);
      const body = (await res.json()) as AnalyzeRoomMaterialResult;
      assert.equal(body.status, 'failed');
      assert.ok(body.message);
      assert.equal(body.floor, undefined);
      assert.equal(body.wall, undefined);
    }
  );
});

test('analyze → an unexpected throw becomes 500 with a short sentence', async () => {
  await withServer(
    {
      analyze: async () => {
        throw new Error('gemini down: key=AIza…');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 500);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'ANALYSIS_FAILED');
      assert.equal(body.error.message, 'We could not read the room materials right now.');
      assert.ok(!JSON.stringify(body).includes('AIza'));
    }
  );
});
