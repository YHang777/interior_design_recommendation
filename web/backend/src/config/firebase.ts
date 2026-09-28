import { existsSync } from 'node:fs';
import { initializeApp, cert, applicationDefault, type App } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';
import { getFirestore, type Firestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage, type Storage } from 'firebase-admin/storage';

/** The @google-cloud/storage bucket type, without adding a direct dependency. */
type Bucket = ReturnType<Storage['bucket']>;
import { ApiError } from '../lib/errors';
import { env } from './env';

/**
 * Lazy Firebase Admin initialization.
 *
 * Credentials (in order of preference — the env var WINS):
 *   1. FIREBASE_SERVICE_ACCOUNT_JSON → cert(JSON.parse(value))  (Render-friendly: no secrets folder)
 *   2. SERVICE_ACCOUNT_PATH          → cert(path)
 *   3. GOOGLE_APPLICATION_CREDENTIALS → applicationDefault()
 *   4. none                          → ApiError(503) naming the missing env var
 *
 * Lazy init means `/api/health` and the login route's validation still work
 * before credentials are configured, and the startup error names the exact
 * env var that is missing.
 */
let app: App | null = null;
let initError: ApiError | null = null;

function ensureApp(): App {
  if (app) return app;
  if (initError) throw initError;
  try {
    const inlineJson = env.serviceAccountJson.trim();
    const saPath = env.serviceAccountPath || process.env.GOOGLE_APPLICATION_CREDENTIALS || '';

    if (inlineJson) {
      // Tolerate the two shapes a host can hand us: the raw JSON object,
      // or that JSON wrapped in an extra pair of quotes as a string value.
      let parsed: unknown;
      try {
        parsed = JSON.parse(inlineJson);
        if (typeof parsed === 'string') parsed = JSON.parse(parsed);
      } catch {
        throw new ApiError(
          503,
          'FIREBASE_NOT_CONFIGURED',
          'FIREBASE_SERVICE_ACCOUNT_JSON is set but is not valid JSON. Paste the whole service-account key file as the value (single line, or a quoted multiline string).'
        );
      }
      app = initializeApp({ credential: cert(parsed as Parameters<typeof cert>[0]), projectId: env.projectId });
    } else if (env.serviceAccountPath && existsSync(env.serviceAccountPath)) {
      app = initializeApp({ credential: cert(env.serviceAccountPath), projectId: env.projectId });
    } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS && existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
      app = initializeApp({ credential: applicationDefault(), projectId: env.projectId });
    } else if (saPath) {
      // Path configured but file missing — fail with a precise message.
      throw new ApiError(
        503,
        'FIREBASE_NOT_CONFIGURED',
        `Service account file not found at "${saPath}". Set FIREBASE_SERVICE_ACCOUNT_JSON (inline JSON), SERVICE_ACCOUNT_PATH (path to the JSON), or GOOGLE_APPLICATION_CREDENTIALS to a valid service-account key.`
      );
    } else {
      throw new ApiError(
        503,
        'FIREBASE_NOT_CONFIGURED',
        'No Firebase credentials configured. Set FIREBASE_SERVICE_ACCOUNT_JSON (the whole service-account JSON as one env var — preferred on Render), SERVICE_ACCOUNT_PATH, or GOOGLE_APPLICATION_CREDENTIALS.'
      );
    }
    return app;
  } catch (err) {
    initError =
      err instanceof ApiError
        ? err
        : new ApiError(503, 'FIREBASE_NOT_CONFIGURED', `Firebase Admin failed to initialize: ${(err as Error).message}`);
    throw initError;
  }
}

export function fbAuth(): Auth {
  return getAuth(ensureApp());
}

export function fbDb(): Firestore {
  return getFirestore(ensureApp());
}

/**
 * Default Storage bucket — used ONLY to stream verification documents
 * (IC images) to authenticated admins. The Admin SDK bypasses Storage
 * security rules, which is why `storage.rules` denies ALL client reads of
 * `verification/**`: these bytes are PII and must never be public.
 */
export function fbStorage(): Bucket {
  return getStorage(ensureApp()).bucket();
}

/** Whether credentials are configured — surfaced by /api/health. */
export function firebaseConfigured(): boolean {
  try {
    ensureApp();
    return true;
  } catch {
    return false;
  }
}

export { FieldValue, Timestamp };
