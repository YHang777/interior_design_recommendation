import 'dart:math';

/// One message in a saved design chat.
///
/// [role] matches the proxy's transcript roles: `'user'` for the person,
/// `'model'` for the assistant — so building a send request is a straight map.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String role;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] == 'user' ? 'user' : 'model',
        text: json['text']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// A saved design conversation, kept on-device (see `ChatHistoryStore`).
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    this.style,
    this.room,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Shown in the history list; set from the first user message.
  final String title;
  final List<ChatMessage> messages;

  /// Last-tapped quick-shortcut context — enriches the system prompt.
  final String? style;
  final String? room;
  final DateTime createdAt;
  final DateTime updatedAt;

  static final Random _rng = Random();

  /// Same spirit as `MarketplaceRepository._newId` — no uuid dependency.
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${_rng.nextInt(99999)}';

  ChatSession copyWith({
    String? title,
    List<ChatMessage>? messages,
    String? style,
    String? room,
    DateTime? updatedAt,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        style: style ?? this.style,
        room: room ?? this.room,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (style != null) 'style': style,
        if (room != null) 'room': room,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return ChatSession(
      id: json['id']?.toString() ?? newId(),
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString()
          : 'Untitled chat',
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map<String, dynamic>>()
              .map(ChatMessage.fromJson)
              .toList()
          : const [],
      style: json['style']?.toString(),
      room: json['room']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
