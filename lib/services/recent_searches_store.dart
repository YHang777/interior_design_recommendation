import 'package:shared_preferences/shared_preferences.dart';

/// Persists the buyer's recent marketplace search terms on-device.
///
/// Storage is a single `StringList` under [prefsKey]; terms are kept
/// most-recent-first and capped at [maxEntries] (10). The store is a dumb
/// IO service — the in-memory state and record/remove/clear semantics live
/// in `RecentSearchesNotifier` (marketplace_providers.dart).
class RecentSearchesStore {
  static const String prefsKey = 'marketplace_recent_searches';
  static const int maxEntries = 10;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKey) ?? const [];
  }

  Future<void> save(List<String> terms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKey, terms.take(maxEntries).toList());
  }
}
