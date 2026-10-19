import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createProductFlagsRouter } from './product-flags.routes';
import { ApiError } from '../lib/errors';
import type { ProductFlagsDeps } from '../services/product-flags.service';
import type { ProductFlagListResult, ProductFlagRow } from '../types/models';

/** Admin identity — the queue is authenticate + requireAdmin only. */
const allowAdmin: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'admin-1', email: null, name: null, adminClaim: true };
  next();
};

/** Signed in, but without the admin claim (and not on the UID allowlist). */
const allowUser: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'seller-1', email: null, name: null, adminClaim: false };
  next();
};

/** Rejects the request the way the real authenticate middleware does. */
const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

const flagRow: ProductFlagRow = {
  productId: 'wall-1',
  name: 'Floral Wallpaper',
  category: 'Wallpaper',
  price: 30,
  supplierId: 'seller-1',
  supplierName: 'Wallpaper Co',
  supplierEmail: 'sales@wallpaper.co',
  image: 'https://cdn.example/wall.jpg',
  description: 'Premium vinyl, waterproof.',
  vision: {
    status: 'ok',
    labels: ['living room', 'sofa'],
    visualCategory: 'Living room',
    summary: 'A living room with a grey sofa.',
    mismatch: { flagged: true, reason: 'Photo shows a room, not wallpaper.' },
    analyzedAt: '2026-10-14T00:00:00.000Z',
    model: 'test-model',
  },
  review: null,
};

async function withServer(
  deps: Partial<ProductFlagsDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: ProductFlagsDeps = {
    list: async () => ({ items: [flagRow], total: 1 }),
    setReview: async (productId, status) => ({
      ...flagRow,
      productId,
      review: {
        status,
        reviewedAt: '2026-10-15T00:00:00.000Z',
        reviewedBy: 'admin-1',
      },
    }),
    authorize: allowAdmin,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/products', createProductFlagsRouter(fullDeps));
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

async function get(base: string, query = '') {
  return fetch(`${base}/api/products/flags${query}`, {
    headers: { Authorization: 'Bearer fake-token' },
  });
}

async function patch(base: string, productId: string, body: unknown) {
  return fetch(`${base}/api/products/flags/${productId}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer fake-token',
    },
    body: JSON.stringify(body),
  });
}

test('flags → 401 for an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 401);
  });
});

test('flags → 403 for a signed-in non-admin', async () => {
  await withServer({ authorize: allowUser }, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 403);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'NOT_ADMIN');
  });
});

test('flags → GET defaults to the open queue', async () => {
  let seen: string | null = null;
  await withServer(
    { list: async (status) => ((seen = status), { items: [], total: 0 }) },
    async (base) => {
      const res = await get(base);
      assert.equal(res.status, 200);
    }
  );
  assert.equal(seen, 'open');
});

test('flags → GET forwards an explicit status and returns {items, total}', async () => {
  let seen: string | null = null;
  await withServer(
    {
      list: async (status) => {
        seen = status;
        return { items: [flagRow], total: 1 };
      },
    },
    async (base) => {
      const res = await get(base, '?status=all');
      assert.equal(res.status, 200);
      const body = (await res.json()) as ProductFlagListResult;
      assert.equal(body.total, 1);
      assert.equal(body.items[0].productId, 'wall-1');
      assert.equal(body.items[0].vision.mismatch.flagged, true);
      assert.equal(body.items[0].review, null); // absent review ⇒ open
    }
  );
  assert.equal(seen, 'all');
});

test('flags → GET rejects an unknown status', async () => {
  await withServer({}, async (base) => {
    const res = await get(base, '?status=banana');
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('flags → PATCH forwards id, status, note and the admin uid', async () => {
  let seen: { productId: string; status: string; note?: string; uid: string } | null = null;
  await withServer(
    {
      setReview: async (productId, status, note, adminUid) => {
        seen = { productId, status, note, uid: adminUid };
        return {
          ...flagRow,
          productId,
          review: {
            status,
            ...(note ? { note } : {}),
            reviewedAt: '2026-10-15T00:00:00.000Z',
            reviewedBy: adminUid,
          },
        };
      },
    },
    async (base) => {
      const res = await patch(base, 'wall-1', {
        status: 'resolved',
        note: 'Confirmed fake — delisted later.',
      });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { item: ProductFlagRow };
      assert.equal(body.item.productId, 'wall-1');
      assert.equal(body.item.review?.status, 'resolved');
      assert.equal(body.item.review?.reviewedBy, 'admin-1');
    }
  );
  assert.deepEqual(seen, {
    productId: 'wall-1',
    status: 'resolved',
    note: 'Confirmed fake — delisted later.',
    uid: 'admin-1',
  });
});

test('flags → PATCH can reopen a resolved flag (no note)', async () => {
  let seenNote: string | undefined = 'unset';
  await withServer(
    {
      setReview: async (productId, _status, note) => {
        seenNote = note;
        return { ...flagRow, productId, review: null };
      },
    },
    async (base) => {
      const res = await patch(base, 'wall-1', { status: 'open' });
      assert.equal(res.status, 200);
    }
  );
  assert.equal(seenNote, undefined);
});

test('flags → PATCH 400 on a bad status value', async () => {
  await withServer({}, async (base) => {
    const res = await patch(base, 'wall-1', { status: 'ignored' });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('flags → PATCH 400 on a path-hostile productId', async () => {
  await withServer({}, async (base) => {
    const res = await patch(base, '..%2Fsecrets', { status: 'resolved' });
    assert.equal(res.status, 400);
  });
});

test('flags → PATCH surfaces the service 404 with its plain sentence', async () => {
  await withServer(
    {
      setReview: async () => {
        throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      },
    },
    async (base) => {
      const res = await patch(base, 'gone-1', { status: 'resolved' });
      assert.equal(res.status, 404);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'PRODUCT_NOT_FOUND');
      assert.equal(body.error.message, 'That product could not be found.');
    }
  );
});

test('flags → PATCH wraps an unexpected failure in a short sentence', async () => {
  await withServer(
    {
      setReview: async () => {
        throw new Error('firestore write denied: PROJECT=interior…');
      },
    },
    async (base) => {
      const res = await patch(base, 'wall-1', { status: 'resolved' });
      assert.equal(res.status, 500);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'REVIEW_WRITE_FAILED');
      assert.equal(body.error.message, 'We could not save that review. Try again.');
      // The diagnostic stays in the log.
      assert.ok(!JSON.stringify(body).includes('firestore'));
    }
  );
});
