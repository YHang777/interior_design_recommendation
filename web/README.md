# Admin monitoring site (`web/frontend` + `web/backend`)

An admin console for the interior-design marketplace: monitor customers and
suppliers, approve/reject suppliers, help users change passwords, and delete
accounts — safely.

**Architecture rule: the frontend never talks to Firebase or Supabase.** It
talks only to the backend API (`web/backend`), which is the sole component
that mutates Firebase Auth and Firestore. (The pre-existing Flutter web shell
files in this folder — `index.html`, `manifest.json`, `favicon.png`, `icons/`
— belong to the Flutter app and are untouched.)

```
web/
  frontend/    React + Vite + TypeScript admin UI  (port 5173)
  backend/     Node + Express + firebase-admin API (port 4000)
  render.yaml  Render Blueprint — deploys BOTH halves (see §3)
  README.md    this file
  .env.example both halves' env vars, in one place
  .gitignore   node_modules, dist, .env, service-account keys
```

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
npm run dev                   # http://localhost:5173
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
| `VITE_API_BASE_URL` | frontend | Backend base URL (default `http://localhost:4000/api`) — **build-time** (`VITE_` vars are inlined by Vite at `npm run build`) |

**Service account — never commit it.** `web/.gitignore` ignores `secrets/`,
`service-account*.json` and `.env` (the repo-root `.gitignore` also ignores
`.env` and `server/secrets/`). Keep the key at e.g.
`web/backend/secrets/service-account.json` and point `SERVICE_ACCOUNT_PATH`
at it, export `GOOGLE_APPLICATION_CREDENTIALS`, or paste it into
`FIREBASE_SERVICE_ACCOUNT_JSON` (see §3 — Render).

---

## 3. Deploy on Render

Both halves deploy to Render — the API as a **Web Service** (Node) and the
frontend as a **Static Site**. A Blueprint declaring both lives at
[`render.yaml`](render.yaml) (paths are repo-root-relative, so it works from
inside `web/`; if your Render flow only auto-detects `render.yaml` at the
repository root, copy this file there or create the services by hand with
Option B — the settings are identical).

### Option A — Render Blueprint

1. Push this repo to GitHub.
2. Render dashboard → **New + → Blueprint** → connect the repo. Point it at
   `web/render.yaml` if asked for a YAML path (or copy that file to the repo
   root).
3. Render creates two services — `intellar-admin-api` (web service) and
   `intellar-admin-frontend` (static site). For each env var marked
   `sync: false`, open the service → **Environment** and fill in the value
   from the tables below.
4. Deploy. Health check: `GET https://<api-name>.onrender.com/api/health`
   → `{ "status": "ok", … }`.

### Option B — create the two services by hand

**API — Dashboard → New → Web Service**

| Setting | Value |
|---|---|
| Runtime | Node |
| Root Directory | `web/backend` |
| Build Command | `npm ci && npm run build` (compiles TypeScript → `dist/`) |
| Start Command | `npm start` (runs `node dist/index.js`) |
| Health Check Path | `/api/health` |

**Frontend — Dashboard → New → Static Site**

| Setting | Value |
|---|---|
| Root Directory | `web/frontend` |
| Build Command | `npm ci && npm run build` (typecheck + Vite production bundle) |
| Publish Directory | `dist` |

### Environment variables — API (Web Service)

| Variable | Value |
|---|---|
| `PORT` | **Injected by Render — do not set it.** The server reads `process.env.PORT` (default `4000` locally) and binds `0.0.0.0`. Hardcoding a port is the #1 Render failure; this app already handles it. |
| `NODE_ENV` | `production` |
| `FRONTEND_ORIGIN` | `https://<frontend-name>.onrender.com` — **exact match, no trailing slash** (see the CORS gotcha below) |
| `FIREBASE_WEB_API_KEY` | Firebase Web API key (same value as `lib/firebase_options.dart`) |
| `ADMIN_UIDS` | Comma-separated Firebase Auth UIDs allowed to use the API |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | The **entire service-account JSON** as a single-line value. Render has no secrets folder, so inline JSON is the supported shape. Collapse the key first: `jq -c . service-account.json`, then paste the output as the value. This env var **wins** over `SERVICE_ACCOUNT_PATH` / `GOOGLE_APPLICATION_CREDENTIALS`. |
| `FIREBASE_PROJECT_ID` | Optional — defaults to `interior-design-256c5` |
| `SERVICE_ACCOUNT_PATH` | Optional alternative (a file path) — only useful if you mount the file yourself; the JSON env var wins |

**Never commit the service-account key.** `web/.gitignore` covers
`service-account*.json`, `secrets/` and `.env`. Paste it only into Render's
Environment tab (or your local `.env`).

### Environment variables — frontend (Static Site)

| Variable | Value |
|---|---|
| `VITE_API_BASE_URL` | `https://<api-name>.onrender.com/api` — note the **`/api` suffix**. This is a **build-time** variable (Vite inlines it into the bundle): set it *before* the first build, and after changing it trigger **Manual Deploy → Clear build cache & deploy** so the new value is baked in. |

### The CORS gotcha (login fails with a CORS error)

The backend only ever emits CORS headers for the one origin in
`FRONTEND_ORIGIN` (exact string match in `web/backend/src/app.ts`). So:

1. Create the frontend Static Site first and note its final URL —
   `https://intellar-admin-frontend.onrender.com` (pick the name you want;
   Render may hand you a `*.onrender.com` default if you skip this).
2. Set the API's `FRONTEND_ORIGIN` to that URL **exactly** (no trailing
   slash, `https://`, including any custom domain).
3. Save — Render restarts the API with the new env.

If this is wrong, every API call from the browser fails with
`Access-Control-Allow-Origin` / CORS errors and the login form shows
"Can't reach the admin API". Similarly, if `VITE_API_BASE_URL` points at the
wrong host (or lacks `/api`), requests 404 or fail — the frontend has no
Firebase SDK and talks **only** to this API.

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
`INVALID_DOCUMENT_PATH` (400), `STORAGE_READ_ERROR` (500),
`PARTIAL_DELETE` (500), `FIREBASE_NOT_CONFIGURED` (503),
`INTERNAL_ERROR` (500), …

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
  index.ts              entry — starts Express
  app.ts                CORS → JSON parsing → routes → 404 → error handler
  config/env.ts         env parsing (dotenv)
  config/firebase.ts    lazy firebase-admin init (service account / ADC)
  middleware/
    authenticate.ts     step 1: verify the Firebase ID token        → req.user
    requireAdmin.ts     step 2: admin claim / ADMIN_UIDS allowlist
    validate.ts         step 3: zod body/query/param validation
    errorHandler.ts     step 5: central JSON error rendering
    types.ts            req.user typing
  routes/
    auth.routes.ts      /auth/login (public proxy), /auth/me
    users.routes.ts     list/detail/verification/password-reset/delete
    stats.routes.ts     /stats
    verification.routes.ts  /verification/applications… (IC review queue;
                        authenticate + requireAdmin on every route)
  services/             step 4: handlers delegate here → persistence
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

The existing Dart server in `server/` (email verification + JSON-file
marketplace API) is **not** touched and not duplicated here — this backend
only does admin monitoring/mutation against real Firebase.

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
- ✅ Render readiness: `render.yaml` blueprint declares both services
  (`healthCheckPath: /api/health`, native Node build, static `dist/`);
  `FIREBASE_SERVICE_ACCOUNT_JSON` (inline JSON, env var wins) is supported
  alongside `SERVICE_ACCOUNT_PATH` / `GOOGLE_APPLICATION_CREDENTIALS`.
- ⚠️ Not exercised against live credentials: sign-in, user listing and all
  mutations need a real service-account key + an admin Firebase account —
  including the Render deploy end-to-end (CORS round-trip, login proxy).
  Configure `web/backend/.env` (§2) or the Render env vars (§3) to try it.
