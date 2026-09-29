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

  // ── Email verification (`/verify-email/*`) ──────────────────────────────
  // Same env names the Dart server used, so the Render service keeps working
  // with the secrets it already has.

  /** HMAC secret for stateless verification tokens. */
  verifyTokenSecret: process.env.VERIFY_TOKEN_SECRET ?? '',
  /** Brevo v3 API key (https://app.brevo.com → SMTP & API → API keys). */
  brevoApiKey: process.env.BREVO_API_KEY ?? '',
  /** Verified sender address in the Brevo console. */
  brevoSenderEmail: process.env.BREVO_SENDER_EMAIL ?? 'noreply@interior-design.app',
  brevoSenderName: process.env.BREVO_SENDER_NAME ?? 'Intellar',
  /**
   * Public origin of THIS service (e.g. https://interior-design-recommendation.onrender.com)
   * — used as the email link base when the request Host header is missing.
   * Normally overridden per-request from Host / X-Forwarded-Proto.
   */
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? '',

  /**
   * Directory holding the built admin SPA (Vite `dist/`). Defaults to
   * `web/frontend/dist` next to the backend package (local dev); the unified
   * Docker image (web/Dockerfile) sets ADMIN_STATIC_DIR explicitly.
   */
  adminStaticDir: process.env.ADMIN_STATIC_DIR ?? '',

  // ── AI design assistant (`/api/ai/chat`) ────────────────────────────────
  //
  // The Gemini key is SERVER-SIDE ONLY. It must never reach the Flutter app:
  // anything compiled into a mobile binary can be extracted from the APK, so
  // a key shipped in the client is not a secret, it is a leaked secret.

  /** Google AI Studio key (https://aistudio.google.com → API keys). */
  geminiApiKey: process.env.GEMINI_API_KEY ?? '',
  /**
   * Model id. Defaults to the cheapest tier — the assistant is short
   * product/design chat, not reasoning work. Overridable without a redeploy
   * when Google restricts a model to older keys.
   */
  geminiModel: process.env.GEMINI_MODEL ?? 'gemini-2.5-flash-lite',

  // ── 3D generation (`/api/tripo/*`) ──────────────────────────────────────
  //
  // Same rule as the Gemini key: SERVER-SIDE ONLY. The Tripo key used to live
  // in `lib/config/local_config.dart`, which meant every APK shipped a copy of
  // it. It now lives here and the app talks to this proxy instead.

  /** Tripo API key (https://platform.tripo3d.ai → API keys). */
  tripoApiKey: process.env.TRIPO_API_KEY ?? '',
  /**
   * Tripo OpenAPI base. Overridable so a version bump or a mock can be tried
   * without a code change.
   */
  tripoBaseUrl: process.env.TRIPO_BASE_URL ?? 'https://openapi.tripo3d.ai/v3',
  /**
   * Tripo model version sent as the image-to-model `model` field. Owned by the
   * server so a version bump is one env var, not an app release.
   */
  tripoModelVersion: process.env.TRIPO_MODEL_VERSION ?? 'v3.1-20260211',
};
