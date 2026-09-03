# ── Build stage ───────────────────────────────────────────────────────
FROM dart:stable AS build
WORKDIR /app
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/bin ./bin
COPY server/lib ./lib
RUN dart compile exe bin/server.dart -o bin/server_exe

# ── Runtime stage (compiled exe needs glibc → debian-slim) ─────────────
FROM debian:bookworm-slim
# CA certificates — without them every HTTPS call (Brevo, Google OAuth2,
# Identity Toolkit) fails with CERTIFICATE_VERIFY_FAILED.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/bin/server_exe /app/bin/server_exe
# Seed data for the marketplace products store (Render disk is ephemeral;
# the JSON stores are recreated on write).
COPY assets/data/products.json /app/assets/data/products.json
ENV DATA_DIR=/app/data \
    PRODUCTS_SEED_ASSET=/app/assets/data/products.json
EXPOSE 8080
CMD ["/app/bin/server_exe"]
