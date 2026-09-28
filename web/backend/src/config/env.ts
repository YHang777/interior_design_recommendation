import 'dotenv/config';

/**
 * All configuration is env-driven. Nothing secret lives in code — see
 * `.env.example` for the full list and `web/README.md` for setup.
 */
function parseAdminUids(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export const env = {
  /** API port (default 4000). */
  port: Number(process.env.PORT ?? 4000),
  /** The ONLY origin allowed by CORS — the Vite dev server / deployed frontend. */
  frontendOrigin: process.env.FRONTEND_ORIGIN ?? 'http://localhost:5173',
  /**
   * Admin allowlist: comma-separated Firebase Auth UIDs. An account is an
   * admin if its UID is listed here OR it carries the custom claim
   * `{ admin: true }` (see `npm run claim-admin -- <uid>`).
   */
  adminUids: parseAdminUids(process.env.ADMIN_UIDS),
  /** Firebase project (matches lib/firebase_options.dart / firebase.json). */
  projectId: process.env.FIREBASE_PROJECT_ID ?? 'interior-design-256c5',
  /**
   * Service-account JSON inlined as an env var (the whole key file as the
   * value). Preferred on hosts with no secrets folder (e.g. Render): paste
   * the JSON as FIREBASE_SERVICE_ACCOUNT_JSON. NEVER commit it.
   * When set, this WINS over SERVICE_ACCOUNT_PATH / GOOGLE_APPLICATION_CREDENTIALS.
   */
  serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON ?? '',
  /**
   * Path to the service-account JSON (local development). NEVER committed —
   * gitignored via `web/.gitignore`. Falls back to GOOGLE_APPLICATION_CREDENTIALS
   * when neither this nor the JSON env var is set.
   */
  serviceAccountPath: process.env.SERVICE_ACCOUNT_PATH ?? '',
  /**
   * Firebase Web API key — used ONLY by the backend's login proxy
   * (Identity Toolkit accounts:signInWithPassword). It is a public-facing
   * key (also present in lib/firebase_options.dart), kept in env for
   * consistency.
   */
  webApiKey: process.env.FIREBASE_WEB_API_KEY ?? '',
};
