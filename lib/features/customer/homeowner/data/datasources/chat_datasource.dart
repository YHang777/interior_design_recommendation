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
///
/// [id] makes a recommendation tappable (the reply can name products the
/// app then renders as cards); the photo fields carry the server's
/// upload-time analysis so the model sees what the photo shows, not just
/// what the seller wrote.
class ChatProduct {
  const ChatProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.designStyle,
    this.description,
    this.photoLabels = const [],
    this.photoSummary,
    this.photoMismatch = false,
  });

  final String id;
  final String name;
  final int price;
  final String category;
  final String? designStyle;

  /// Seller-written copy — the unverified claim.
  final String? description;

  /// What the server's photo analysis saw — the trusted line.
  final List<String> photoLabels;
  final String? photoSummary;
  final bool photoMismatch;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'category': category,
        if (designStyle != null && designStyle!.isNotEmpty)
          'designStyle': designStyle,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (photoLabels.isNotEmpty) 'photoLabels': photoLabels,
        if (photoSummary != null && photoSummary!.isNotEmpty)
          'photoSummary': photoSummary,
        if (photoMismatch) 'photoMismatch': true,
      };
}

/// One product the assistant picked, as referenced by id in a reply.
class ChatSuggestionRef {
  const ChatSuggestionRef({required this.productId, required this.reason});

  final String productId;
  final String reason;
}

/// One assistant answer: prose for the bubble plus the catalogue items it
/// points at (already validated server-side against the request).
class ChatReply {
  const ChatReply({required this.reply, this.suggestions = const []});

  final String reply;
  final List<ChatSuggestionRef> suggestions;
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

  Future<ChatReply> send({
    required List<ChatTurn> messages,
    String? style,
    String? room,
    List<ChatProduct> products = const [],
  }) async {
    final base = AppConfig.chatApiUrl.trim();
    if (base.isEmpty) {
      // No proxy in this build — reply locally so the chat is never a
      // dead end. Small delay so the typing indicator has a beat to show.
      await Future.delayed(const Duration(milliseconds: 600));
      return ChatReply(reply: _localReply(style: style, room: room));
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

    Map<String, dynamic>? decoded;
    try {
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) decoded = body;
    } on FormatException catch (e) {
      debugPrint('[chat] unparseable reply body: $e');
    }
    final reply = decoded?['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const ChatException(
          'The design assistant could not reply. Try again.');
    }
    // Suggestions are optional garnish: a proxy without them (or a junk
    // entry) must never fail a reply that has perfectly good prose.
    final rawSuggestions = decoded?['suggestions'];
    final suggestions = <ChatSuggestionRef>[];
    if (rawSuggestions is List) {
      for (final item in rawSuggestions) {
        if (item is! Map) continue;
        final id = item['productId'];
        if (id is! String || id.trim().isEmpty) continue;
        final reason = item['reason'];
        suggestions.add(ChatSuggestionRef(
          productId: id.trim(),
          reason: reason is String ? reason.trim() : '',
        ));
      }
    }
    return ChatReply(reply: reply.trim(), suggestions: suggestions);
  }

  /// Canned reply for builds without a configured proxy. Short, plain
  /// sentences (house rule), adapting to whatever context the chips gave.
  static String _localReply({String? style, String? room}) {
    if (style != null && room != null) {
      return 'Here is a $style recommendation for your $room: Try a '
          'neutral color palette with accent furniture pieces. Would you '
          'like specific product suggestions?';
    }
    if (style != null || room != null) {
      final what = style ?? room;
      return 'Here are some $what ideas: A neutral base with one or two '
          'accent pieces keeps the space flexible. Want suggestions for '
          'specific furniture?';
    }
    return 'I can help with furniture picks, color palettes, and layout '
        'ideas for any room. Tell me a style or a room to start with.';
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
