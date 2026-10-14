import 'dart:math';

/// A product the assistant suggested, snapshotted at reply time.
///
/// Not just an id: the card must still render name/price/photo after the
/// listing is edited or deleted. The id is what a tap acts on — the Add
/// handler re-checks the live catalogue before anything enters the cart.
class ChatSuggestionSnapshot {
  const ChatSuggestionSnapshot({
    required this.productId,
    required this.name,
    required this.price,
    required this.image,
    required this.reason,
  });

  final String productId;
  final String name;
  final int price;
  final String image;

  /// The model's one-line why.
  final String reason;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'image': image,
        'reason': reason,
      };

  factory ChatSuggestionSnapshot.fromJson(Map<String, dynamic> json) =>
      ChatSuggestionSnapshot(
        productId: json['productId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        price: (json['price'] as num?)?.toInt() ?? 0,
        image: json['image']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

/// One message in a saved design chat.
///
/// [role] matches the proxy's transcript roles: `'user'` for the person,
/// `'model'` for the assistant — so building a send request is a straight map.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.suggestions,
  });

  final String role;
  final String text;
  final DateTime createdAt;

  /// Product cards attached to an assistant reply; null/empty for the
  /// plain prose bubbles older saved chats hold.
  final List<ChatSuggestionSnapshot>? suggestions;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (suggestions != null && suggestions!.isNotEmpty)
          'suggestions': [for (final s in suggestions!) s.toJson()],
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = json['suggestions'];
    return ChatMessage(
      role: json['role'] == 'user' ? 'user' : 'model',
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      suggestions: rawSuggestions is List
          ? rawSuggestions
              .whereType<Map<String, dynamic>>()
              .map(ChatSuggestionSnapshot.fromJson)
              .where((s) => s.productId.isNotEmpty && s.name.isNotEmpty)
              .toList()
          : null,
    );
  }
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
