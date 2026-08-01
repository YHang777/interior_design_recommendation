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
}