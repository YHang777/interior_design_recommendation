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
}