import test from 'node:test';
import assert from 'node:assert/strict';
import express, { type RequestHandler } from 'express';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createSettingsRouter } from './settings.routes';
import { ApiError } from '../lib/errors';
import type { SettingsDeps } from '../services/settings.service';
import type { AppSettings } from '../types/models';

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

const SETTINGS: AppSettings = {
  taxRate: 0.06,
  updatedAt: '2026-10-19T00:00:00.000Z',
  updatedBy: 'admin-1',
};

async function withServer(
  deps: Partial<SettingsDeps>,
  fn: (base: string) => Promise<void>
): Promise<void> {
  const fullDeps: SettingsDeps = {
    get: async () => SETTINGS,
    update: async (taxRate, adminUid) => ({ taxRate, updatedAt: '2026-10-19T01:00:00.000Z', updatedBy: adminUid }),
    authorize: allowAdmin,
    log: () => {},
    ...deps,
  };
  const app = express();
  app.use(express.json({ limit: '128kb' }));
  app.use('/api/settings', createSettingsRouter(fullDeps));
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

async function get(base: string) {
  return fetch(`${base}/api/settings`, { headers: AUTH });
}

async function patch(base: string, body: unknown) {
  return fetch(`${base}/api/settings`, {
    method: 'PATCH',
    headers: { ...AUTH, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test('settings → 401 for an unauthenticated caller', async () => {
  await withServer({ authorize: deny }, async (base) => {
    assert.equal((await get(base)).status, 401);
  });
});

test('settings → 403 for a signed-in non-admin', async () => {
  await withServer({ authorize: allowUser }, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 403);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, 'NOT_ADMIN');
  });
});

test('settings GET → 200 returns the settings envelope', async () => {
  await withServer({}, async (base) => {
    const res = await get(base);
    assert.equal(res.status, 200);
    const body = (await res.json()) as { settings: AppSettings };
    assert.deepEqual(body.settings, SETTINGS);
  });
});

test('settings PATCH → 400 for out-of-range or non-numeric taxRate', async () => {
  for (const body of [{ taxRate: 1.5 }, { taxRate: -0.1 }, { taxRate: '0.06' }, {}]) {
    await withServer({}, async (base) => {
      const res = await patch(base, body);
      assert.equal(res.status, 400);
      const parsed = (await res.json()) as { error: { code: string } };
      assert.equal(parsed.error.code, 'VALIDATION_ERROR');
    });
  }
});

test('settings PATCH → 200 forwards the fraction and the admin uid', async () => {
  const calls: [number, string][] = [];
  await withServer(
    {
      update: async (taxRate, adminUid) => {
        calls.push([taxRate, adminUid]);
        return { taxRate, updatedAt: '2026-10-19T02:00:00.000Z', updatedBy: adminUid };
      },
    },
    async (base) => {
      const res = await patch(base, { taxRate: 0.08 });
      assert.equal(res.status, 200);
      const body = (await res.json()) as { settings: AppSettings };
      assert.equal(body.settings.taxRate, 0.08);
      assert.equal(body.settings.updatedBy, 'admin-1');
      assert.deepEqual(calls, [[0.08, 'admin-1']]);
    }
  );
});
