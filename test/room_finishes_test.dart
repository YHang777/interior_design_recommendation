import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart'
    show FloorFinishType, WallFinishType;
import 'package:interior_design_recommendation/features/customer/ar/data/room_finishes.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

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

    test('floor size presets are positive and sorted, Custom sentinel kept',
        () {
      final options = RoomFinishCatalog.floorSizeOptionsM;
      expect(options, isNotEmpty);
      final presets = options.where((o) => o >= 0).toList();
      expect(presets, isNotEmpty);
      for (var i = 0; i < presets.length; i++) {
        expect(presets[i], greaterThan(0));
        if (i > 0) {
          expect(presets[i], greaterThan(presets[i - 1]),
              reason: 'floor size presets must be strictly sorted');
        }
      }
      expect(options, contains(-1.0),
          reason: 'the documented Custom sentinel (-1) must stay in the list');
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

      expect(base.copyWith(), base);
    });
  });

  group('nearest palette matching (material scan)', () {
    test('an exact palette color maps to its own swatch', () {
      final oak = RoomFinishCatalog.colorsForFloor(FloorFinishType.woodPlanks).first;
      expect(RoomFinishCatalog.nearestColorForFloor(FloorFinishType.woodPlanks, oak.argb).argb,
          oak.argb);
      final navy = RoomFinishCatalog.colorsForWall(WallFinishType.paint)
          .firstWhere((c) => c.name == 'Navy');
      expect(
          RoomFinishCatalog.nearestColorForWall(WallFinishType.paint, 0xFF22334D)
              .argb,
          navy.argb);
    });

    test('an off-palette hex snaps to the closest swatch of its type', () {
      // A dark walnut-ish brown, close to Walnut (0xFF6B4A32).
      final snapped = RoomFinishCatalog.nearestColorForFloor(
          FloorFinishType.woodPlanks, 0xFF6E4E36);
      expect(snapped.name, 'Walnut');
    });

    test('a missing hex falls back to the type default', () {
      expect(
          RoomFinishCatalog.nearestColorForFloor(FloorFinishType.cement, null)
              .argb,
          RoomFinishCatalog.defaultArgbForFloor(FloorFinishType.cement));
      expect(
          RoomFinishCatalog.nearestColorForWall(WallFinishType.brick, null)
              .argb,
          RoomFinishCatalog.defaultArgbForWall(WallFinishType.brick));
    });

    test('the snapped color is always a member of the type palette', () {
      const probes = [0xFF000000, 0xFFFFFFFF, 0xFF123456, 0xFFA95F45];
      for (final type in FloorFinishType.values) {
        final palette = RoomFinishCatalog.colorsForFloor(type);
        for (final probe in probes) {
          expect(palette.map((c) => c.argb),
              contains(RoomFinishCatalog.nearestColorForFloor(type, probe).argb));
        }
      }
      for (final type in WallFinishType.values) {
        final palette = RoomFinishCatalog.colorsForWall(type);
        for (final probe in probes) {
          expect(palette.map((c) => c.argb),
              contains(RoomFinishCatalog.nearestColorForWall(type, probe).argb));
        }
      }
    });
  });

  group('finishSelectionFrom', () {
    RoomDesign designWith({
      String? floorType,
      int? floorColor,
      String? wallType,
      int? wallColor,
    }) =>
        RoomDesign(
          id: 'd1',
          name: 'Scan Room',
          roomType: 'living_room',
          floorFinishType: floorType,
          floorFinishColor: floorColor,
          wallFinishType: wallType,
          wallFinishColor: wallColor,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          userId: 'u1',
        );

    test('a null design is the catalog default selection', () {
      expect(finishSelectionFrom(null), const FinishSelection());
    });

    test('stored finishes become the selection', () {
      final s = finishSelectionFrom(designWith(
        floorType: 'parquet',
        floorColor: 0xFFD9B076,
        wallType: 'brick',
        wallColor: 0xFFA8442F,
      ));
      expect(s.floorType, FloorFinishType.parquet);
      expect(s.floorColorArgb, 0xFFD9B076);
      expect(s.wallType, WallFinishType.brick);
      expect(s.wallColorArgb, 0xFFA8442F);
    });

    test('a type without a color uses its palette default', () {
      final s = finishSelectionFrom(designWith(floorType: 'cement'));
      expect(s.floorType, FloorFinishType.cement);
      expect(s.floorColorArgb, RoomFinishCatalog.defaultArgbForFloor(FloorFinishType.cement));
      expect(s.wallType, RoomFinishCatalog.defaultWallType);
    });

    test('unknown or missing names fall back per side', () {
      final s = finishSelectionFrom(designWith(
        floorType: 'marble',
        floorColor: 0xFF123456,
        wallType: 'paint',
      ));
      expect(s.floorType, RoomFinishCatalog.defaultFloorType);
      expect(s.floorColorArgb, RoomFinishCatalog.defaultFloorColorArgb);
      expect(s.wallType, WallFinishType.paint);
    });
  });
}
