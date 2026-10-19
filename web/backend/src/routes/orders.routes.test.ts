import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createOrdersRouter } from './orders.routes';
import { ApiError } from '../lib/errors';
import type { OrdersDeps } from '../services/orders.service';
import type { AdminOrderDetail, AdminOrderRow } from '../types/models';

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

const orderRow: AdminOrderRow = {
  orderId: 'ord-1',
  orderNumber: 'ORD-20261015-1234',
  customerId: 'user-1',
  customerName: 'Aina',
  status: 'pending',
  itemCount: 2,
  total: 1025,
  paymentMethod: 'fpx',
  createdAt: '2026-10-15T00:00:00.000Z',
  nextStatuses: ['confirmed', 'shipped', 'delivered'],
};

const orderDetail: AdminOrderDetail = {
  ...orderRow,
  customerEmail: 'aina@example.com',
  customerPhone: '0123456789',
  shippingAddress: '1 Jalan Test, KL',
  items: [
    { productId: 'p-1', name: 'Sofa', image: '', unitPrice: 500, quantity: 2, supplierId: 'seller-1' },
  ],
  subtotal: 1000,
  shippingFee: 25,
  discount: 0,
  tax: 0,
  supplierIds: ['seller-1'],
  statusHistory: { pending: '2026-10-15T00:00:00.000Z' },
  invoiceSupplierIds: [],
};

async function withServer(
  deps: Partial<OrdersDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: OrdersDeps = {
    list: async () => ({ total: 1, limit: 50, offset: 0, items: [orderRow] }),
    get: async () => orderDetail,
    setStatus: async (id, status) => ({
      ...orderDetail,
      orderId: id,
      status,
      nextStatuses: status === 'delivered' || status === 'cancelled' ? [] : ['delivered'],
    }),
    authorize: allowAdmin,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/orders', createOrdersRouter(fullDeps));
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

async function get(base: string, path = '') {
  return fetch(`${base}/api/orders${path}`, { headers: AUTH });
}

async function patch(base: string, id: string, body: unknown) {
  return fetch(`${base}/api/orders/${id}`, {
    method: 'PATCH',
    headers: { ...AUTH, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test('orders → 401 for an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    assert.equal((await get(base)).status, 401);
  });
});

test('orders → 403 for a signed-in non-admin', async () => {
  await withServer({ authorize: allowUser }, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 403);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'NOT_ADMIN');
  });
});

test('orders → GET forwards the query', async () => {
  let seen: unknown = null;
  await withServer(
    {
      list: async (q) => {
        seen = q;
        return { total: 0, limit: q.limit, offset: q.offset, items: [] };
      },
    },
    async (base) => {
      const res = await get(base, '?status=shipped&q=ORD-1&limit=10&offset=20');
      assert.equal(res.status, 200);
    }
  );
  assert.deepEqual(seen, { status: 'shipped', q: 'ORD-1', limit: 10, offset: 20 });
});

test('orders → GET defaults limit=50 offset=0, no status/q', async () => {
  let seen: unknown = null;
  await withServer(
    { list: async (q) => ((seen = q), { total: 0, limit: q.limit, offset: q.offset, items: [] }) },
    async (base) => {
      assert.equal((await get(base)).status, 200);
    }
  );
  assert.deepEqual(seen, { status: undefined, q: undefined, limit: 50, offset: 0 });
});

test('orders → GET rejects a bad status', async () => {
  await withServer({}, async (base) => {
    const res = await get(base, '?status=banana');
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('orders → GET /:id returns {order}', async () => {
  await withServer({}, async (base) => {
    const res = await get(base, '/ord-1');
    assert.equal(res.status, 200);
    const body = (await res.json()) as { order: AdminOrderDetail };
    assert.equal(body.order.orderId, 'ord-1');
    assert.equal(body.order.items.length, 1);
  });
});

test('orders → GET /:id maps the service 404', async () => {
  await withServer(
    {
      get: async () => {
        throw new ApiError(404, 'ORDER_NOT_FOUND', 'That order could not be found.');
      },
    },
    async (base) => {
      const res = await get(base, '/gone-1');
      assert.equal(res.status, 404);
      const body = (await res.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'ORDER_NOT_FOUND');
    }
  );
});

test('orders → PATCH forwards id and status', async () => {
  let seen: { id: string; status: string } | null = null;
  await withServer(
    {
      setStatus: async (id, status) => {
        seen = { id, status };
        return { ...orderDetail, orderId: id, status };
      },
    },
    async (base) => {
      const res = await patch(base, 'ord-1', { status: 'shipped' });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { order: AdminOrderDetail };
      assert.equal(body.order.status, 'shipped');
    }
  );
  assert.deepEqual(seen, { id: 'ord-1', status: 'shipped' });
});

test('orders → PATCH 400 on an unknown status', async () => {
  await withServer({}, async (base) => {
    const res = await patch(base, 'ord-1', { status: 'banana' });
    assert.equal(res.status, 400);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'VALIDATION_ERROR');
  });
});

test('orders → PATCH 400 on a missing status', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, 'ord-1', {})).status, 400);
  });
});

test('orders → PATCH 400 on a path-hostile id', async () => {
  await withServer({}, async (base) => {
    assert.equal((await patch(base, '..%2Fsecrets', { status: 'shipped' })).status, 400);
  });
});

test('orders → PATCH surfaces the service 400 transition error', async () => {
  await withServer(
    {
      setStatus: async () => {
        throw new ApiError(
          400,
          'ORDER_INVALID_TRANSITION',
          'An order that is delivered cannot become cancelled.'
        );
      },
    },
    async (base) => {
      const res = await patch(base, 'ord-1', { status: 'cancelled' });
      assert.equal(res.status, 400);
      const body = (await res.json()) as { error: { code: string; message: string } };
      assert.equal(body.error.code, 'ORDER_INVALID_TRANSITION');
      assert.equal(body.error.message, 'An order that is delivered cannot become cancelled.');
    }
  );
});
