# Intellar web host (`web/frontend` + `web/backend`)

The admin console **and** the mobile app's email-verification service, served
from ONE Render URL:

| Path | What |
|---|---|
| `/admin` | Admin console SPA (React + Vite + TypeScript) |
| `/admin/api/*` (alias `/api/*`) | Admin API — monitor customers/suppliers, approve/reject suppliers, review IC applications, password help, safe account deletion |
| `/verify-email/send` · `/verify-email/confirm` | Registration email verification (Brevo link → confirm page marks Firebase `emailVerified`) — port of the old Dart `server/` routes, same paths and byte-compatible tokens |
| `/api/ai/chat` | Design assistant for the Flutter app (short product/room chat) — signed-in, proxied to Gemini. **The key stays here.** |
| `/api/tripo/generation/image-to-model` · `/api/tripo/tasks/:taskId` | 3D model generation for sellers — signed-in, proxied to Tripo (status + body forwarded verbatim). **The key stays here.** |

**Architecture rule: the frontend never talks to Firebase or Supabase.** It
talks only to the admin API, which is the sole component that mutates Firebase
Auth and Firestore. (The pre-existing Flutter web shell files in this folder —
`index.html`, `manifest.json`, `favicon.png`, `icons/` — belong to the Flutter
app and are untouched.)

```
web/
  frontend/    React + Vite + TypeScript admin UI  (dev port 5173, base /admin/)
  backend/     Node + Express + firebase-admin + email verification (port 4000)
  Dockerfile   unified image — the ONE Render service (see §3)
  README.md    this file
  .env.example both halves' env vars, in one place
  .gitignore   node_modules, dist, .env, service-account keys
```

The Dart package in `server/` is kept for local dev and as the reference for
the token format; production email verification runs on this Node port
(`web/backend/src/lib/verification-token.ts` is byte-compatible with
`server/lib/verification_token.dart`, so links already in inboxes stay valid).

Deploying? Jump straight to **[§3 Deploy on Render](#3-deploy-on-render)**.

---

## 1. Run it

### Prerequisites
- Node.js 20+ (tested on Node 24)
- A Firebase **service-account JSON** for project `interior-design-256c5`
  (the same key the Dart server uses at `server/secrets/service-account.json`
  works — do not copy it anywhere that is committed)

### Backend

```bash
cd web/backend
cp .env.example .env          # then edit — see §2
npm install
npm run dev                   # http://localhost:4000
```

Other scripts: `npm run build` (tsc → `dist/`), `npm start` (run compiled),
`npm run typecheck` (`tsc --noEmit`), `npm run claim-admin -- <uid>`
(grant the admin custom claim).

### Frontend

```bash
cd web/frontend
npm install
npm run dev                   # http://localhost:5173/admin/
```

Other scripts: `npm run build` (typecheck + production bundle in `dist/`),
`npm run typecheck`.

The frontend reads `VITE_API_BASE_URL` (default `http://localhost:4000/api`);
override in `frontend/.env.local` if the API runs elsewhere.

---

## 2. Configuration (secrets)

| Variable | Half | Purpose |
|---|---|---|
| `PORT` | backend | API port (default `4000`). Read from `process.env.PORT` — Render injects it automatically; never hardcode a port. |
| `FRONTEND_ORIGIN` | backend | The **only** origin allowed by CORS (default `http://localhost:5173`) |
| `FIREBASE_PROJECT_ID` | backend | Defaults to `interior-design-256c5` |
| `FIREBASE_WEB_API_KEY` | backend | Firebase **Web API key** (Firebase console → Project settings → General). Used only by the login proxy. It is a public-facing key — the same value ships in `lib/firebase_options.dart`. Missing it → login returns `503 LOGIN_NOT_CONFIGURED`. |
| `ADMIN_UIDS` | backend | Comma-separated Firebase Auth UIDs allowed to use the API |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | backend | **The whole service-account JSON as one env var** — preferred on Render (no secrets folder). When set it **wins** over the two below. |
| `SERVICE_ACCOUNT_PATH` | backend | Path to the service-account JSON (local dev); falls back to `GOOGLE_APPLICATION_CREDENTIALS` |
| `VERIFY_TOKEN_SECRET` | backend | HMAC secret for stateless `/verify-email` tokens (same name the Dart server used). Missing → send returns 503 |
| `BREVO_API_KEY` | backend | Brevo v3 API key (transactional send). Missing → send returns 503 |
| `BREVO_SENDER_EMAIL` / `BREVO_SENDER_NAME` | backend | Verified Brevo sender (default name `Intellar`) |
| `PUBLIC_BASE_URL` | backend | Fallback email-link origin (e.g. `https://interior-design-recommendation.onrender.com`). Normally overridden per-request from `Host` + `X-Forwarded-Proto` |
| `GEMINI_API_KEY` | backend | Google AI Studio key for `/api/ai/chat` (the design assistant). **Server-side only** — never put it in the Flutter app or a `--dart-define`; APK contents are extractable. Missing → chat returns `503 NOT_CONFIGURED`. |
| `GEMINI_MODEL` | backend | Model id for the assistant (default `gemini-2.5-flash-lite`, the cheapest tier). If a new key cannot reach the 2.5 family, set `gemini-3.1-flash-lite`. |
| `TRIPO_API_KEY` | backend | Tripo AI key for `/api/tripo/*` (seller 3D generation). **Server-side only** — same rule as the Gemini key: it used to live in `lib/config/local_config.dart` and shipped inside every APK. Missing → both routes return `503 NOT_CONFIGURED`. |
| `TRIPO_MODEL_VERSION` | backend | Tripo model billed for image-to-model (default `v3.1-20260211`). Server-owned so a version bump is an env change, not an app release. |
| `TRIPO_BASE_URL` | backend | Tripo OpenAPI origin (default `https://openapi.tripo3d.ai/v3`) — override only for a Tripo proxy/mirror. |
| `ADMIN_STATIC_DIR` | backend | Where the built SPA lives. Default: `web/frontend/dist`; the unified Docker image sets it to `/app/frontend-dist` |
| `VITE_API_BASE_URL` | frontend | Backend base URL (default `http://localhost:4000/api`; the unified image bakes `/admin/api`) — **build-time** (`VITE_` vars are inlined by Vite at `npm run build`) |

**Service account — never commit it.** `web/.gitignore` ignores `secrets/`,
`service-account*.json` and `.env` (the repo-root `.gitignore` also ignores
`.env` and `server/secrets/`). Keep the key at e.g.
`web/backend/secrets/service-account.json` and point `SERVICE_ACCOUNT_PATH`
at it, export `GOOGLE_APPLICATION_CREDENTIALS`, or paste it into
`FIREBASE_SERVICE_ACCOUNT_JSON` (see §3 — Render).

---

## 3. Deploy on Render

Everything lives on the **existing** `interior-design-recommendation` web
service (the one that used to run the Dart `server/` image) at
`https://interior-design-recommendation.onrender.com`. One service, one URL —
Render's `*.onrender.com` hostname belongs to a single service, so unifying
paths under it means the service itself serves them all (that's what
`web/Dockerfile` + `web/backend/src/app.ts` do).

There is deliberately **no blueprint**: the old `web/render.yaml` (two
services) was removed — running it would create duplicate half-configured
services next to the real host.

### One-time switch on the existing service

1. **Push** this repo to GitHub (Render deploys from GitHub, not your disk).
2. Render dashboard → the `interior-design-recommendation` service →
   **Settings**:
   - **Dockerfile Path** → `web/Dockerfile` (build context stays the repo
     root — the image copies from `web/frontend` + `web/backend`; the old
     `server/Dockerfile` is no longer used in production).
   - **Health Check Path** (optional but recommended) → `/api/health`.
3. **Environment** tab — keep every var the Dart server used and add the
   admin ones (full table below). Save triggers a redeploy.
4. **Manual Deploy → Deploy latest commit** (first time after the path
   change; use **Clear build cache & deploy** if anything looks stale).
5. Verify (see checklist below).

### Environment variables (one service, one list)

| Variable | Value | Notes |
|---|---|---|
| `PORT` | **Injected by Render — do not set it.** | Hardcoding a port is the #1 Render failure; the server reads `process.env.PORT` and binds `0.0.0.0`. |
| `NODE_ENV` | `production` | |
| `ADMIN_UIDS` | Comma-separated Firebase Auth UIDs allowed to use the admin API | **New** |
| `FIREBASE_WEB_API_KEY` | Firebase Web API key (same value as `lib/firebase_options.dart`) | **New** — powers the admin login proxy; missing → `503 LOGIN_NOT_CONFIGURED` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | The **entire** service-account JSON as a single-line value (`jq -c . service-account.json`) | **Or** reuse the existing secret-file mount instead — see next row. This var **wins** if both are set. |
| `SERVICE_ACCOUNT_PATH` | e.g. `/etc/secrets/service-account.json` | Already on this service (the Dart server used it). Keep the secret file and this path — the backend reads it too. |
| `FIREBASE_PROJECT_ID` | `interior-design-256c5` | Already set |
| `VERIFY_TOKEN_SECRET` | unchanged | Email tokens (HMAC) |
| `BREVO_API_KEY` · `BREVO_SENDER_EMAIL` · `BREVO_SENDER_NAME` | unchanged | Brevo send |
| `GEMINI_API_KEY` | Google AI Studio key | **New** — design assistant (`/api/ai/chat`). Server-side only. |
| `GEMINI_MODEL` | optional, default `gemini-2.5-flash-lite` | **New** — set `gemini-3.1-flash-lite` if the key cannot reach the 2.5 family |
| `TRIPO_API_KEY` | Tripo AI key (`tsk_…`) | **New** — seller 3D generation (`/api/tripo/*`). Server-side only. |
| `TRIPO_MODEL_VERSION` | optional, default `v3.1-20260211` | **New** — the Tripo model billed for image-to-model |
| `PUBLIC_BASE_URL` | `https://interior-design-recommendation.onrender.com` | Fallback email-link base (normally derived from the request Host) |
| `FRONTEND_ORIGIN` | optional on the unified host | Only matters for split-origin local dev (`http://localhost:5173`). Same-origin `/admin` → `/admin/api` calls need no CORS at all. |

**Never commit the service-account key.** `web/.gitignore` covers
`service-account*.json`, `secrets/` and `.env`. It lives in Render's secret
files / Environment tab only.

`VITE_API_BASE_URL` is baked at image build to the same-origin path
`/admin/api` (`web/Dockerfile` ARG) — no dashboard var needed.

### Post-deploy checklist

| Check | Expect |
|---|---|
| `GET https://interior-design-recommendation.onrender.com/api/health` | `{"status":"ok",…,"firebaseConfigured":true,"verificationEmailConfigured":true}` |
| `GET …/admin` | the admin login page (Intellar Admin) |
| `GET …/verify-email/confirm?token=garbage` | styled "Verification failed" page |
| Admin login with an allowlisted account | console loads; Overview KPIs appear |
| One real registration email | link lands on `…/verify-email/confirm?token=…` → "Email Verified!" → `I've Verified` in the app works |

Failure decoder:

| Symptom | Cause | Fix |
|---|---|---|
| `/admin` shows 503 "assets are not built" | image built without the frontend stage | Dockerfile Path must be `web/Dockerfile`, not `server/Dockerfile` |
| health `firebaseConfigured:false` | no service account | secret-file mount + `SERVICE_ACCOUNT_PATH`, or `FIREBASE_SERVICE_ACCOUNT_JSON` |
| health `verificationEmailConfigured:false` | `VERIFY_TOKEN_SECRET` / `BREVO_API_KEY` missing | fill both |
| `503 LOGIN_NOT_CONFIGURED` | `FIREBASE_WEB_API_KEY` missing | set it |
| seller's "Generate 3D" returns "3D generation is not set up yet" | `TRIPO_API_KEY` missing on the server | set it in Render → Environment (the app cannot see it — by design) |
| `403 NOT_ADMIN` | UID not allowlisted, no claim | add to `ADMIN_UIDS` (save restarts) |
| first load slow (30–60 s) | free-tier cold start | expected; same as before |

### Promoting someone to admin

An account can use the API only if **either** its UID is in `ADMIN_UIDS`
**or** it carries the Firebase custom claim `{admin: true}`:

```bash
# Option 1 — custom claim (local, needs the service account):
cd web/backend
npm run claim-admin -- <firebase-uid>   # the user must sign out/in afterwards

# Option 2 — allowlist (works from Render's dashboard, no local setup):
#   Service → Environment → ADMIN_UIDS → "uid1,uid2" → Save (API restarts)
```

This console is deliberately **not self-serve** — the login page tells
non-admin accounts to ask an existing admin instead.

---

## 4. How admin authentication works

1. The admin signs in on the frontend → `POST /api/auth/login`
   `{ email, password }`.
2. The **backend** proxies the credentials to Identity Toolkit
   (`accounts:signInWithPassword`) and gets a Firebase ID token.
3. The backend verifies that token and checks the account is an admin —
   the token is returned to the frontend **only for admins**.
4. The frontend stores the ID token (localStorage) and sends
   `Authorization: Bearer <id-token>` on **every** request.
5. On every authenticated route the middleware chain runs:
   `authenticate` (verify ID token via Admin SDK) → `requireAdmin`
   (custom claim `{ admin: true }` **or** UID in `ADMIN_UIDS`) →
   `validate` (zod) → handler → service persistence.

An account is an admin if **either**:
- its UID is listed in `ADMIN_UIDS`, or
- it carries the custom claim `{ admin: true }` —
  grant with `npm run claim-admin -- <uid>` (the account must sign
  out/in afterwards).

There is deliberately **no `admin` role field in Firestore**: the Flutter app
parses `users/{uid}.role` as only `homeowner`/`supplier`
(`lib/features/auth/data/models/app_user.dart`), so admin identity lives in
env/claims where the mobile app never reads it.

Security properties:
- No unauthenticated writes: every mutating route passes `authenticate` + `requireAdmin`.
- Passwords are never stored or logged. "Password help" either **generates a
  Firebase reset link** (`generatePasswordResetLink`) or sets a **random
  one-time password** via Admin `updateUser({ password })`, returned exactly
  once in the response. Request bodies are never logged.
- CORS is locked to `FRONTEND_ORIGIN`.
- Every body/query/path is zod-validated; errors return
  `{ error: { code, message, details } }` without stack traces.

---

## 5. API surface

Base URL: `http://localhost:4000/api`. All responses JSON.
Auth = `Authorization: Bearer <id-token>` (Firebase ID token).

| Method | Path | Auth | Body / query | Success response |
|---|---|---|---|---|
| GET | `/health` | public | — | `{ status, service, firebaseConfigured }` |
| POST | `/ai/chat` | **signed-in** | `{ messages: [{role:'user'\|'model', text}], style?, room?, products?: [{name, price?, category?}] }` (≤20 products) | `{ reply }` — the design assistant. Proxied to Gemini; the API key never leaves the server. |
| POST | `/tripo/generation/image-to-model` | **signed-in** | `{ input: <image URL>, texture?, pbr?, auto_size?, face_limit? }` (≤500000) | Tripo's own `{code, data}` body, **status and Content-Type forwarded verbatim** — the app's transient/terminal retry policy keys off them. The server injects `model` and the `Authorization: Bearer <TRIPO_API_KEY>` header; the key never leaves the server. |
| GET | `/tripo/tasks/:taskId` | **signed-in** | `:taskId` must be `[A-Za-z0-9_-]{1,128}` (path-traversal guarded) | Tripo's task status body, forwarded verbatim (same pass-through rule). Re-polling is free; re-submitting is billed — the app keeps `ar3d.taskId` across failures so a paid task is never lost. |
| POST | `/auth/login` | public | `{ email, password }` | `{ uid, email, idToken, expiresIn, isAdmin, profile }` |
| GET | `/auth/me` | admin | — | `{ uid, email, name, isAdmin, adminViaClaim, profile }` |
| GET | `/stats` | admin | — | `{ customers, suppliers, authOnlyAccounts, products, orders, pendingSuppliers, rejectedSuppliers, unverifiedSuppliers, pendingVerifications, recentUsers[≤5] }` |
| GET | `/users` | admin | `role=homeowner\|supplier\|all`, `status=verified\|pending\|rejected`, `q`, `limit≤200`, `offset` | `{ total, limit, offset, items: AdminUserRow[] }` |
| GET | `/users/:uid` | admin | — | `{ user: AdminUserDetail }` |
| PATCH | `/users/:uid/verification` | admin | `{ status: 'verified'\|'pending'\|'rejected' }` | `{ uid, verificationStatus, productsSynced }` |
| POST | `/users/:uid/password-reset` | admin | `{ mode?: 'reset_link'\|'temp_password' }` | `{ mode, email, link }` or `{ mode, email, tempPassword }` |
| DELETE | `/users/:uid` | admin | `{ confirmEmail }` (must equal the target's email, case-insensitive) | `{ uid, email, authDeleted, profileDeleted, cartItemsDeleted, wishlistItemsDeleted, productsDeactivated }` |
| GET | `/verification/applications` | admin | `status=pending\|approved\|rejected\|all` (default `pending`), `limit≤200` (default 100), `offset` | `{ total, limit, offset, items: [{ uid, email, businessName, status, submittedAt, documentCount }] }` — **metadata only, never file bytes** |
| GET | `/verification/applications/:uid` | admin | — | `{ application: VerificationApplication }` — includes the `documents[]` metadata array (id, kind, fileName, contentType, sizeBytes, storagePath, uploadedAt) |
| GET | `/verification/applications/:uid/documents/:docId` | admin | — | Raw bytes of **one declared document** (streamed). `Content-Type` re-validated against an image/PDF allowlist, `Content-Disposition: inline; filename="…"`, `Cache-Control: private, no-store`. `:docId` is matched against the application's own `documents[]` first, so no arbitrary Storage path can be probed |
| PATCH | `/verification/applications/:uid` | admin | `{ status: 'approved'\|'rejected', reviewNote?: string (≤2000) }` | `{ application, verificationStatus: 'verified'\|'rejected', productsSynced }` |

Error shape (any failure): `{ error: { code, message, details? } }` with codes
`UNAUTHENTICATED` (401), `NOT_ADMIN` (403), `VALIDATION_ERROR` (400),
`CONFIRM_MISMATCH` (400), `SELF_DELETE` (400), `NOT_SUPPLIER` (400),
`USER_NOT_FOUND` (404), `APPLICATION_NOT_FOUND` (404),
`DOCUMENT_NOT_FOUND` (404), `STORAGE_OBJECT_MISSING` (404),
`NOT_CONFIGURED` (503, AI chat + 3D generation), `UPSTREAM_ERROR` (502,
AI chat + 3D generation), `UPSTREAM_TIMEOUT` (504, AI chat + 3D generation),
`INVALID_DOCUMENT_PATH` (400), `STORAGE_READ_ERROR` (500),
`PARTIAL_DELETE` (500), `FIREBASE_NOT_CONFIGURED` (503),
`INTERNAL_ERROR` (500), …

**`/api/tripo/*` is the exception that proves the shape.** Success and
*upstream* failures are forwarded with Tripo's status and `{code, data}` body
untouched, because the app's retry policy (transient → keep `ar3d.taskId` and
retry; terminal → stop) reads those directly. Only *proxy-level* failures are
shaped as the `{error:{code,message}}` envelope above — `NOT_CONFIGURED`
(503, no key), `UNAUTHENTICATED` (401), `VALIDATION_ERROR` (400),
`UPSTREAM_TIMEOUT` (504), `UPSTREAM_ERROR` (502). The app recognises the
envelope and shows its short sentence instead of guessing from a status code.

`AdminUserRow` fields (from `/users`): `uid, email, name, role,
verificationStatus, phone, businessName, businessPhone, createdAt,
authCreatedAt, lastSignInAt, emailVerified, disabled, profileExists,
productCount, orderCount`.

---

## 6. Verification review workflow (IC uploads)

Suppliers earn the **Verified** badge by applying: **IC (identity card)
front + back (required)** plus **0–5 supporting documents**.

**Data layout**

| Where | What |
|---|---|
| Firestore `verification_applications/{uid}` (doc id = supplier uid) | `uid, email, businessName, status ('pending'\|'approved'\|'rejected'), submittedAt, reviewedAt?, reviewedBy?, reviewNote?, documents[]` (each: `id, kind ('ic_front'\|'ic_back'\|'supporting'), fileName, contentType, sizeBytes, storagePath, uploadedAt`) |
| Firebase Storage `verification/{uid}/{documentId}.{ext}` | the raw file bytes |
| Firestore `users/{uid}` | `verificationStatus ('none'\|'pending'\|'verified'\|'rejected'), verificationSubmittedAt?, verificationReviewNote?` |

**Security rules (IC images are admin-only)**

- `storage.rules` — new rule for `match /verification/{uid}/{file}`:
  `allow read: if false;` (nobody reads these through the Storage SDK, and
  **no public download URL exists** — the bytes only leave the server through
  the admin-only `GET …/documents/:docId` stream) and
  `allow write: if request.auth != null && request.auth.uid == uid;`
  (a supplier may write only into their own folder). The pre-existing
  `images/` public-read rule is untouched.
- `firestore.rules` — `match /verification_applications/{uid}`: the supplier
  may **create and read only their own** application (`request.auth.uid == uid`);
  **no client may update or delete it** (`allow update, delete: if false`) —
  the admin backend writes the review outcome with the Admin SDK, which bypasses
  rules; there is **no public read**.
- `firestore.rules` — `match /users/{uid}` tightened: the owner still reads/
  writes only their own profile, but **cannot write `verificationStatus: 'verified'`**
  (checked on both create and update via the `diff().affectedKeys()`), so a
  supplier can never self-approve. ⚠️ The Flutter registration flow must
  therefore **not** write `'verified'` at signup — start suppliers at
  `'none'`/`'pending'`; a create attempt with `'verified'` is now denied.

**The review loop**

1. The supplier uploads their IC + documents from the mobile app → the app
   creates `verification_applications/{uid}` with `status: 'pending'` and marks
   the user pending.
2. The admin opens **Directory → Verification** — the sidebar item carries a
   live pending-count badge, and Overview shows an **IC applications** KPI
   (`GET /stats` → `pendingVerifications`).
3. Filter chips (Pending / Approved / Rejected / All) drive the queue table;
   **Review** opens the detail drawer: applicant identity, submitted/reviewed
   dates, and every document as a thumbnail (IC front/back first, accent-
   highlighted and clearly labelled). Clicking one opens the full-size
   `Modal` viewer. Every byte is fetched with `Authorization: Bearer <id-token>`
   through the API — never from a public URL.
4. **Approve** applies immediately; **Reject** requires a review note and asks
   for confirmation first. Both toast the result (including how many listings
   were re-synced).
5. `PATCH /verification/applications/:uid` updates the application
   (`status`, `reviewedAt`, `reviewedBy`, `reviewNote`), sets
   `users/{uid}.verificationStatus` to `verified`/`rejected` (mirroring the note
   to `verificationReviewNote`), and batch-updates `products/{id}.supplier.verificationStatus`
   for every listing the supplier owns — so the buyer app's badge and the
   "Verified sellers only" filter stay in sync.

Document bytes are **never** returned in list/detail JSON, never logged, and
the stream route re-validates `Content-Type` against an image/PDF allowlist
(the `documents[]` array is supplier-authored, so a crafted `text/html` type
would otherwise be an XSS risk on the admin origin).

**Deploying the rules:** push both changed files — `firebase deploy --only
firestore:rules` picks up `firestore.rules`; for Storage, either add a
`"storage": { "rules": "storage.rules" }` section to `firebase.json` and
include `storage:rules`, or paste the `storage.rules` content into the
Firebase console (Storage → Rules). Until the Storage rule lands, the old
public-read behaviour still applies only to `images/` — `verification/**`
has no matching rule yet, so uploads/reads of it are **denied** by default
until the new rule is deployed (deploy it together with the mobile upload
flow).

---

## 7. Firestore/Auth fields the admin mutates

The schema matches the Flutter app exactly — **no new fields were invented**:

| Action | Firebase Auth | Firestore |
|---|---|---|
| Verify / reject supplier | — | `users/{uid}.verificationStatus` → `verified` \| `pending` \| `rejected`; `users/{uid}.updatedAt` → server time. **Plus** `products/{id}.supplier.verificationStatus` for every listing the supplier owns (matched by `supplierId` and legacy `supplier.id`). |
| Review an IC application (`PATCH /verification/applications/:uid`) | — | `verification_applications/{uid}`: `status` → `approved`\|`rejected`, `reviewedAt` (ISO-8601 UTC), `reviewedBy` (admin uid), `reviewNote`; plus **everything the row above writes** (`users/{uid}.verificationStatus`, `users/{uid}.verificationReviewNote`, product supplier snapshots) — all in one call. |
| Password help (reset link) | `generatePasswordResetLink(email)` — link returned once | — |
| Password help (temp password) | `updateUser(uid, { password })` — random, returned once | — |
| Delete account | `deleteUser(uid)` (retry-safe if already gone) | delete `users/{uid}`, `users/{uid}/cart/*`, `users/{uid}/wishlist/*`; if supplier: `products/{id}.isActive = false`. `orders/*` are **never** deleted. |

### Why products are synced too (migration note)

The buyer marketplace's **"Verified sellers only"** filter (default ON) reads
the *embedded* snapshot `p.supplier.verificationStatus`
(`lib/features/customer/marketplace/presentation/providers/marketplace_providers.dart`
→ `p.supplier.isVerified`), not the user document. So an approval that only
touched `users/{uid}` would be invisible in the app. The verification service
therefore updates **both** copies — same field name the app already uses
(`'verified' | 'pending' | 'rejected'`, per `lib/models/product.dart` and
`app_user.dart`).

**No schema migration is required to run this admin site.** Two notes for the
future:

1. The Flutter register flow currently writes
   `verificationStatus: 'verified'` immediately
   (`auth_repository_impl.dart`, with a `TODO(future)` for admin approval).
   This admin can flip any supplier to `'pending'` / `'rejected'` and back.
   If you later change registration to start suppliers as `'pending'`, no
   admin-side change is needed — the field and value set already match.
2. Products created before `supplierId` existed carry only `supplier.id`;
   all admin queries match both (same fallback as `Product.resolvedSupplierId`
   and `migrateLegacyProducts()`).

Admin identity is **not** stored in Firestore (see §3), so nothing in the
app's `users` collection had to change for it.

---

## 8. Backend structure (the middleware chain)

```
backend/src/
  index.ts              entry — starts Express (the unified web host)
  app.ts                CORS → JSON parsing → /verify-email + /api/ai +
                        /api/tripo + /api + /admin (SPA static/fallback)
                        → 404 → error handler
  config/env.ts         env parsing (dotenv)
  config/firebase.ts    lazy firebase-admin init (service account / ADC)
  middleware/
    authenticate.ts     step 1: verify the Firebase ID token        → req.user
    requireAdmin.ts     step 2: admin claim / ADMIN_UIDS allowlist
    validate.ts         step 3: zod body/query/param validation
    errorHandler.ts     step 5: central JSON error rendering
    types.ts            req.user typing
  lib/
    verification-token.ts   HMAC token — byte-compatible port of
                        server/lib/verification_token.dart
    verification-mailer.ts  Brevo send + email HTML (port of the Dart mailer)
  routes/
    verify-email.routes.ts  /verify-email/send + /confirm (app signup flow;
                        deps-injected so tests can fake mailer/Firebase)
    ai-chat.routes.ts   /api/ai/chat — the design assistant proxy
                        (authenticate → validate → Gemini)
    tripo.routes.ts     /api/tripo/generation/image-to-model +
                        /api/tripo/tasks/:taskId — 3D generation proxy
                        (authenticate → validate → Tripo, pass-through)
    auth.routes.ts      /auth/login (public proxy), /auth/me
    users.routes.ts     list/detail/verification/password-reset/delete
    stats.routes.ts     /stats
    verification.routes.ts  /verification/applications… (IC review queue;
                        authenticate + requireAdmin on every route)
  services/             step 4: handlers delegate here → persistence
    verification-email.service.ts  env + firebase wiring for /verify-email
    ai-chat.service.ts  Gemini call for the design assistant
    tripo.service.ts    Tripo call for 3D generation — the ONLY place
                        TRIPO_API_KEY is read, and it is never returned
    identity.service.ts sign-in proxy, reset link, temp password, auth delete
    users.service.ts    user list/detail/stats with product & order counts
    verification.service.ts  supplier approval + product snapshot sync
    applications.service.ts  application queue + IC document streaming
                        (path allowlisting) + approve/reject decisions
    deletion.service.ts      delete orchestration + PARTIAL_DELETE recovery
  scripts/set-admin-claim.ts  npm run claim-admin -- <uid>
```

Route wiring makes the chain explicit, e.g.:

```ts
usersRouter.patch('/:uid/verification',
  authenticate,          // auth check
  requireAdmin,          // role check
  validateParams(uidParam),
  validateBody(verificationBody),   // validation
  handler → setSupplierVerification) // handler → persistence
```

The Dart server in `server/` used to host email verification (and a legacy
JSON-file marketplace API) on Render. This backend now **is** that host: its
`/verify-email` routes are the port, run from the same unified service as the
admin console. The Dart package remains in the repo for local dev and as the
token-format reference; its JSON marketplace endpoints were dropped outright —
the marketplace is Firestore (`lib/services/marketplace_repository.dart`) and
nothing in the app called them.

---

## 9. What was verified / what wasn't

- ✅ `web/backend`: `npm run build` (`tsc` → `dist/`) clean; `npm start` runs
  the compiled output and binds `process.env.PORT` on `0.0.0.0` (Render-safe).
- ✅ `web/frontend`: `npm run build` (`tsc && vite build`) clean.
- ✅ Verification console (IC review): the four `/verification/applications…`
  routes build clean behind `authenticate` + `requireAdmin`; the review page
  compiles into the bundle. ⚠️ Not exercised against live Firebase: reviewing
  needs a real service-account key plus an actual application document in
  `verification_applications/` and files under `verification/{uid}/` —
  configure `web/backend/.env` (§2) and deploy the updated `storage.rules`
  and `firestore.rules` first.
- ✅ Email-verification port (replaces the Dart `server/` in production):
  `npm test` runs 16 tests — the 7 token cases ported from
  `server/test/verification_token_test.dart` plus route-level pins (503 when
  unconfigured, 400 missing fields, token minting with Host-derived link
  base, 502 on Brevo failure without leaking details, invalid/expired confirm
  page, unavailable page without Firebase, success page calling
  `setEmailVerified`, unavailable page when Firebase write fails). Tokens are
  byte-compatible with the Dart format (unpadded base64url, HMAC over the
  payload string as received, `exp` in epoch seconds) — links already in
  inboxes keep working.
- ✅ Unified host routing, smoke-tested locally: `GET /` → redirect `/admin`;
  `/admin` serves the SPA (assets under `/admin/assets/…`); deep `/admin/…`
  paths fall back to the shell; `/admin/api/nope` returns the JSON 404 (not
  the SPA); `/api/health` and `/admin/api/health` both answer; confirm page
  renders for garbage tokens.
- ✅ Render readiness: `web/Dockerfile` builds SPA + API into one image
  (repo-root build context, `ADMIN_STATIC_DIR` set for the runtime);
  `FIREBASE_SERVICE_ACCOUNT_JSON` (inline JSON, env var wins) is supported
  alongside `SERVICE_ACCOUNT_PATH` / `GOOGLE_APPLICATION_CREDENTIALS` — the
  existing service's secret-file mount keeps working.
- ⚠️ Not exercised against live credentials: sign-in, user listing and all
  mutations need a real service-account key + an admin Firebase account —
  including the Render deploy end-to-end (login proxy, real Brevo send →
  confirm → `emailVerified`). Configure `web/backend/.env` (§2) or the Render
  env vars (§3) and run the §3 checklist.
