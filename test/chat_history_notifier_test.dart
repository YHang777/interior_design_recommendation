import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/models/chat_session.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';

class _FakeChatHistoryStore implements ChatHistoryStore {
  _FakeChatHistoryStore({this.sessions = const [], this.activeId});

  List<ChatSession> sessions;
  String? activeId;
  int saveCalls = 0;

  @override
  Future<List<ChatSession>> load() async => sessions;

  @override
  Future<String?> loadActiveSessionId() async => activeId;

  @override
  Future<void> save(
    List<ChatSession> sessions, {
    String? activeSessionId,
  }) async {
    saveCalls++;
    this.sessions = List.of(sessions);
    activeId = activeSessionId;
  }
}

ChatSession _session(String id, {DateTime? updatedAt, String style = ''}) {
  final at = updatedAt ?? DateTime(2026, 10, 1, 9);
  return ChatSession(
    id: id,
    title: 'Chat $id',
    messages: const [],
    style: style.isEmpty ? null : style,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  late _FakeChatHistoryStore store;
  late ProviderContainer container;

  setUp(() {
    store = _FakeChatHistoryStore();
    container = ProviderContainer(
      overrides: [chatHistoryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
  });

  ChatHistoryNotifier notifier() =>
      container.read(chatHistoryProvider.notifier);
  ChatHistoryState state() => container.read(chatHistoryProvider);

  test('hydrates sessions and the active id from the store', () async {
    final older = _session('b', updatedAt: DateTime(2026, 10, 1));
    final newer = _session('a', updatedAt: DateTime(2026, 10, 2));
    store = _FakeChatHistoryStore(sessions: [older, newer], activeId: 'a');
    container = ProviderContainer(
      overrides: [chatHistoryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(chatHistoryProvider);
    await pumpEventQueue();

    expect(state().sessions.map((s) => s.id), ['a', 'b']);
    expect(state().activeSessionId, 'a');
    expect(state().activeSession?.id, 'a');
  });

  test('an active id pointing at a missing session is discarded', () async {
    store = _FakeChatHistoryStore(
        sessions: [_session('a')], activeId: 'ghost');
    container = ProviderContainer(
      overrides: [chatHistoryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(chatHistoryProvider);
    await pumpEventQueue();

    expect(state().activeSessionId, isNull);
  });

  test('ensureActiveSession creates once and reuses the open session',
      () async {
    final id = notifier()
        .ensureActiveSession(style: 'Modern', room: 'Living Room');
    final id2 = notifier().ensureActiveSession();

    expect(id2, id);
    final session = state().activeSession!;
    expect(session.id, id);
    expect(session.messages, isEmpty);
    expect(session.style, 'Modern');
    expect(session.room, 'Living Room');
    expect(store.saveCalls, greaterThanOrEqualTo(1));
  });

  test('first user message titles the session, later ones just append',
      () async {
    final id = notifier().ensureActiveSession();
    notifier().addMessage(id, role: 'user', text: 'Sofa ideas for a modern flat');
    notifier().addMessage(id, role: 'model', text: 'Try sage green.');

    final session = state().activeSession!;
    expect(session.title, 'Sofa ideas for a modern flat');
    expect(session.messages, hasLength(2));
    expect(session.messages.last.role, 'model');
    expect(state().activeSession!.title, 'Sofa ideas for a modern flat');
  });

  test('long first messages are truncated for the title', () {
    final id = notifier().ensureActiveSession();
    final long = 'What is the best sofa color for a modern living room?';
    notifier().addMessage(id, role: 'user', text: long);

    final title = state().activeSession!.title;
    expect(title, hasLength(41));
    expect(title, endsWith('…'));
    expect(state().activeSession!.messages.single.text, long);
  });

  test('adding to a deleted session is a no-op', () async {
    final id = notifier().ensureActiveSession();
    notifier().deleteSession(id);
    final savesAfterDelete = store.saveCalls;

    notifier().addMessage(id, role: 'model', text: 'late reply');

    expect(state().sessions, isEmpty);
    expect(store.saveCalls, savesAfterDelete);
  });

  test('addMessage moves its session to the top of the list', () async {
    final a = notifier().ensureActiveSession();
    notifier().startNewChat();
    final b = notifier().ensureActiveSession();
    expect(state().sessions.first.id, b);

    notifier().addMessage(a, role: 'user', text: 'back to chat a');
    expect(state().sessions.first.id, a);
    expect(state().activeSessionId, b);
  });

  test('deleteSession removes it and clears the active id when needed',
      () async {
    final id = notifier().ensureActiveSession();
    notifier().deleteSession(id);

    expect(state().sessions, isEmpty);
    expect(state().activeSessionId, isNull);
    expect(store.activeId, isNull);
    expect(store.sessions, isEmpty);
  });

  test('startNewChat and openSession switch the active chat', () async {
    final id = notifier().ensureActiveSession();
    notifier().startNewChat();
    expect(state().activeSessionId, isNull);

    notifier().openSession(id);
    expect(state().activeSessionId, id);

    notifier().openSession('missing');
    expect(state().activeSessionId, id);
  });

  test('setActiveContext writes style/room onto the open chat', () async {
    final id = notifier().ensureActiveSession();
    notifier().setActiveContext(style: 'Minimalist', room: 'Bedroom');

    final session = state().activeSession!;
    expect(session.id, id);
    expect(session.style, 'Minimalist');
    expect(session.room, 'Bedroom');

    notifier().startNewChat();
    notifier().setActiveContext(style: 'Classic');
    expect(state().sessions, hasLength(1));
  });
}
