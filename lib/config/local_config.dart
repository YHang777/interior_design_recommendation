/// Local overrides for app configuration.
///
/// Edit these values to set keys/URLs without passing `--dart-define`.
/// Keep in mind: avoid committing real secrets to a public repo.
class LocalConfig {
  // No Gemini or Tripo settings here on purpose: both go through backend
  // proxies (`AppConfig.chatApiUrl` / `AppConfig.tripoApiUrl`), which hold
  // GEMINI_API_KEY and TRIPO_API_KEY server-side. A key compiled into an APK
  // can be pulled out of the binary — it is a leaked key, not a hidden one.

  /// Marketplace API base URL. Set to your backend list endpoint.
  /// Uses the local Dart server by default (run `cd server && dart run bin/server.dart`).
  /// Set to `null` to use bundled asset fallback only.
  static const String marketplaceApiUrl = 'http://localhost:8080';

  /// Verification middleware URL — sends verification emails via Brevo and
  /// hosts the `/verify-email/confirm` page. `http://localhost:8088` reaches
  /// the local Dart server (8080 is Apache; the Android emulator rewrites
  /// localhost to 10.0.2.2). Set this to the Render URL (https://…
  /// onrender.com) once deployed.
  ///
  /// This is also the base for the AI chat and 3D-generation proxies — one
  /// backend, one URL.
  static const String verificationApiUrl = 'https://interior-design-recommendation.onrender.com';

  /// Cloudinary cloud name (dashboard top-left, e.g. "dxyz123").
  ///
  /// Required for product photo uploads. Set to `null` (make the field
  /// nullable again) to fall back to `--dart-define=CLOUDINARY_CLOUD_NAME=`.
  static const String cloudinaryCloudName = 'qydpaw3g'; // e.g., "dxyz123"

  /// Cloudinary UNSIGNED upload preset name.
  ///
  /// Create it in the Cloudinary console (Settings → Upload → Upload
  /// presets → Add upload preset → Signing Mode: Unsigned). Set to `null`
  /// (make the field nullable again) to fall back to
  /// `--dart-define=CLOUDINARY_UPLOAD_PRESET=`.
  static const String cloudinaryUploadPreset = 'interior_app'; 

  /// Supabase project URL, e.g. "https://abcd1234.supabase.co".
  ///
  /// Required for GLB model publishing (photos stay on Cloudinary) — the
  /// free tier's 50 MB per-file cap fits large Tripo output where
  /// Cloudinary's 10 MB cap could reject it. Set to `null` (make the field
  /// nullable again) to fall back to `--dart-define=SUPABASE_URL=...`.
  static const String supabaseUrl = 'https://wlgqhhnezniodelidbvz.supabase.co'; // e.g., "https://abcd1234.supabase.co"

  /// Supabase anon/public key (Settings → API). Public BY DESIGN — access is
  /// governed by the bucket's storage policies, not by keeping it secret.
  /// Set to `null` (make the field nullable again) to fall back to
  /// `--dart-define=SUPABASE_ANON_KEY=...`.
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndsZ3FoaG5lem5pb2RlbGlkYnZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MzUzMDQsImV4cCI6MjEwNDAxMTMwNH0.Pz2KTjMTHqXq8hZ7EhymKk5Lr_a4Mg41jhy0pmQY66o'; // e.g., "eyJhbGciOi..."

  /// Supabase Storage bucket hosting the published GLBs. Leave `null` to use
  /// the AppConfig default (`product_models`).
  static const String? supabaseModelsBucket = null; // e.g., "product_models"
}