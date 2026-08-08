import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../models/room_design.dart';
import '../../data/datasources/room_design_datasource.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

// ─── Datasource ────────────────────────────────────────────────────────────────

final roomDesignDatasourceProvider = Provider<RoomDesignDatasource>((ref) {
  return RoomDesignDatasource();
});

// ─── Saved Designs (real-time from Firestore) ─────────────────────────────────

final savedDesignsProvider = StreamProvider<List<RoomDesign>>((ref) {
  final user = ref.watch(currentUserProvider);
  final userId = user?.uid;
  if (userId == null) return const Stream.empty();

  final ds = ref.watch(roomDesignDatasourceProvider);
  return ds.watchDesigns(userId).map((snapshot) {
    final designs = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['id'] = doc.id;
      return RoomDesign.fromJson(data);
    }).toList();
    // Sort client-side by updatedAt descending
    designs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return designs;
  });
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
