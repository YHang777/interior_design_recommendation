import 'package:shared_preferences/shared_preferences.dart';

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
