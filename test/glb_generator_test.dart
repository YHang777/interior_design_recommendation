// Tests for the parts of the procedural GLB generator that are still alive:
// room-scanner floor/wall finish overlays, the resolveShapeFamily keyword
// classifier (shared with the supplier product form's dimension autofill),
// and the GLB bounds parser (including a regression guard on a real bundled
// asset).
//
// The FURNITURE generator was deleted with the procedural product-model
// path: a product's 3D model is a Tripo AI model rescaled to the seller's
// dimensions (see model_glb_resolver_test.dart / glb_rescaler_test.dart).
//
// Pure Dart tests (no widgets); fast and deterministic.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';

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
  group('floor / wall finish GLBs (room scanner overlays)', () {
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

    test('parquet floor parses to ≈ 3 × 3 m', () {
      final bounds = parseGlb(generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.parquet, colorArgb: 0xFFC09A6B)));
      expectNear(bounds.widthM, 3.0, 0.05, 'parquet floor width');
      expectNear(bounds.depthM, 3.0, 0.05, 'parquet floor depth');
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

    test('same finish → byte-identical output (deterministic)', () {
      Uint8List gen() => generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B));
      expect(gen(), gen());
    });

    test('non-positive sizeM is rejected', () {
      expect(
        () => generateFloorGlb(
            finish: const FloorFinish(
                type: FloorFinishType.cement,
                colorArgb: 0xFFB9B9B4,
                sizeM: 0)),
        throwsArgumentError,
      );
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

    test('custom wall panel size is honored', () {
      final bounds = parseGlb(
          generateWallGlb(
              finish: const WallFinish(
                  type: WallFinishType.paint, colorArgb: 0xFFE9E4DA),
              widthM: 3.0,
              heightM: 2.5));
      expectNear(bounds.widthM, 3.0, 0.05, 'custom wall width');
      expectNear(bounds.heightM, 2.5, 0.05, 'custom wall height');
    });

    test('non-positive panel size is rejected', () {
      expect(
        () => generateWallGlb(
            finish: const WallFinish(
                type: WallFinishType.paint, colorArgb: 0xFFE9E4DA),
            widthM: 0,
            heightM: 2.7),
        throwsArgumentError,
      );
    });
  });

  group('resolveShapeFamily (supplier form autofill — not an AR path)', () {
    test('lighting category maps everything to lamp', () {
      expect(
        resolveShapeFamily(category: 'Lighting', name: 'Desk Fan'),
        'lamp',
      );
      expect(
        resolveShapeFamily(category: 'lighting', name: 'Table Lamp'),
        'lamp',
      );
    });

    test('decor category uses name keywords', () {
      expect(
        resolveShapeFamily(category: 'Decor', name: 'Wool Rug'),
        'rug',
      );
      expect(
        resolveShapeFamily(category: 'Decor', name: 'Ceramic Vase'),
        'vase',
      );
      expect(
        resolveShapeFamily(category: 'Decor', name: 'Picture Frame'),
        'mirror',
      );
      // Unknown decor names stay a real object ('default'), never a mat.
      expect(
        resolveShapeFamily(category: 'Decor', name: 'Abstract Statue'),
        'default',
      );
    });

    test('name keywords map onto shape families', () {
      expect(resolveShapeFamily(category: 'Furniture', name: 'Oak Sofa'),
          'sofa');
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Lounge Armchair'),
          'armchair');
      expect(resolveShapeFamily(category: 'Furniture', name: 'Wooden Chair'),
          'chair');
      expect(resolveShapeFamily(category: 'Furniture', name: 'Double Bed'),
          'bed');
      expect(resolveShapeFamily(category: 'Furniture', name: 'Dining Table'),
          'table');
      expect(resolveShapeFamily(category: 'Furniture', name: 'Bookcase'),
          'cabinet');
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Floor Lamp'),
          'lamp');
    });

    test('specific keywords win over generic ones', () {
      // bedside/nightstand before 'bed'.
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Bedside Table'),
          'cabinet');
      // armchair before 'chair'.
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Recliner Armchair'),
          'armchair');
    });

    test('unknown names fall through to default', () {
      expect(
        resolveShapeFamily(category: 'Furniture', name: 'Mystery Object'),
        'default',
      );
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
      final original = generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B));
      final expected = GlbBounds.fromGlbBytes(original);

      const headerLen = 12 + 8;
      final jsonLen =
          ByteData.sublistView(original).getUint32(12, Endian.little);
      final jsonBytes = original.sublist(headerLen, headerLen + jsonLen);
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
      head.setUint32(
          8, 12 + 8 + jsonPadded + rest.length, Endian.little);
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
      expectNear(bounds.widthM, expected.widthM, 1e-5, 'scanned width');
      expectNear(bounds.heightM, expected.heightM, 1e-5, 'scanned height');
      expectNear(bounds.depthM, expected.depthM, 1e-5, 'scanned depth');
      expectNear(bounds.minY, expected.minY, 1e-5, 'scanned minY');
    });
  });
}
