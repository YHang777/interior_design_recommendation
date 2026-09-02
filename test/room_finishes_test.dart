// Tests for the Room-mode finish catalog (RoomFinishCatalog) and the
// FinishSelection value class.
//
// Pure Dart — no widgets, no Firebase, no filesystem.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_generator.dart'
    show FloorFinishType, WallFinishType;
import 'package:interior_design_recommendation/features/ar/data/room_finishes.dart';

void main() {
  group('finish color palettes', () {
    test('every floor palette is non-empty', () {
      for (final type in FloorFinishType.values) {
        expect(RoomFinishCatalog.colorsForFloor(type), isNotEmpty,
            reason: 'floor palette of ${type.name} must not be empty');
      }
    });

    test('every wall palette is non-empty', () {
      for (final type in WallFinishType.values) {
        expect(RoomFinishCatalog.colorsForWall(type), isNotEmpty,
            reason: 'wall palette of ${type.name} must not be empty');
      }
    });

    test('every default color is a member of its own palette', () {
      for (final type in FloorFinishType.values) {
        final defaultArgb = RoomFinishCatalog.defaultArgbForFloor(type);
        expect(
          RoomFinishCatalog.colorsForFloor(type)
              .any((c) => c.argb == defaultArgb),
          isTrue,
          reason: 'default floor color of ${type.name} must be in its '
              'palette',
        );
      }
      for (final type in WallFinishType.values) {
        final defaultArgb = RoomFinishCatalog.defaultArgbForWall(type);
        expect(
          RoomFinishCatalog.colorsForWall(type)
              .any((c) => c.argb == defaultArgb),
          isTrue,
          reason: 'default wall color of ${type.name} must be in its palette',
        );
      }
    });

    test('catalog defaults match their type\'s first palette color', () {
      expect(RoomFinishCatalog.defaultFloorColorArgb,
          RoomFinishCatalog.colorsForFloor(FloorFinishType.woodPlanks).first.argb);
      expect(RoomFinishCatalog.defaultWallColorArgb,
          RoomFinishCatalog.colorsForWall(WallFinishType.paint).first.argb);
    });

    test('every colorArgb is a valid fully opaque 0xFFxxxxxx int', () {
      void checkPalette(List<FinishColor> palette, String label) {
        for (final c in palette) {
          expect(c.argb & 0xFF000000, 0xFF000000,
              reason: '$label color "${c.name}" (0x'
                  '${c.argb.toRadixString(16)}) must be fully opaque');
          expect(c.argb & 0xFFFFFF, inInclusiveRange(0, 0xFFFFFF));
        }
      }

      for (final type in FloorFinishType.values) {
        checkPalette(RoomFinishCatalog.colorsForFloor(type),
            '${type.name} floor');
      }
      for (final type in WallFinishType.values) {
        checkPalette(
            RoomFinishCatalog.colorsForWall(type), '${type.name} wall');
      }
    });

    test('floor size options are positive and sorted ascending', () {
      final options = RoomFinishCatalog.floorSizeOptionsM;
      expect(options, isNotEmpty);
      for (var i = 0; i < options.length; i++) {
        expect(options[i], greaterThan(0));
        if (i > 0) {
          expect(options[i], greaterThan(options[i - 1]),
              reason: 'floor size options must be strictly sorted');
        }
      }
      expect(options, contains(RoomFinishCatalog.defaultFloorSizeM));
    });

    test('labels and descriptions are non-empty for every type', () {
      for (final type in FloorFinishType.values) {
        expect(RoomFinishCatalog.floorLabel(type), isNotEmpty);
        expect(RoomFinishCatalog.floorDescription(type), isNotEmpty);
      }
      for (final type in WallFinishType.values) {
        expect(RoomFinishCatalog.wallLabel(type), isNotEmpty);
        expect(RoomFinishCatalog.wallDescription(type), isNotEmpty);
      }
    });

    test('colorName resolves palette members and falls back for strangers',
        () {
      final palette = RoomFinishCatalog.colorsForFloor(
          RoomFinishCatalog.defaultFloorType);
      expect(RoomFinishCatalog.colorName(palette.first.argb, palette),
          palette.first.name);
      expect(RoomFinishCatalog.colorName(0xFF123456, palette), 'Custom');
    });
  });

  group('FinishSelection', () {
    test('defaults match the catalog defaults', () {
      const selection = FinishSelection();
      expect(selection.floorType, RoomFinishCatalog.defaultFloorType);
      expect(
          selection.floorColorArgb, RoomFinishCatalog.defaultFloorColorArgb);
      expect(selection.floorSizeM, RoomFinishCatalog.defaultFloorSizeM);
      expect(selection.wallType, RoomFinishCatalog.defaultWallType);
      expect(selection.wallColorArgb, RoomFinishCatalog.defaultWallColorArgb);
    });

    test('equality compares every field', () {
      const a = FinishSelection();
      const b = FinishSelection();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == const FinishSelection(
          floorColorArgb: 0xFF112233), isFalse);
      expect(a == const FinishSelection(floorSizeM: 2.0), isFalse);
      expect(a == const FinishSelection(floorType: FloorFinishType.cement),
          isFalse);
      expect(a == const FinishSelection(wallType: WallFinishType.brick),
          isFalse);
      expect(a == const FinishSelection(wallColorArgb: 0xFF445566), isFalse);
    });

    test('copyWith overrides only the requested fields', () {
      const base = FinishSelection();
      final allChanged = base.copyWith(
        floorType: FloorFinishType.parquet,
        floorColorArgb: 0xFFC9A368,
        floorSizeM: 4.0,
        wallType: WallFinishType.woodPanels,
        wallColorArgb: 0xFF6B4A32,
      );
      expect(allChanged.floorType, FloorFinishType.parquet);
      expect(allChanged.floorColorArgb, 0xFFC9A368);
      expect(allChanged.floorSizeM, 4.0);
      expect(allChanged.wallType, WallFinishType.woodPanels);
      expect(allChanged.wallColorArgb, 0xFF6B4A32);

      final oneField = base.copyWith(floorSizeM: 2.0);
      expect(oneField.floorSizeM, 2.0);
      expect(oneField.floorType, base.floorType);
      expect(oneField.floorColorArgb, base.floorColorArgb);
      expect(oneField.wallType, base.wallType);
      expect(oneField.wallColorArgb, base.wallColorArgb);

      // copyWith with no arguments is the identity (equal, not identical —
      // copyWith returns a fresh instance by design).
      expect(base.copyWith(), base);
    });
  });
}
