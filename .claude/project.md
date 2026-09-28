# Intellar — Interior Design & Furniture Recommendation App

Project reference for Claude Code sessions. **Read this first**; it reflects the
codebase as of 2026-09-29 (post-redesign, unified web host live on Render).

---

## 1. Overview

FYP (Final Year Project) by **Lim Yee Hang** (24PMR10425), Tunku Abdul Rahman
University of Management and Technology (Penang branch), supervisor **Ms Tan
Kee Oon**, academic year 2025/26.

A mobile app for interior design and furniture shopping with two roles:

- **Homeowner (customer)** — scan/design rooms, get AI recommendations, place
  furniture in AR, browse a furniture marketplace, plan budgets.
- **Supplier** — manage a product catalogue, fulfil orders, see analytics.
- **Admin** — a web console (separate from the app) for user/supplier
  monitoring, IC verification review, and account help.

The app is **implemented**, not a skeleton: the pre-redesign monolith
(`main.dart` ~9,400 lines of hardcoded UI) was fully rebuilt into the feature
structure below. Marketplace is Firestore-backed with real-time sync; AR
places true-size furniture via procedural GLBs; email verification is a live
production flow.

---

## 2. System Architecture (as built)

Three deliverables in one repo:

| Part | Tech | Role |
|---|---|---|
| `lib/` | Flutter 3.29+ / Dart | The mobile app (customer + supplier) |
| `web/` | React 18 + Vite 6 (SPA) and Express 4 + firebase-admin (Node 22) | **Unified web host** — admin console + email verification — one Render service, one URL |
| `server/` | Dart (shelf-free, plain `HttpServer`) | **Legacy** — the original email-verification server. Kept as local-dev + token-format reference only. Its JSON marketplace endpoints are dropped (marketplace is Firestore). Not deployed. |

### Live hosting (Render)

One service `interior-design-recommendation` on the free tier, image built by
`web/Dockerfile` (multi-stage; build context = **repo root**):

| URL | Serves |
|---|---|
| `https://interior-design-recommendation.onrender.com/` | 302 → `/admin` |
| `…/admin` | React admin console (static SPA, `base: '/admin/'`) |
| `…/admin/api/*` | Admin API (alias `/api/*` = same router; health check uses `/api/health`) |
| `…/verify-email/send` | POST — mints HMAC token, sends Brevo email (called by the app at registration) |
| `…/verify-email/confirm` | GET — token check page; sets Firebase `emailVerified` via firebase-admin |

**Render settings that must not regress:**
- **Dockerfile Path = `web/Dockerfile`** (if this reverts to `server/Dockerfile`,
  the OLD Dart image builds and the health check at `/api/health` times out).
- **Health Check Path = `/api/health`** → `{status:'ok', firebaseConfigured, verificationEmailConfigured}`.
- Env: `FIREBASE_PROJECT_ID`, `FIREBASE_WEB_API_KEY` (Identity Toolkit login
  proxy), `ADMIN_UIDS` (comma-separated UIDs), `FIREBASE_SERVICE_ACCOUNT_JSON`
  (paste whole key JSON — **secret, never commit, never paste into chat**; the
  old `SERVICE_ACCOUNT_PATH` secret-file mount also works), `VERIFY_TOKEN_SECRET`,
  `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`, `PUBLIC_BASE_URL`
  (optional override for link base), `ADMIN_STATIC_DIR` (set in the image).
- Free tier cold starts (~1 min). Health check must return 2xx or deploys fail
  after ~18 min.

### Email verification flow (production = Node port in `web/backend`)

- Stateless HMAC-SHA256 token: `base64url(payload).base64url(sig)`, payload
  `{uid, email, exp}` (epoch seconds, TTL 24h), **unpadded** base64url.
  Token format is **byte-compatible** with the Dart implementation — links
  already sent stay valid across the migration.
- Send: `POST /verify-email/send` `{email, uid}` → Brevo v3 `/smtp/email`
  transactional. 503 if unconfigured, 502 generic message on Brevo failure
  (never leaks provider detail).
- Confirm: `GET /verify-email/confirm?token=…` → success/failure HTML card
  (inline CSS, same markup as the Dart version) + `updateUser(uid, {emailVerified: true})`.
- Link base = request `Host` + `X-Forwarded-Proto` (first comma token),
  fallback `https`, overridable by `PUBLIC_BASE_URL`.
- The app side lives in `lib/features/auth/` +
  `lib/services/verification/verification_application_service.dart` (IC
  applications) and calls the paths above.

### Admin auth & authorization

- Login = Identity Toolkit `signInWithPassword` proxy (`/admin/api/auth/login`);
  no Firebase SDK in the browser.
- Admin = UID listed in `ADMIN_UIDS` **or** custom claim `{admin: true}`.
- Firestore profile is optional at login (admin has no `role` field — the app
  parses role as homeowner/supplier only).
- Admin features: overview stats, user/supplier monitoring, IC verification
  review queue (`verification_applications`), password reset help, safe account
  deletion (cascade: cart/wishlist subcollections, deactivate owned products).
- IC document bytes are admin-only — no public URLs.

---

## 3. Directory Structure

### Flutter app (`lib/`)

```
lib/
├── main.dart                  # Firebase init → first-auth seed/migration → ProviderScope → app
├── app.dart                   # MaterialApp.router
├── config/                    # app_config.dart, local_config.dart (API keys — see Secrets)
├── core/
│   ├── constants/             # app_colors, app_strings
│   ├── router/                # app_router.dart (GoRouter, role redirects), route_names.dart
│   ├── theme/                 # app_theme, text_styles (GoogleFonts)
│   └── utils/                 # formatters, pricing, validators
├── features/
│   ├── auth/                  # clean architecture: domain, data, presentation
│   │   └── login, register, forgot_password, verify_email
│   ├── customer/
│   │   ├── ar/                # AR viewer + data/: glb_generator, glb_rescaler, glb_bounds,
│   │   │                      #   glb_file_saver, furniture_model_library, room_finishes
│   │   ├── budget/            # budget planner
│   │   ├── homeowner/         # dashboard, shell, scan, ai_recommendation, saved_designs, profile
│   │   │                      #   data/: supabase_room_design_datasource (polling), providers/
│   │   ├── marketplace/       # marketplace, product_detail, cart, checkout, order_confirmation,
│   │   │                      #   order_history, buyer_order_detail, wishlist + providers/
│   │   └── scanner/           # room_scanner (camera + ML Kit image labeling)
│   └── supplier/              # presentation/{providers,screens}: shell, dashboard,
│                              #   product_management, product_form, order_management,
│                              #   order_detail, analytics, supplier_profile
├── models/                    # product, cart_item, order, review, room_design,
│                              #   product_category, app_config_data
├── services/
│   ├── gemini_service.dart
│   ├── marketplace_repository.dart   # Firestore CRUD + seed/migration
│   ├── recent_searches_store.dart
│   ├── verification/                # verification_application_model/service (supplier IC apply)
│   ├── media/                       # MediaStore → HybridMediaStore: photos → Cloudinary,
│   │                                #   GLBs → Supabase
│   └── model_generation/            # model_glb_resolver, tripo_generator, tripo_poll_state,
│                                    #   generation_decider, model_generation_trigger
└── shared/widgets/            # product_card, floating_nav_bar, skeleton_loader, empty_state,
                               #   confirm_dialog, gradient_scaffold, … (21 shared widgets)
```

### Web host (`web/`)

```
web/
├── Dockerfile                 # THE Render image (3 stages: Vite build → tsc → node:22 runtime)
├── README.md                  # deploy guide + env reference
├── .env.example
├── backend/src/
│   ├── app.ts                 # unified host assembly (mount order matters — see file header)
│   ├── index.ts               # boot + config-status banner
│   ├── config/                # env.ts (zod), firebase.ts (admin SDK credential chain)
│   ├── lib/                   # verification-token.ts (+test), verification-mailer.ts
│   ├── middleware/            # auth, admin guard, errorHandler (400 INVALID_JSON etc.)
│   ├── routes/                # index (health), auth, users, stats, verification,
│   │                          #   verify-email.routes.ts (+test)
│   └── services/              # identity, users, applications, deletion, verification,
│                              #   verification-email
└── frontend/src/              # React 18 + TS + Vite 6; pages: Login, Overview, Users,
                               #   Verification; api/client.ts (VITE_API_BASE_URL);
                               #   no react-router (state-switched pages)
```

### Legacy Dart server (`server/`)

`bin/server.dart`, `lib/{verification_token,verification_mailer,verify_handlers,firebase_admin_client}.dart`,
`test/` (7 token tests). **Not deployed.** Useful only for local token debugging;
keep token format in sync with `web/backend/src/lib/verification-token.ts`.

### Repo root

`firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`
(future Blaze upgrade — Firebase Storage is currently unavailable on Spark),
`lib/firebase_options.dart`, `test/` (Flutter widget/unit tests), `assets/`
(seed `data/products.json`, ~70 images, 10 bundled `.glb` models).

---

## 4. Tech Stack

| Layer | Technology |
|---|---|
| Mobile frontend | Flutter 3.29+, Dart SDK ^3.7, Android-first (minSdk 28, compileSdk 36) |
| State management | **Riverpod** (`flutter_riverpod` 2.6) — StreamProviders for live data |
| Navigation | **GoRouter** 14.8 — two `StatefulShellRoute.indexedStack` shells + role redirects |
| Backend / DB | Firebase Auth + **Cloud Firestore** (marketplace source of truth) + Supabase PostgREST (room designs) |
| Media | Cloudinary (product photos, unsigned preset), Supabase Storage (GLB models) |
| AI | Google Gemini (`google_generative_ai`, model `gemini-2.0-flash`) for recommendations |
| 3D generation | Tripo AI (async poll) with procedural GLB generator from seller dimensions first |
| AR | `ar_flutter_plugin_2` (ARCore/SceneView) — true-size placement, floor/wall finish overlays |
| Camera / ML | `camera` + `google_mlkit_image_labeling` (room scanner) |
| Web admin | React 18 + Vite 6 + TypeScript, Express 4 + firebase-admin 13 + zod, Node 22 |
| Email | Brevo (Sendinblue) v3 SMTP API — transactional verification mail |
| Hosting | Render free tier (one Docker service), Firebase project `interior-design-256c5` |
| Testing | `flutter_test` (widget/unit), `node:test` via `node --import tsx --test`, Dart `server/` tests |

---

## 5. System Modules (implementation status)

| Module | Status | Notes |
|---|---|---|
| Account / Profile | ✅ | Firebase Auth; login/register/forgot-password; email verification live (Brevo). 2FA face recognition was planned — **not implemented**. |
| AR Visualization | ✅ | True-size furniture from seller dims (procedural GLB) → Tripo fallback → bundled library; floor/wall finish overlays with swatches. Needs a physical device for runtime testing. |
| AI Recommendation Engine | ✅ | Gemini chat-style recommender with inline style/room selection. |
| Marketplace (eco filter) | ✅ | Firestore real-time: catalog, cart, checkout, orders, reviews, wishlist. Membership tiers count DELIVERED orders only. Eco/energy filter exists in the product model/UI. |
| Budget Planner | ✅ | Budget plans + estimates (MYR). |
| Role Dashboards | ✅ | Homeowner dashboard + supplier dashboard/analytics. |
| Virtual Staging | ⚠️ partial | AI style imagery + room scans exist; a dedicated virtual-staging module is not a separate feature. |
| Supplier IC Verification | ✅ | Supplier applies in-app; admin reviews in `/admin` (IC docs admin-only). |
| Admin Console | ✅ | Users, stats, verification review, password help, safe deletion. |

---

## 6. Data Model (as coded)

Firestore (`interior-design-256c5`):

| Path | Contents |
|---|---|
| `products` | Public read, auth write. `stock` updated with **deltas** in transactions. `isActive` soft-delete. |
| `products/{id}/reviews` | Doc id = order id → one review per order. |
| `orders` | Participant-scoped via `supplierIds` array; status state machine (transactional next-step). |
| `users/{uid}` | Profile (role: homeowner/supplier — no admin role here). |
| `users/{uid}/cart`, `users/{uid}/wishlist` | Per-user subcollections. |
| `verification_applications/{uid}` | Supplier IC verification applications (status, document refs). |

Supabase (PostgREST, project `wlgqhhnezniodelidbvz`):

| Table | Contents |
|---|---|
| `room_designs` | id, name, room_type, width_cm, height_cm, furniture JSONB, detected_items JSONB, image_path, timestamps, user_id. RLS disabled; anon key (Firebase Auth is the real auth). |

Dart models in `lib/models/`: `product.dart`, `cart_item.dart`, `order.dart`,
`review.dart`, `room_design.dart`, `product_category.dart`, `app_config_data.dart`.

**Pricing invariant (do not regress):** ONE source —
`lib/core/utils/pricing.dart` `computePriceBreakdown` (free shipping on
post-membership-discount chargeable; 6% tax on chargeable). `PriceBreakdown.fromStored`
for persisted orders.

**Marketplace invariants:** `createOrder` is idempotent (deterministic id +
transaction existence check before stock decrement); `updateProduct` uses stock
deltas; `updateOrderStatus` transactional state machine; cart rows reconcile
against the live products stream; seeding runs once after first sign-in
(SharedPreferences key `marketplace_seed_v1`).

---

## 7. Key Design Patterns

- Auth state drives routing (`authStateProvider` watched by `appRouterProvider`).
  Unauth → `/login`; homeowner blocked from `/supplier/**`; supplier blocked
  from cart/checkout/orders/wishlist.
- Shells (`HomeownerShell` 6 branches, `SupplierShell` 5 branches) are
  `StatelessWidget`s with only a `NavigationBar` — each screen owns its Scaffold/AppBar.
- 3D model pipeline: procedural GLB from seller dimensions → Tripo AI fallback →
  bundled `assets/models/` fallback (`generation_decider.dart`).
- AR viewer accepts `Product`, `List<ArFurnitureItem>`, or no args (full catalog).
- Intra-lib imports are **relative**; Dart clamps `..` at the package root — when
  moving files recompute each relative URI, never blind-prepend `../`.
- Marketplace UI is StreamProvider-driven (seller publishes → buyer grid updates
  instantly).
- ProductCard uses `Flexible(flex: 2, fit: FlexFit.loose)` for the info section
  (overflow fixes at 320dp are tested in `test/`).
- Web backend: deps-injected routers for testability; middleware order in
  `app.ts` is the contract (CORS lock → JSON → verify-email → api mounts → SPA
  static/fallback → 404 → error handler).

---

## 8. Development Methodology

Evolutionary prototyping: build vertical slices, verify on device/tests, refine.
Recent history: broken HTTP+asset marketplace → Firestore rebuild (Sep 2026) →
monolith-to-features redesign (Riverpod/GoRouter) → AR pipeline → unified web
host (admin + email verification) on Render (Sep 29 2026).

Prefer small verified steps; keep pricing/order invariants; match surrounding
code style. Flutter UI work needs widget tests for layout fixes (`test/`).

---

## 9. Project Constraints

- **Solo developer** (FYP) — favor simple, maintainable solutions.
- **Android-first** (minSdk 28); iOS/Windows folders exist but are not targeted.
- **Malaysian market**: MYR pricing, 6% SST-style tax in the pricing helper.
- **Free-tier everything**: Render (cold starts), Firebase Spark plan (no
  Storage → hybrid Cloudinary/Supabase media), Cloudinary 25GB/10MB, Supabase
  1GB/50MB. Design for these caps.
- ~60+ stock assets (images) and 10 bundled GLB models; GoogleFonts (online).

---

## 10. Secrets & Safety Rules

- Service-account JSON and API keys are **secrets**: never commit, never paste
  into chat. Sources: `web/.env` / `web/backend/.env` (gitignored), Render
  Environment tab, `lib/config/local_config.dart` for the app's client keys.
- `web/.gitignore` covers `service-account*.json`, `secrets/`, `.env`; root
  `.gitignore` covers `.env`, `server/secrets/`.
- Passwords are never stored or logged. Admin API refuses non-admin UIDs.

---

## 11. Remaining TODOs

1. Deploy updated `firestore.rules` / `storage.rules` for the IC verification
   review queue (admin-only document reads) — `firebase deploy --only firestore`
   when ready; Storage rules only matter after a Blaze upgrade.
2. One real end-to-end registration email through the live Node port (send →
   Brevo inbox → confirm page → `emailVerified: true`).
3. Register the Android debug SHA-1 in the Firebase console if sign-in still
   fails with DEVELOPER_ERROR.
4. (Nice to have) deprecation note in `server/` docs; keep `server/Dockerfile`
   from ever being selected on Render again.

---

## 12. Useful Entry Points

| Want to… | Start at |
|---|---|
| App startup / DI | `lib/main.dart`, `lib/app.dart` |
| Routes & roles | `lib/core/router/app_router.dart`, `route_names.dart` |
| Marketplace logic | `lib/services/marketplace_repository.dart`, `lib/core/utils/pricing.dart` |
| AR / 3D | `lib/features/customer/ar/`, `lib/services/model_generation/` |
| Email verification (prod) | `web/backend/src/routes/verify-email.routes.ts`, `lib/verification-token.ts` |
| Admin API | `web/backend/src/routes/`, `services/` |
| Deploy | `web/README.md` §3, `web/Dockerfile` |
| Structure deep map | memory `project-structure-lookup` (update it when structure changes) |
