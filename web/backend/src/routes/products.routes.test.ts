import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createProductsRouter } from './products.routes';
import { ApiError } from '../lib/errors';
import type { ProductsDeps } from '../services/products.service';
import type { AdminProductDetail, AdminProductRow } from '../types/models';

const allowAdmin: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'admin-1', email: null, name: null, adminClaim: true };
  next();
};

const allowUser: RequestHandler = (req, _res, next) => {
  req.user = { uid: 'seller-1', email: null, name: null, adminClaim: false };
  next();
};

const deny: RequestHandler = (_req, _res, next) =>
  next(new ApiError(401, 'UNAUTHENTICATED', 'Missing bearer token. Sign in first.'));

const productRow: AdminProductRow = {
  productId: 'sofa-1',
  name: 'Linen Sofa',
  category: 'Furniture',
  designStyle: 'Scandinavian',
  price: 899,
  originalPrice: 1099,
  stock: 12,
  isActive: true,
  isEcoFriendly: false,
  rating: 4.5,
  ratingCount: 20,
  supplierId: 'seller-1',
  supplierName: 'Nordic Home',
  image: 'https://cdn.example/sofa.jpg',
  createdAt: '2026-10-01T00:00:00.000Z',
};

const productDetail: AdminProductDetail = {
  ...productRow,
  description: 'Three-seater in oatmeal linen.',
  images: ['https://cdn.example/1.jpg'],
  shippingEnabled: true,
  shippingFee: 25,
  shippingLongDistanceNotice: false,
  ar3dStatus: 'ready',
  visionFlagged: false,
  supplierPhone: '012',
  supplierEmail: 'n@e',
  supplierVerificationStatus: 'verified',
};

async function withServer(
  deps: Partial<ProductsDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: ProductsDeps = {
    list: async () => ({ total: 1, limit: 50, offset: 0, items: [productRow] }),
    get: async () => productDetail,
    update: async (id, patch) => ({ ...productDetail, productId: id, ...('name' in patch ? { name: patch.name! } : {}) }),
    remove: async (id) => ({ productId: id, deleted: true, reviewsDeleted: 2 }),
    authorize: allowAdmin,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/products', createProductsRouter(fullDeps));
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

const AUTH = { Authorization: 'Bearer fake-token' };

async function get(base: string, query = '') {
  return fetch(`${base}/api/products${query}`, { headers: AUTH });
}

async function patch(base: string, id: string, body: unknown) {
  return fetch(`${base}/api/products/${id}`, {
    method: 'PATCH',
    headers: { ...AUTH, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function del(base: string, id: string) {
  return fetch(`${base}/api/products/${id}`, { method: 'DELETE', headers: AUTH });
}

test('products → 401 for an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    assert.equal((await get(base)).status, 401);
  });
});

test('products → 403 for a signed-in non-admin', async () => {
  await withServer({ authorize: allowUser }, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 403);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'NOT_ADMIN');
  });
});

test('products → GET forwards the query and returns {total, limit, offset, items}', async () => {
  let seen: unknown = null;
  await withServer(
    {
      list: async (q) => {
        seen = q;
        return { total: 1, limit: q.limit, offset: q.offset, items: [productRow] };
      },
    },
    async (base) => {
      const res = await get(base, '?q=sofa&category=Furniture&status=active&limit=25&offset=50');
      assert.equal(res.status, 200);
      const body = (await res.json()) as { total: number; items: AdminProductRow[] };
      assert.equal(body.total, 1);
      assert.equal(body.items[0].productId, 'sofa-1');
    }
  );
  assert.deepEqual(seen, {
    q: 'sofa',
    category: 'Furniture',
    status: 'active',
    limit: 25,
    offset: 50,
  });
});

test('products → GET defaults status=all limit=50 offset=0', async () => {
  let seen: unknown = null;
  await withServer(
    { list: async (q) => ((seen = q), { total: 0, limit: q.limit, offset: q.offset, items: [] }) },
    async (base) => {
      assert.equal((await get(base)).status, 200);
    }
  );
  assert.deepEqual(seen, { q: undefined, category: undefined, status: 'all', limit: 50, offset: 0 });
});

test('products → GET rejects a bad status value', async () => {
  await withServer({}, async (base) => {
    const res = await get(base, '?status=banana');
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('products → GET /:id returns {product}', async () => {
  await withServer({}, async (base) => {
    const res = await get(base, '/sofa-1');
    assert.equal(res.status, 200);
    const body = (await res.json()) as { product: AdminProductDetail };
    assert.equal(body.product.productId, 'sofa-1');
    assert.equal(body.product.ar3dStatus, 'ready');
  });
});

test('products → GET /:id maps the service 404', async () => {
  await withServer(
    {
      get: async () => {
        throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      },
    },
    async (base) => {
      const res = await get(base, '/gone-1');
      assert.equal(res.status, 404);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'PRODUCT_NOT_FOUND');
    }
  );
});

test('products → PATCH forwards the parsed patch', async () => {
  let seen: { id: string; patch: unknown } | null = null;
  await withServer(
    {
      update: async (id, patch) => {
        seen = { id, patch };
        return { ...productDetail, productId: id };
      },
    },
    async (base) => {
      const res = await patch(base, 'sofa-1', {
        name: 'Renamed Sofa',
        price: 799,
        originalPrice: null,
        isActive: false,
        shippingLongDistanceNotice: true,
      });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { product: AdminProductDetail };
      assert.equal(body.product.productId, 'sofa-1');
    }
  );
  assert.deepEqual(seen, {
    id: 'sofa-1',
    patch: {
      name: 'Renamed Sofa',
      price: 799,
      originalPrice: null,
      isActive: false,
      shippingLongDistanceNotice: true,
    },
  });
});

test('products → PATCH 400 on a negative price', async () => {
  await withServer({}, async (base) => {
    const res = await patch(base, 'sofa-1', { price: -1 });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('products → PATCH 400 on a negative shipping fee', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, 'sofa-1', { shippingFee: -5 })).status, 400);
  });
});

test('products → PATCH 400 on a non-boolean shippingLongDistanceNotice', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, 'sofa-1', { shippingLongDistanceNotice: 'true' })).status, 400);
  });
});

test('products → PATCH 400 on an unknown category', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, 'sofa-1', { category: 'Spaceships' })).status, 400);
  });
});

test('products → PATCH 400 on an empty body', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, 'sofa-1', {})).status, 400);
  });
});

test('products → PATCH 400 on a path-hostile id', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, '..%2Fsecrets', { price: 1 })).status, 400);
  });
});

test('products → DELETE forwards the id and returns the result', async () => {
  let seen: string | null = null;
  await withServer(
    {
      remove: async (id) => {
        seen = id;
        return { productId: id, deleted: true, reviewsDeleted: 3 };
      },
    },
    async (base) => {
      const res = await del(base, 'sofa-1');
      assert.equal(res.status, 200);
      const body = (await res.json()) as { productId: string; deleted: boolean; reviewsDeleted: number };
      assert.deepEqual(body, { productId: 'sofa-1', deleted: true, reviewsDeleted: 3 });
    }
  );
  assert.equal(seen, 'sofa-1');
});

test('products → DELETE maps the service 404', async () => {
  await withServer(
    {
      remove: async () => {
        throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
      },
    },
    async (base) => {
      assert.equal((await del(base, 'gone-1')).status, 404);
    }
  );
});
