# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# Unified Intellar web host — ONE container, ONE Render service, ONE URL:
#
#   /verify-email/*   email verification API + confirm page (mobile app flow)
#   /admin            the React admin console (static SPA)
#   /admin/api/*      admin API  (/api/* is the same API, as an alias)
#
# Replaces the old Dart-only `server/Dockerfile` on the
# `interior-design-recommendation` Render service. Build context is the REPO
# ROOT (same as the old image). The email-verification routes are the Node
# port in web/backend (byte-compatible HMAC tokens — links already in inboxes
# keep working).
# ─────────────────────────────────────────────────────────────────────────────

# ── Stage 1: admin SPA (Vite) ────────────────────────────────────────────────
FROM node:22-bookworm-slim AS frontend-build
WORKDIR /build
COPY web/frontend/package.json web/frontend/package-lock.json ./frontend/
RUN cd frontend && npm ci
COPY web/frontend ./frontend
# Same-origin production build: assets under /admin/, API at /admin/api.
ARG VITE_API_BASE_URL=/admin/api
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
RUN cd frontend && npm run build

# ── Stage 2: admin API + email verification (TypeScript) ─────────────────────
FROM node:22-bookworm-slim AS backend-build
WORKDIR /build
COPY web/backend/package.json web/backend/package-lock.json ./backend/
RUN cd backend && npm ci
COPY web/backend ./backend
RUN cd backend && npm run build

# ── Stage 3: runtime ─────────────────────────────────────────────────────────
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
COPY web/backend/package.json web/backend/package-lock.json ./backend/
RUN cd backend && npm ci --omit=dev
COPY --from=backend-build /build/backend/dist ./backend/dist
COPY --from=frontend-build /build/frontend/dist ./frontend-dist
# Where app.ts looks for the SPA (it also falls back to web/frontend/dist).
ENV ADMIN_STATIC_DIR=/app/frontend-dist
# Render injects PORT; never hardcode it. EXPOSE is documentation only.
EXPOSE 8080
CMD ["node", "backend/dist/index.js"]
