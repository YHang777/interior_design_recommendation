import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../../../config/app_config.dart';
import '../../../../../core/utils/user_errors.dart';

/// One conversation turn as the chat proxy expects it.
/// [role] is `'user'` for the person and `'model'` for the assistant.
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}

/// A marketplace listing trimmed to what the assistant needs to
/// recommend real items.
class ChatProduct {
  const ChatProduct({
    required this.name,
    required this.price,
    required this.category,
  });

  final String name;
  final int price;
  final String category;

  Map<String, Object> toJson() =>
      {'name': name, 'price': price, 'category': category};
}

/// A chat failure already phrased for the person waiting on a reply:
/// short, plain, and free of SDK/stack jargon. UI code may show it as is.
class ChatException implements Exception, UserFacingException {
  const ChatException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'ChatException: $message';
}

/// Sends design-chat requests to the app's backend proxy
/// (`POST {chatApiUrl}/api/ai/chat`).
///
/// The Gemini key exists ONLY in the backend's environment — anything in a
/// mobile binary can be extracted from the APK, so this client never holds
/// one. It authenticates with the signed-in user's Firebase ID token and
/// the proxy calls Gemini server-side.
class ChatDatasource {
  ChatDatasource({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  // Model replies take longer than an email enqueue, so a little more
  // headroom than the verification flow's 20s.
  static const Duration _timeout = Duration(seconds: 30);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<String> send({
    required List<ChatTurn> messages,
    String? style,
    String? room,
    List<ChatProduct> products = const [],
  }) async {
    final base = AppConfig.chatApiUrl.trim();
    if (base.isEmpty) {
      throw const ChatException('AI chat is not configured in this build.');
    }
    // Fail fast without a token: an unauthenticated call would only earn
    // a 401 from the proxy.
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ChatException('Please sign in to use the design assistant.');
    }

    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$base/api/ai/chat'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'messages': [for (final m in messages) m.toJson()],
              if (style != null && style.isNotEmpty) 'style': style,
              if (room != null && room.isNotEmpty) 'room': room,
              'products': [for (final p in products) p.toJson()],
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ChatException('The assistant is taking too long. Try again.');
    } on http.ClientException catch (e) {
      debugPrint('[chat] request failed: $e');
      throw const ChatException(
          'Could not reach the assistant. Check your connection.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // The error envelope is a server diagnostic for the logs; the person
      // waiting on a reply gets our own short sentence for the status.
      debugPrint('[chat] rejected HTTP ${resp.statusCode}: ${resp.body}');
      throw ChatException(_messageForStatus(resp.statusCode));
    }

    Object? reply;
    try {
      final decoded = jsonDecode(resp.body);
      reply = decoded is Map ? decoded['reply'] : null;
    } on FormatException catch (e) {
      debugPrint('[chat] unparseable reply body: $e');
    }
    if (reply is! String || reply.trim().isEmpty) {
      throw const ChatException(
          'The design assistant could not reply. Try again.');
    }
    return reply.trim();
  }

  String _messageForStatus(int status) {
    if (status == 401) return 'Please sign in to use the design assistant.';
    if (status == 503) return 'The design assistant is not available yet.';
    if (status == 504) return 'The assistant is taking too long. Try again.';
    // 502 upstream failure, 400 bad request, anything else: the reply
    // simply did not land.
    return 'The design assistant could not reply. Try again.';
  }
}
