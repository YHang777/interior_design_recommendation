/// Local overrides for app configuration.
///
/// Edit these values to set keys/URLs without passing `--dart-define`.
/// Keep in mind: avoid committing real secrets to a public repo.
class LocalConfig {
  /// Gemini API key. Set to your key string to enable AI chat.
  /// Leave as `null` to use environment or default fallback.
  static const String? geminiApiKey = null; // e.g., "AIza...your-key"

  /// Gemini model override. Leave `null` to use the default from AppConfig.
  static const String? geminiModel = null; // e.g., "gemini-2.0-flash"

  /// Marketplace API base URL. Set to your backend list endpoint.
  /// Uses the local Dart server by default (run `dart run server/bin/server.dart`).
  /// Set to `null` to use bundled asset fallback only.
  static const String marketplaceApiUrl = 'http://localhost:8080';

  /// Tripo 3D API key (get one at https://platform.tripo3d.ai).
  ///
  /// When set, products with real dimensions and a network image get an
  /// AI-generated 3D model from Tripo at publish time (textured image-to-
  /// model). Tripo is pay-as-you-go (~US$0.30 per textured model after any
  /// free signup credits) — leave `null` to stay on the free built-in
  /// procedural generator. Set to `null` to use environment or default.
  static const String? tripoApiKey = null; // e.g., "tripo_..."

  /// Tripo model version. Leave `null` to use the AppConfig default
  /// (`v3.1-20260211`, the current v3 release).
  static const String? tripoModelVersion = null; // e.g., "v3.1-20260211"
}