import 'local_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class AppConfig {

  static const String cloudinaryCloudName = LocalConfig.cloudinaryCloudName;

  static const String cloudinaryUploadPreset =
      LocalConfig.cloudinaryUploadPreset;

  static const String supabaseUrl = LocalConfig.supabaseUrl;

  static const String supabaseAnonKey = LocalConfig.supabaseAnonKey;

  static const String supabaseModelsBucket = LocalConfig.supabaseModelsBucket ??
      String.fromEnvironment(
        'SUPABASE_MODELS_BUCKET',
        defaultValue: 'product_models',
      );

  static String get marketplaceApiUrl {
    final fromLocal = LocalConfig.marketplaceApiUrl;
    final fromEnv = const String.fromEnvironment('MARKETPLACE_API_URL', defaultValue: '');
    String url = fromLocal.isNotEmpty ? fromLocal : fromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (url.startsWith('http://localhost')) {
        url = url.replaceFirst('http://localhost', 'http://10.0.2.2');
      }
    }
    return url;
  }

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
