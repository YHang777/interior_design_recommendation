import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/chat_session.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _msg(String role, String text, [DateTime? at]) => ChatMessage(
      role: role,
      text: text,
      createdAt: at ?? DateTime(2026, 10, 1, 12),
    );

ChatSession _session({
  required String id,
  required DateTime updatedAt,
  List<ChatMessage>? messages,
  String? style,
  String? room,
  String title = 'Chat',
}) =>
    ChatSession(
      id: id,
      title: title,
      messages: messages ?? [_msg('user', 'hello')],
      style: style,
      room: room,
      createdAt: updatedAt.subtract(const Duration(minutes: 5)),
      updatedAt: updatedAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = ChatHistoryStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns an empty list when nothing was saved', () async {
    expect(await store.load(), isEmpty);
    expect(await store.loadActiveSessionId(), isNull);
  });

  test('round-trips sessions with messages, context and dates', () async {
    final sessions = [
      _session(
        id: 'a',
        updatedAt: DateTime(2026, 10, 2, 9, 30),
        title: 'Sofa ideas',
        style: 'Modern',
        room: 'Living Room',
        messages: [
          _msg('user', 'Sofa ideas?'),
          _msg('model', 'Try a sage green three-seater.'),
        ],
      ),
      _session(id: 'b', updatedAt: DateTime(2026, 10, 1, 18), title: 'Bed'),
    ];

    await store.save(sessions, activeSessionId: 'a');
    final loaded = await store.load();

    expect(loaded.map((s) => s.toJson()), sessions.map((s) => s.toJson()));
    expect(loaded.first.style, 'Modern');
    expect(loaded.first.room, 'Living Room');
    expect(loaded.first.messages, hasLength(2));
    expect(loaded.first.messages.last.role, 'model');
    expect(await store.loadActiveSessionId(), 'a');
  });

  test('a corrupted blob yields an empty list instead of throwing',
      () async {
    SharedPreferences.setMockInitialValues({
      ChatHistoryStore.prefsKey: '{not valid json',
    });
    expect(await store.load(), isEmpty);
  });

  test('caps sessions at the 15 newest', () async {
    final sessions = [
      for (var i = 0; i < 20; i++)
        _session(id: 's$i', updatedAt: DateTime(2026, 10, 1).add(Duration(hours: i))),
    ];

    await store.save(sessions);
    final loaded = await store.load();

    expect(loaded, hasLength(ChatHistoryStore.maxSessions));
    expect(loaded.first.id, 's19');
    expect(loaded.last.id, 's5');
  });

  test('caps each session at the 40 newest messages', () async {
    final messages = [
      for (var i = 0; i < 50; i++)
        _msg(i.isEven ? 'user' : 'model', 'msg $i'),
    ];
    await store.save([
      _session(id: 'a', updatedAt: DateTime(2026, 10, 1), messages: messages),
    ]);

    final loaded = await store.load();
    final kept = loaded.first.messages;

    expect(kept, hasLength(ChatHistoryStore.maxMessagesPerSession));
    expect(kept.first.text, 'msg 10');
    expect(kept.last.text, 'msg 49');
  });

  test('truncates over-long message text at save time', () async {
    final long = 'x' * 5000;
    await store.save([
      _session(
        id: 'a',
        updatedAt: DateTime(2026, 10, 1),
        messages: [_msg('user', long)],
      ),
    ]);

    final loaded = await store.load();
    expect(loaded.first.messages.single.text,
        hasLength(ChatHistoryStore.maxMessageChars));
  });

  test('suggestion cards round-trip through save and load', () async {
    const card = ChatSuggestionSnapshot(
      productId: 'sofa-1',
      name: 'Nordic Sofa',
      price: 1299,
      image: 'https://cdn/sofa.jpg',
      reason: 'Matches your grey floor.',
    );
    await store.save([
      _session(
        id: 'a',
        updatedAt: DateTime(2026, 10, 1),
        messages: [
          _msg('user', 'sofa?'),
          ChatMessage(
            role: 'model',
            text: 'This one fits.',
            createdAt: DateTime(2026, 10, 1, 12),
            suggestions: const [card],
          ),
        ],
      ),
    ]);

    final loaded = await store.load();
    final reply = loaded.first.messages.last;
    expect(reply.suggestions, hasLength(1));
    expect(reply.suggestions!.single.productId, 'sofa-1');
    expect(reply.suggestions!.single.name, 'Nordic Sofa');
    expect(reply.suggestions!.single.price, 1299);
    expect(reply.suggestions!.single.reason, 'Matches your grey floor.');

    final legacy = ChatMessage.fromJson(
        const {'role': 'model', 'text': 'plain', 'createdAt': '2026-10-01T12:00:00Z'});
    expect(legacy.suggestions, isNull);
  });

  test('over-long text truncation keeps the suggestion cards', () async {
    final card = ChatSuggestionSnapshot(
      productId: 'lamp-1',
      name: 'Arc Lamp',
      price: 210,
      image: 'https://cdn/lamp.jpg',
      reason: 'Lifts the dark corner.',
    );
    await store.save([
      _session(
        id: 'a',
        updatedAt: DateTime(2026, 10, 1),
        messages: [
          ChatMessage(
            role: 'model',
            text: 'y' * 5000,
            createdAt: DateTime(2026, 10, 1, 12),
            suggestions: [card],
          ),
        ],
      ),
    ]);

    final loaded = await store.load();
    final kept = loaded.first.messages.single;
    expect(kept.text, hasLength(ChatHistoryStore.maxMessageChars));
    expect(kept.suggestions, hasLength(1));
    expect(kept.suggestions!.single.productId, 'lamp-1');
  });

  test('active session id round-trips and clears', () async {
    await store.save(
      [_session(id: 'a', updatedAt: DateTime(2026, 10, 1))],
      activeSessionId: 'a',
    );
    expect(await store.loadActiveSessionId(), 'a');

    await store.save(
      [_session(id: 'a', updatedAt: DateTime(2026, 10, 1))],
      activeSessionId: null,
    );
    expect(await store.loadActiveSessionId(), isNull);
  });
}
