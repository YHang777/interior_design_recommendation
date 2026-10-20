import '../../../../models/chat_session.dart';

class ChatStateMatch {
  const ChatStateMatch({required this.topic, required this.isPure});

  final ChatDataTopic topic;
  final bool isPure;
}

const int kStateQuestionWordLimit = 8;

final List<(ChatDataTopic, RegExp)> _stateRules = [
  (ChatDataTopic.cart, RegExp(r'\bcart\b|\bbasket\b', caseSensitive: false)),
  (
    ChatDataTopic.budget,
    RegExp(r'\bbudget\b|afford|left to spend|over ?budget',
        caseSensitive: false),
  ),
  (
    ChatDataTopic.plan,
    RegExp(r'room plan|floor plan|layout|how big|room size|\bplaced\b',
        caseSensitive: false),
  ),
  (
    ChatDataTopic.orders,
    RegExp(r'\borders?\b|shipped|track my|where.?s my (order|package|parcel)',
        caseSensitive: false),
  ),
  (
    ChatDataTopic.wishlist,
    RegExp(r'wishlist|wish list|\bsaved\b|favourites?|favorites?',
        caseSensitive: false),
  ),
];

ChatStateMatch? matchStateQuestion(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final hits = <ChatDataTopic>{};
  for (final (topic, pattern) in _stateRules) {
    if (pattern.hasMatch(trimmed)) hits.add(topic);
  }
  if (hits.isEmpty) return null;

  final words =
      trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (hits.length == 1 && words <= kStateQuestionWordLimit) {
    return ChatStateMatch(topic: hits.first, isPure: true);
  }

  for (final (topic, _) in _stateRules) {
    if (hits.contains(topic)) {
      return ChatStateMatch(topic: topic, isPure: false);
    }
  }
  return null;
}

String cannedLine(ChatDataTopic topic) => switch (topic) {
      ChatDataTopic.cart => "Here's what's in your cart right now.",
      ChatDataTopic.budget => "Here's where your budget stands right now.",
      ChatDataTopic.plan => "Here's your saved room plan at a glance.",
      ChatDataTopic.orders => "Here's where your recent orders stand.",
      ChatDataTopic.wishlist => "Here's what you've saved.",
    };
