import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';

/// Persists the buyer's saved design chats on-device.
///
/// Storage is one JSON string under [prefsKey] plus the last-open chat id
/// under [activeIdKey]. The store is a dumb IO service — ordering,
/// open/new/delete semantics and in-memory state live in
/// `ChatHistoryNotifier` (design_providers.dart). Caps live here so every
/// write stays bounded (shared_preferences loads the whole blob, and
/// Android's binder limit is ~1MB).
class ChatHistoryStore {
  static const String prefsKey = 'ai_chat_history';
  static const String activeIdKey = 'ai_chat_active_session_id';
  static const int maxSessions = 15;
  static const int maxMessagesPerSession = 40;
  static const int maxMessageChars = 2000;

  Future<List<ChatSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatSession.fromJson)
          .toList();
    } catch (e) {
      // A corrupted blob must not brick the screen — start fresh instead.
      return const [];
    }
  }

  Future<String?> loadActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(activeIdKey);
  }

  Future<void> save(
    List<ChatSession> sessions, {
    String? activeSessionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = _cap(sessions);
    await prefs.setString(
      prefsKey,
      jsonEncode([for (final s in capped) s.toJson()]),
    );
    if (activeSessionId == null) {
      await prefs.remove(activeIdKey);
    } else {
      await prefs.setString(activeIdKey, activeSessionId);
    }
  }

  /// Newest-first trim: at most [maxSessions] chats, each with at most
  /// [maxMessagesPerSession] newest messages and [maxMessageChars]-char texts.
  static List<ChatSession> _cap(List<ChatSession> sessions) {
    final sorted = [...sessions]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final s in sorted.take(maxSessions))
        s.copyWith(
          messages: [
            for (final m in s.messages.skip(
              s.messages.length > maxMessagesPerSession
                  ? s.messages.length - maxMessagesPerSession
                  : 0,
            ))
              m.text.length > maxMessageChars
                  ? ChatMessage(
                      role: m.role,
                      text: m.text.substring(0, maxMessageChars),
                      createdAt: m.createdAt,
                      // Cards survive the text trim — dropping them here
                      // would silently un-render every old suggestion.
                      suggestions: m.suggestions,
                    )
                  : m,
          ],
        ),
    ];
  }
}
