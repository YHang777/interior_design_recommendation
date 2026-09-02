// Tests for the pure-Dart procedural GLB generator + GLB bounds parser.
//
// AR cannot run on the emulator, so these tests prove the geometry pipeline:
// every generated model is round-tripped through the GLB parser and its
// bounding box is asserted against the requested real-world dimensions.
//
// Pure Dart tests (no widgets); fast and deterministic.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_generator.dart';

/// Parses [bytes] and also verifies the GLB container header.
GlbBounds parseGlb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(0, Endian.little), 0x46546C67,
      reason: 'GLB magic must be "glTF"');
  expect(data.getUint32(4, Endian.little), 2, reason: 'GLB version 2');
  expect(data.getUint32(8, Endian.little), bytes.length,
      reason: 'declared length must match file length');
  return GlbBounds.fromGlbBytes(bytes);
}

void expectNear(double actual, double expected, double tolerance,
    [String? reason]) {
  expect((actual - expected).abs(), lessThanOrEqualTo(tolerance),
      reason: reason ?? 'expected ≈ $expected, got $actual');
}

void main() {
  group('generated furniture GLBs', () {
    test('header: magic, version, length (table)', () {
      final bytes = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 1.0,
        heightM: 0.75,
        depthM: 0.6,
      );
      expect(bytes, isNotEmpty);
      parseGlb(bytes); // asserts magic/version/length internally
    });

    test('table 1.0 × 0.75 × 0.6 m parses to matching extents', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 1.0,
        heightM: 0.75,
        depthM: 0.6,
      ));
      expectNear(bounds.widthM, 1.0, 0.05, 'table width');
      expectNear(bounds.heightM, 0.75, 0.05, 'table height');
      expectNear(bounds.depthM, 0.6, 0.05, 'table depth');
    });

    test('sofa keeps its requested width and has positive extents', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Three Seater Sofa',
        widthM: 2.2,
        heightM: 0.85,
        depthM: 0.9,
      ));
      expect(bounds.widthM, greaterThan(0));
      expect(bounds.heightM, greaterThan(0));
      expect(bounds.depthM, greaterThan(0));
      expectNear(bounds.widthM, 2.2, 0.05, 'sofa width');
    });

    test('chair keeps its requested width', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Wooden Chair',
        widthM: 0.6,
        heightM: 0.9,
        depthM: 0.6,
      ));
      expect(bounds.heightM, greaterThan(0));
      expectNear(bounds.widthM, 0.6, 0.05, 'chair width');
    });

    test('armchair includes armrests but still spans its width', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Leather Armchair',
        widthM: 0.9,
        heightM: 1.0,
        depthM: 0.85,
      ));
      expectNear(bounds.widthM, 0.9, 0.05, 'armchair width');
      expect(bounds.heightM, greaterThan(0.6));
    });

    test('lamp parses with width ≈ requested shade width', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Lighting',
        name: 'Floor Lamp',
        widthM: 0.45,
        heightM: 1.5,
        depthM: 0.45,
      ));
      expect(bounds.heightM, greaterThan(1.0));
      expectNear(bounds.widthM, 0.45, 0.05, 'lamp width');
    });

    test('default shape (no keyword) is an exact cuboid', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Ottoman',
        widthM: 0.8,
        heightM: 0.4,
        depthM: 0.6,
      ));
      expectNear(bounds.widthM, 0.8, 0.001, 'cuboid width');
      expectNear(bounds.heightM, 0.4, 0.001, 'cuboid height');
      expectNear(bounds.depthM, 0.6, 0.001, 'cuboid depth');
    });

    test('bed parses and matches width', () {
      final bounds = parseGlb(generateFurnitureGlb(
        category: 'Furniture',
        name: 'Double Bed',
        widthM: 1.8,
        heightM: 1.0,
        depthM: 2.0,
      ));
      expectNear(bounds.widthM, 1.8, 0.05, 'bed width');
      expectNear(bounds.depthM, 2.0, 0.05, 'bed depth');
      expect(bounds.heightM, greaterThan(0.5));
    });

    test('output is byte-identical for the same inputs (deterministic)', () {
      Uint8List gen() => generateFurnitureGlb(
            category: 'Furniture',
            name: 'Dining Table',
            widthM: 1.0,
            heightM: 0.75,
            depthM: 0.6,
            seedOrColor: 42,
          );
      expect(gen(), gen());
      // A different seed produces different bytes.
      final other = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 1.0,
        heightM: 0.75,
        depthM: 0.6,
        seedOrColor: 7,
      );
      expect(other, isNot(equals(gen())));
    });

    test('rejects non-positive dimensions', () {
      expect(
        () => generateFurnitureGlb(
            category: 'Furniture',
            name: 'Table',
            widthM: 0,
            heightM: 0.75,
            depthM: 0.6),
        throwsArgumentError,
      );
    });
  });

  group('floor / wall finish GLBs', () {
    test('wood plank floor parses to ≈ 3 × 3 m', () {
      final bounds = parseGlb(generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B)));
      expectNear(bounds.widthM, 3.0, 0.05, 'plank floor width');
      expectNear(bounds.depthM, 3.0, 0.05, 'plank floor depth');
      expect(bounds.heightM, greaterThan(0));
      expect(bounds.heightM, lessThan(0.05), reason: 'floor is thin');
    });

    test('ceramic tile floor parses to ≈ 3 × 3 m', () {
      final bounds = parseGlb(generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.ceramicTiles, colorArgb: 0xFFD8D2C0)));
      expectNear(bounds.widthM, 3.0, 0.05, 'tile floor width');
      expectNear(bounds.depthM, 3.0, 0.05, 'tile floor depth');
    });

    test('custom-size cement floor honors sizeM', () {
      final bounds = parseGlb(generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.cement,
              colorArgb: 0xFFB9B9B4,
              sizeM: 4.0)));
      expectNear(bounds.widthM, 4.0, 0.05, 'cement floor width');
      expectNear(bounds.depthM, 4.0, 0.05, 'cement floor depth');
    });

    test('brick wall parses to ≈ 2.4 wide × 2.7 high', () {
      final bounds = parseGlb(generateWallGlb(
          finish: const WallFinish(
              type: WallFinishType.brick, colorArgb: 0xFFA65B3C)));
      expectNear(bounds.widthM, 2.4, 0.05, 'wall width');
      expectNear(bounds.heightM, 2.7, 0.05, 'wall height');
      expect(bounds.depthM, greaterThan(0.03));
      expect(bounds.depthM, lessThan(0.1), reason: 'wall panel is thin');
    });

    test('wood panel wall parses to ≈ 2.4 wide × 2.7 high', () {
      final bounds = parseGlb(generateWallGlb(
          finish: const WallFinish(
              type: WallFinishType.woodPanels, colorArgb: 0xFF8A6A4F)));
      expectNear(bounds.widthM, 2.4, 0.05, 'wall width');
      expectNear(bounds.heightM, 2.7, 0.05, 'wall height');
    });

    test('paint wall parses to ≈ 2.4 wide × 2.7 high', () {
      final bounds = parseGlb(generateWallGlb(
          finish: const WallFinish(
              type: WallFinishType.paint, colorArgb: 0xFFE9E4DA)));
      expectNear(bounds.widthM, 2.4, 0.05, 'wall width');
      expectNear(bounds.heightM, 2.7, 0.05, 'wall height');
    });
  });

  group('real bundled GLB (regression)', () {
    test('assets/models/three_seater_sofa.glb parses with positive extents',
        () {
      final file = File('assets/models/three_seater_sofa.glb');
      expect(file.existsSync(), isTrue,
          reason: 'bundled model must live in assets/models/');
      final bytes = file.readAsBytesSync();
      final bounds = parseGlb(bytes);
      expect(bounds.widthM, greaterThan(0));
      expect(bounds.heightM, greaterThan(0));
      expect(bounds.depthM, greaterThan(0));
    });

    test('parser throws descriptive errors on malformed input', () {
      expect(() => GlbBounds.fromGlbBytes(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<GlbParseException>()));
      final notGlb = Uint8List.fromList(List.filled(64, 7));
      expect(() => GlbBounds.fromGlbBytes(notGlb),
          throwsA(isA<GlbParseException>()));
    });

    test('parser falls back to scanning the buffer when POSITION min/max '
        'are missing', () {
      // Take a real generated GLB and surgically strip the accessor
      // min/max arrays from its JSON chunk (re-padding to 4-byte
      // alignment), then make sure GlbBounds still computes the same box
      // by scanning the raw vertex floats.
      final original = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 1.0,
        heightM: 0.75,
        depthM: 0.6,
      );
      final headerLen = 12 + 8;
      final jsonLen =
          ByteData.sublistView(original).getUint32(12, Endian.little);
      final jsonBytes =
          original.sublist(headerLen, headerLen + jsonLen);
      final trimmed = String.fromCharCodes(jsonBytes)
          .replaceAll(RegExp(r',\s*"min"\s*:\s*\[[^\]]*\]'), '')
          .replaceAll(RegExp(r',\s*"max"\s*:\s*\[[^\]]*\]'), '');
      expect(trimmed, isNot(contains('"min"')));
      final jsonOut = Uint8List.fromList(trimmed.codeUnits);
      final jsonPadded = (jsonOut.length + 3) & ~3;

      final rest = original.sublist(headerLen + jsonLen);
      final builder = BytesBuilder(copy: false);
      final head = ByteData(12);
      head.setUint32(0, 0x46546C67, Endian.little);
      head.setUint32(4, 2, Endian.little);
      head.setUint32(8, 12 + 8 + jsonPadded + rest.length, Endian.little);
      builder.add(head.buffer.asUint8List());
      final chunk = ByteData(8);
      chunk.setUint32(0, jsonPadded, Endian.little);
      chunk.setUint32(4, 0x4E4F534A, Endian.little);
      builder.add(chunk.buffer.asUint8List());
      builder.add(jsonOut);
      // GLB JSON padding must be spaces (0x20), not NULs.
      builder.add(Uint8List(jsonPadded - jsonOut.length)
        ..fillRange(0, jsonPadded - jsonOut.length, 0x20));
      builder.add(rest);

      final bounds = GlbBounds.fromGlbBytes(builder.toBytes());
      expectNear(bounds.widthM, 1.0, 0.05, 'scanned width');
      expectNear(bounds.heightM, 0.75, 0.05, 'scanned height');
      expectNear(bounds.depthM, 0.6, 0.05, 'scanned depth');
    });
  });
}
