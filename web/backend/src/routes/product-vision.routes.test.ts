import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createProductVisionRouter } from './product-vision.routes';
import { ApiError } from '../lib/errors';
import type {
  AnalyzeProductResult,
  ProductVisionDeps,
} from '../services/product-vision.service';

/** Lets the request through with a fake identity — tests exercise the route, not Firebase. */
const allow: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'test-user', email: null, name: null, adminClaim: false };
  next();
};

/** Rejects the request the way the real authenticate middleware does. */
const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

const okResult: AnalyzeProductResult = {
  status: 'ok',
  vision: {
    status: 'ok',
    labels: ['wallpaper roll', 'floral print'],
    visualCategory: 'Wallpaper',
    visualStyle: 'Floral',
    summary: 'A roll of floral wallpaper.',
    mismatch: { flagged: false, reason: '' },
    analyzedAt: '2026-10-14T00:00:00.000Z',
    model: 'test-model',
  },
};

async function withServer(
  deps: Partial<ProductVisionDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: ProductVisionDeps = {
    isConfigured: () => true,
    analyze: async () => okResult,
    authorize: allow,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/ai', createProductVisionRouter(fullDeps));
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
  return fetch(`${base}/api/ai/analyze-product`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
}

const validBody = { productId: 'p123' };

test('analyze → 503 when the Gemini key is not set', async () => {
  await withServer({ isConfigured: () => false }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 503);
    const body = (await res.json()) as { error: { code: string; message: string } };
    assert.equal(body.error.code, 'NOT_CONFIGURED');
    // A config diagnostic never reaches the seller.
    assert.equal(body.error.message, 'Photo analysis is not configured yet.');
  });
});

test('analyze → rejects an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 401);
  });
});

test('analyze → 400 on an empty productId', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { productId: '' });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('analyze → 400 on a productId with path-hostile characters', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, { productId: '../secrets' });
    assert.equal(res.status, 400);
  });
});

test('analyze → 403 when the caller does not own the product', async () => {
  await withServer(
    {
      analyze: async () => {
        throw new ApiError(403, 'PRODUCT_NOT_OWNED', 'You can only check your own products.');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 403);
      const body = (await res.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'PRODUCT_NOT_OWNED');
    }
  );
});

test('analyze → 404 when the product does not exist', async () => {
  await withServer(
    {
      analyze: async () => {
        throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 404);
    }
  );
});

test('analyze → forwards the id, caller and admin flag to the service', async () => {
  let seen: { productId: string; uid: string; isAdmin: boolean } | null = null;
  await withServer(
    {
      analyze: async (productId, uid, isAdmin) => {
        seen = { productId, uid, isAdmin };
        return okResult;
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 200);
    }
  );
  assert.deepEqual(seen, { productId: 'p123', uid: 'test-user', isAdmin: false });
});

test('analyze → 200 returns the stored verdict verbatim', async () => {
  await withServer({}, async (base) => {
    const res = await post(base, validBody);
    assert.equal(res.status, 200);
    const body = (await res.json()) as AnalyzeProductResult;
    assert.equal(body.status, 'ok');
    assert.deepEqual(body, okResult);
  });
});

test('analyze → an analysis failure is still 200 (never blocks a save)', async () => {
  await withServer(
    {
      analyze: async () => ({
        status: 'failed',
        message: 'We could not read this photo. Your listing is saved as usual.',
        vision: okResult.vision,
      }),
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 200);
      const body = (await res.json()) as AnalyzeProductResult;
      assert.equal(body.status, 'failed');
      assert.ok(body.message);
    }
  );
});

test('analyze → an unexpected throw becomes 500 with a short sentence', async () => {
  await withServer(
    {
      analyze: async () => {
        throw new Error('firestore down: PROJECT=interior…');
      },
    },
    async (base) => {
      const res = await post(base, validBody);
      assert.equal(res.status, 500);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'ANALYSIS_FAILED');
      assert.equal(body.error.message, 'We could not check this photo right now.');
      assert.ok(!JSON.stringify(body).includes('firestore'));
    }
  );
});
