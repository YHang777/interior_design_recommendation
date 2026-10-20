import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../models/product.dart';
import '../../../../../models/room_design.dart';
import '../../../../../services/chat_history_store.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/supabase_room_design_datasource.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';

// ─── Datasource ────────────────────────────────────────────────────────────────

final roomDesignDatasourceProvider =
    Provider<SupabaseRoomDesignDatasource>((ref) {
  return SupabaseRoomDesignDatasource();
});

final chatDatasourceProvider = Provider<ChatDatasource>((ref) {
  return ChatDatasource();
});

// ─── Chat history (saved conversations, on-device) ───────────────────────────

final chatHistoryStoreProvider = Provider<ChatHistoryStore>((ref) {
  return ChatHistoryStore();
});

class ChatHistoryState {
  const ChatHistoryState({required this.sessions, this.activeSessionId});

  final List<ChatSession> sessions;
  final String? activeSessionId;

  ChatSession? get activeSession {
    final id = activeSessionId;
    if (id == null) return null;
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class ChatHistoryNotifier extends Notifier<ChatHistoryState> {
  @override
  ChatHistoryState build() {
    final store = ref.watch(chatHistoryStoreProvider);
    Future<void>.microtask(() async {
      try {
        final sessions = await store.load();
        final activeId = await store.loadActiveSessionId();
        if (sessions.isEmpty && activeId == null) return;
        state = ChatHistoryState(
          sessions: _sorted(sessions),
          activeSessionId:
              sessions.any((s) => s.id == activeId) ? activeId : null,
        );
      } catch (e) {
        debugPrint('[chat-history] load failed: $e');
      }
    });
    return const ChatHistoryState(sessions: []);
  }

  void startNewChat() {
    state = ChatHistoryState(
      sessions: state.sessions,
      activeSessionId: null,
    );
    unawaited(_persist());
  }

  void openSession(String id) {
    if (!state.sessions.any((s) => s.id == id)) return;
    state = ChatHistoryState(sessions: state.sessions, activeSessionId: id);
    unawaited(_persist());
  }

  void deleteSession(String id) {
    final next = state.sessions.where((s) => s.id != id).toList();
    state = ChatHistoryState(
      sessions: next,
      activeSessionId: state.activeSessionId == id ? null : state.activeSessionId,
    );
    unawaited(_persist());
  }

  String ensureActiveSession({String? style, String? room}) {
    final existing = state.activeSession;
    if (existing != null) return existing.id;

    final now = DateTime.now();
    final session = ChatSession(
      id: ChatSession.newId(),
      title: 'Untitled chat',
      messages: const [],
      style: style,
      room: room,
      createdAt: now,
      updatedAt: now,
    );
    state = ChatHistoryState(
      sessions: [session, ...state.sessions],
      activeSessionId: session.id,
    );
    unawaited(_persist());
    return session.id;
  }

  void addMessage(
    String sessionId, {
    required String role,
    required String text,
    List<ChatSuggestionSnapshot>? suggestions,
  }) {
    final sessions = [...state.sessions];
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index < 0) return;

    final current = sessions[index];
    final isFirstUserMessage =
        role == 'user' && current.title == 'Untitled chat';
    final updated = current.copyWith(
      messages: [...current.messages, ChatMessage(
        role: role,
        text: text,
        createdAt: DateTime.now(),
        suggestions: suggestions,
      )],
      title: isFirstUserMessage ? _titleFrom(text) : null,
      updatedAt: DateTime.now(),
    );
    sessions
      ..removeAt(index)
      ..insert(0, updated);
    state = ChatHistoryState(sessions: _sorted(sessions), activeSessionId: state.activeSessionId);
    unawaited(_persist());
  }

  void setActiveContext({String? style, String? room}) {
    final sessions = [...state.sessions];
    final id = state.activeSessionId;
    if (id == null) return;
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    sessions[index] = sessions[index].copyWith(style: style, room: room);
    state = ChatHistoryState(sessions: sessions, activeSessionId: id);
    unawaited(_persist());
  }

  static String _titleFrom(String text) {
    final trimmed = text.trim();
    return trimmed.length <= 40 ? trimmed : '${trimmed.substring(0, 40)}…';
  }

  static List<ChatSession> _sorted(List<ChatSession> sessions) =>
      [...sessions]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _persist() async {
    try {
      final s = state;
      await ref.read(chatHistoryStoreProvider).save(
            s.sessions,
            activeSessionId: s.activeSessionId,
          );
    } catch (e) {
      debugPrint('[chat-history] save failed: $e');
    }
  }
}

final chatHistoryProvider =
    NotifierProvider<ChatHistoryNotifier, ChatHistoryState>(
        ChatHistoryNotifier.new);

// ─── Saved Designs (polling from Supabase) ────────────────────────────────────

final savedDesignsProvider = StreamProvider<List<RoomDesign>>((ref) {
  final user = ref.watch(currentUserProvider);
  final userId = user?.uid;
  if (userId == null) return const Stream.empty();

  final ds = ref.watch(roomDesignDatasourceProvider);
  return ds.watchDesigns(userId);
});

// ─── Current design being edited ──────────────────────────────────────────────

final currentDesignProvider =
    StateNotifierProvider<CurrentDesignNotifier, RoomDesign?>((ref) {
  return CurrentDesignNotifier();
});

class CurrentDesignNotifier extends StateNotifier<RoomDesign?> {
  CurrentDesignNotifier() : super(null);

  void loadDesign(RoomDesign design) => state = design;

  void createNew({
    required String id,
    required String name,
    required String roomType,
    required String userId,
  }) {
    final now = DateTime.now();
    state = RoomDesign(
      id: id,
      name: name,
      roomType: roomType,
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
  }

  void updateFurniture(List<FurniturePlacement> furniture) {
    if (state == null) return;
    state = state!.copyWith(furniture: furniture);
  }

  void updateRoomDimensions(double widthCm, double heightCm) {
    if (state == null) return;
    state = state!.copyWith(widthCm: widthCm, heightCm: heightCm);
  }

  void updateName(String name) {
    if (state == null) return;
    state = state!.copyWith(name: name);
  }

  void addFurniture(FurniturePlacement placement) {
    if (state == null) return;
    state = state!.copyWith(furniture: [...state!.furniture, placement]);
  }

  void removeFurniture(String placementId) {
    if (state == null) return;
    state = state!.copyWith(
      furniture:
          state!.furniture.where((f) => f.id != placementId).toList(),
    );
  }

  void clear() => state = null;
}

// ─── Editor state ──────────────────────────────────────────────────────────────

final selectedPlacementIndexProvider = StateProvider<int>((ref) => -1);

final editorRoomWidthProvider = StateProvider<double>((ref) => 400);

final editorRoomHeightProvider = StateProvider<double>((ref) => 500);

// ─── Chat suggestions → room-plan placements ──────────────────────────────────

class ChatPlacementsNotifier extends StateNotifier<List<FurniturePlacement>> {
  ChatPlacementsNotifier() : super(const []);

  void enqueue(FurniturePlacement placement) {
    state = [...state, placement];
  }

  List<FurniturePlacement> drain() {
    final pending = state;
    if (pending.isNotEmpty) state = const [];
    return pending;
  }
}

final pendingChatPlacementsProvider =
    StateNotifierProvider<ChatPlacementsNotifier, List<FurniturePlacement>>(
        (ref) => ChatPlacementsNotifier());

FurniturePlacement chatPlacementForProduct(Product product) {
  final iconName = _chatIconNameFor(product);
  final fallback = _chatCatalogSizes[iconName] ?? (80.0, 60.0);
  var width = fallback.$1;
  var height = fallback.$2;
  final dims = product.dimensions;
  if (dims != null && dims.widthM > 0) {
    width = (dims.widthM * 100).clamp(10.0, 300.0).toDouble();
  }
  if (dims != null && dims.heightM > 0) {
    height = (dims.heightM * 100).clamp(10.0, 300.0).toDouble();
  }
  return FurniturePlacement(
    id: 'chat-${product.id}-${DateTime.now().microsecondsSinceEpoch}',
    name: product.name,
    iconName: iconName,
    x: 20,
    y: 20,
    width: width,
    height: height,
  );
}

const _chatCatalogSizes = <String, (double, double)>{
  'sofa': (180, 90),
  'armchair': (70, 70),
  'coffee_table': (100, 50),
  'dining_table': (140, 100),
  'bed': (200, 160),
  'cabinet': (90, 50),
  'desk': (120, 60),
  'floor_lamp': (25, 25),
  'plant': (30, 30),
  'tv_stand': (140, 45),
  'rug': (160, 120),
  'bookshelf': (90, 30),
};

String _chatIconNameFor(Product product) {
  final source = '${product.category} ${product.name}'.toLowerCase();
  const keys = <String, String>{
    'coffee table': 'coffee_table',
    'dining table': 'dining_table',
    'tv stand': 'tv_stand',
    'armchair': 'armchair',
    'bookshelf': 'bookshelf',
    'wardrobe': 'cabinet',
    'cabinet': 'cabinet',
    'couch': 'sofa',
    'sofa': 'sofa',
    'chair': 'armchair',
    'desk': 'desk',
    'shelf': 'bookshelf',
    'bed': 'bed',
    'rug': 'rug',
    'carpet': 'rug',
    'lamp': 'floor_lamp',
    'light': 'floor_lamp',
    'plant': 'plant',
  };
  for (final entry in keys.entries) {
    if (source.contains(entry.key)) return entry.value;
  }
  return 'unknown';
}
