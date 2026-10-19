import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';

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
                      suggestions: m.suggestions,
                    )
                  : m,
          ],
        ),
    ];
  }
}
