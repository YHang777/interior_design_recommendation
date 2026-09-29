import 'local_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class AppConfig {
  // NOTE: no third-party key lives in this app. AI chat goes through
  // [chatApiUrl] (GEMINI_API_KEY) and 3D generation through [tripoApiUrl]
  // (TRIPO_API_KEY) — both env vars on the backend. Anything compiled into an
  // APK can be extracted from it, so a key shipped here is a leaked key.

  // Cloudinary (product photos — GLB models go to Supabase; see below).
  // Firebase Storage now requires the Blaze plan, so the app uploads through
  // Cloudinary's free tier using an UNSIGNED upload preset (no API secret on
  // the client). Sourced from LocalConfig; make those fields nullable again
  // (and null-valued) to fall back to --dart-define=CLOUDINARY_CLOUD_NAME=...
  // / CLOUDINARY_UPLOAD_PRESET=...
  static const String cloudinaryCloudName = LocalConfig.cloudinaryCloudName;

  /// Upload preset name configured for unsigned uploads in the Cloudinary
  /// console (Settings → Upload → Upload presets).
  static const String cloudinaryUploadPreset =
      LocalConfig.cloudinaryUploadPreset;

  // Supabase Storage (published GLB models — photos stay on Cloudinary; see
  // lib/services/media/supabase_media_store.dart). Free tier: 1 GB storage,
  // 50 MB per-file cap — a fit for large textured Tripo output. Sourced
  // from LocalConfig; make those fields nullable again (and null-valued) to
  // fall back to --dart-define=SUPABASE_URL=... / SUPABASE_ANON_KEY=...
  static const String supabaseUrl = LocalConfig.supabaseUrl;

  /// Supabase anon/public key (Settings → API). Public BY DESIGN — access is
  /// governed by the bucket's storage policies, not by keeping it secret.
  static const String supabaseAnonKey = LocalConfig.supabaseAnonKey;

  /// Storage bucket hosting the published GLBs.
  static const String supabaseModelsBucket = LocalConfig.supabaseModelsBucket ??
      String.fromEnvironment(
        'SUPABASE_MODELS_BUCKET',
        defaultValue: 'product_models',
      );

  // Marketplace API URL; empty/null means use asset fallback (`assets/data/products.json`).
  static String get marketplaceApiUrl {
    final fromLocal = LocalConfig.marketplaceApiUrl;
    final fromEnv = const String.fromEnvironment('MARKETPLACE_API_URL', defaultValue: '');
    String url = fromLocal.isNotEmpty ? fromLocal : fromEnv;
    // Map localhost to Android emulator host when running on Android (non-web)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }

  // Middleware URL for the custom email-verification flow (sends links via
  // Brevo and hosts the /verify-email/confirm page). Mirrors
  // [marketplaceApiUrl] including the Android-emulator localhost rewrite.
  static String get verificationApiUrl {
    final fromLocal = LocalConfig.verificationApiUrl;
    final fromEnv = const String.fromEnvironment('VERIFICATION_API_URL', defaultValue: '');
    String url = fromLocal.isNotEmpty ? fromLocal : fromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }

  // AI chat proxy (POST /api/ai/chat) — the same server as
  // [verificationApiUrl], so it reads the same config: the Gemini key is
  // an env var on that backend, never in this app. Mirrors the
  // Android-emulator localhost rewrite above.
  static String get chatApiUrl {
    final fromLocal = LocalConfig.verificationApiUrl;
    final fromEnv = const String.fromEnvironment('VERIFICATION_API_URL', defaultValue: '');
    String url = fromLocal.isNotEmpty ? fromLocal : fromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }

  // 3D-generation proxy (POST /api/tripo/generation/image-to-model,
  // GET /api/tripo/tasks/{id}) — again the same server, for the same reason:
  // TRIPO_API_KEY is a paid credential and stays in the backend's env.
  static String get tripoApiUrl {
    final fromLocal = LocalConfig.verificationApiUrl;
    final fromEnv = const String.fromEnvironment('VERIFICATION_API_URL', defaultValue: '');
    String url = fromLocal.isNotEmpty ? fromLocal : fromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }
}