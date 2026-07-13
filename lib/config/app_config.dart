import 'local_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class AppConfig {
  // Prefer LocalConfig overrides; otherwise use compile-time environment with safe defaults.
  static const String geminiApiKey = LocalConfig.geminiApiKey ?? const String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // Gemini model name; can be overridden locally.
  static const String geminiModel = LocalConfig.geminiModel ?? const String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.0-flash',
  );

  // Marketplace API URL; empty/null means use asset fallback (`assets/data/products.json`).
  static String get marketplaceApiUrl {
    final fromLocal = LocalConfig.marketplaceApiUrl;
    final fromEnv = const String.fromEnvironment('MARKETPLACE_API_URL', defaultValue: '');
    String url = fromLocal ?? fromEnv;
    // Map localhost to Android emulator host when running on Android (non-web)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }
}