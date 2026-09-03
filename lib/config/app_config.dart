import 'local_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class AppConfig {
  // Prefer LocalConfig overrides; otherwise use compile-time environment with safe defaults.
  static const String geminiApiKey = LocalConfig.geminiApiKey ??
      String.fromEnvironment(
        'GEMINI_API_KEY',
        defaultValue: '',
      );

  // Gemini model name; can be overridden locally.
  static const String geminiModel = LocalConfig.geminiModel ??
      String.fromEnvironment(
        'GEMINI_MODEL',
        defaultValue: 'gemini-2.0-flash',
      );

  // Tripo 3D API key (https://platform.tripo3d.ai) — empty = procedural-only.
  // Pay-as-you-go: ~US$0.30 per textured image-to-model output (free signup
  // credits may apply). Override locally in LocalConfig or with
  // --dart-define=TRIPO_API_KEY=...
  static const String tripoApiKey = LocalConfig.tripoApiKey ??
      String.fromEnvironment(
        'TRIPO_API_KEY',
        defaultValue: '',
      );

  // Tripo model version passed as the image-to-model "model" field. Defaults
  // to the current v3 release; override locally in LocalConfig or with
  // --dart-define=TRIPO_MODEL_VERSION=...
  static const String tripoModelVersion = LocalConfig.tripoModelVersion ??
      String.fromEnvironment(
        'TRIPO_MODEL_VERSION',
        defaultValue: 'v3.1-20260211',
      );

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
}