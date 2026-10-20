import 'dart:math';

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

enum ChatDataTopic {
  cart,
  budget,
  plan,
  orders,
  wishlist;

  static ChatDataTopic? tryParse(String? raw) {
    for (final topic in values) {
      if (topic.name == raw) return topic;
    }
    return null;
  }
}

class ChatDataCardRef {
  const ChatDataCardRef({required this.topic});

  final ChatDataTopic topic;

  Map<String, dynamic> toJson() => {'topic': topic.name};

  static ChatDataCardRef? tryFromJson(Map<String, dynamic> json) {
    final topic = ChatDataTopic.tryParse(json['topic']?.toString());
    if (topic == null) return null;
    return ChatDataCardRef(topic: topic);
  }
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.suggestions,
    this.dataCard,
  });

  final String role;
  final String text;
  final DateTime createdAt;

  final List<ChatSuggestionSnapshot>? suggestions;

  final ChatDataCardRef? dataCard;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (suggestions != null && suggestions!.isNotEmpty)
          'suggestions': [for (final s in suggestions!) s.toJson()],
        if (dataCard != null) 'dataCard': dataCard!.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSuggestions = json['suggestions'];
    final rawCard = json['dataCard'];
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
      dataCard: rawCard is Map
          ? ChatDataCardRef.tryFromJson(Map<String, dynamic>.from(rawCard))
          : null,
    );
  }
}

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

  final String title;
  final List<ChatMessage> messages;

  final String? style;
  final String? room;
  final DateTime createdAt;
  final DateTime updatedAt;

  static final Random _rng = Random();

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
