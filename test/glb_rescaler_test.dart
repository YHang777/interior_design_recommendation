// Tests for the GLB rescaler: downloaded AI models (arbitrary baked scale,
// float-unsafe for exact dims) must be re-baked to exact W×H×D meters and
// grounded at y = 0 so AR placement can use a uniform scale of 1.0.
//
// Pure Dart tests (no widgets / platform channels) — fast and deterministic.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_rescaler.dart';

/// Parses [bytes] and verifies the GLB container header.
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

/// Decodes the GLB JSON chunk and returns it.
Map<String, dynamic> jsonChunkOf(Uint8List bytes) {
  final headerLen = 12 + 8;
  final jsonLen = ByteData.sublistView(bytes).getUint32(12, Endian.little);
  final jsonBytes = bytes.sublist(headerLen, headerLen + jsonLen);
  return jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
}

void main() {
  group('rescaleGlbToDimensions', () {
    test('table 0.8 × 0.7 × 0.5 m → 1.0 × 1.5 × 0.6 m extents match', () {
      final source = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 0.8,
        heightM: 0.7,
        depthM: 0.5,
      );
      final rescaled = rescaleGlbToDimensions(
        source,
        targetWidthM: 1.0,
        targetHeightM: 1.5,
        targetDepthM: 0.6,
      );
      final bounds = parseGlb(rescaled);
      expectNear(bounds.widthM, 1.0, 0.01, 'width');
      expectNear(bounds.heightM, 1.5, 0.01, 'height');
      expectNear(bounds.depthM, 0.6, 0.01, 'depth');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded minY ≈ 0');
      expectNear(bounds.minX, -0.5, 0.01, 'minX = -targetW/2');
      expectNear(bounds.maxX, 0.5, 0.01, 'maxX = +targetW/2');
    });

    test('accessor min/max arrays are rewritten to the scaled extents', () {
      final source = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 0.8,
        heightM: 0.7,
        depthM: 0.5,
      );
      final before = jsonChunkOf(source);
      final accessor0Before = (before['accessors'] as List<dynamic>)[0]
          as Map<String, dynamic>;
      // Source extents were authored exactly.
      expectNear(
          (accessor0Before['min'] as List)[0] as double, -0.4, 1e-6, 'src minX');
      expectNear(
          (accessor0Before['max'] as List)[1] as double, 0.7, 1e-6, 'src maxY');

      final rescaled = rescaleGlbToDimensions(
        source,
        targetWidthM: 1.0,
        targetHeightM: 1.5,
        targetDepthM: 0.6,
      );
      final json = jsonChunkOf(rescaled);
      final accessors = json['accessors'] as List<dynamic>;
      expect(accessors.length, before['accessors'].length,
          reason: 'accessor count unchanged');
      final pos = accessors[0] as Map<String, dynamic>;
      final min = (pos['min'] as List).cast<num>().toList();
      final max = (pos['max'] as List).cast<num>().toList();
      expectNear(min[0].toDouble(), -0.5, 0.01, 'min[0] (X)');
      expectNear(min[1].toDouble(), 0.0, 1e-6, 'min[1] (Y grounded)');
      expectNear(min[2].toDouble(), -0.3, 0.01, 'min[2] (Z)');
      expectNear(max[0].toDouble(), 0.5, 0.01, 'max[0] (X)');
      expectNear(max[1].toDouble(), 1.5, 0.01, 'max[1] (Y)');
      expectNear(max[2].toDouble(), 0.3, 0.01, 'max[2] (Z)');
    });

    test('non-zero source minY is grounded to y = 0 (floor slab)', () {
      // Generated floor slab: top at y = 0, bottom at y = −0.01.
      final floor = generateFloorGlb(
          finish: const FloorFinish(
              type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B));
      final src = parseGlb(floor);
      expectNear(src.minY, -0.01, 1e-6, 'floor slab starts below 0');

      // Stretch it to a 4 × 0.2 × 4 slab — grounding must lift the bottom
      // face to y = 0 while keeping the full requested thickness.
      final rescaled = rescaleGlbToDimensions(
        floor,
        targetWidthM: 4.0,
        targetHeightM: 0.2,
        targetDepthM: 4.0,
      );
      final bounds = parseGlb(rescaled);
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded minY ≈ 0');
      expectNear(bounds.heightM, 0.2, 0.01, 'height preserved after ground');
      expectNear(bounds.widthM, 4.0, 0.01, 'width');
      expectNear(bounds.depthM, 4.0, 0.01, 'depth');
      // X/Z kept the model's own centering: −2 … +2.
      expectNear(bounds.minX, -2.0, 0.01, 'minX centered');
      expectNear(bounds.maxX, 2.0, 0.01, 'maxX centered');
    });

    test('rescale to square targets keeps byte determinism', () {
      final source = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Sofa',
        widthM: 2.2,
        heightM: 0.85,
        depthM: 0.9,
      );
      Uint8List run() => rescaleGlbToDimensions(
            source,
            targetWidthM: 1.8,
            targetHeightM: 1.1,
            targetDepthM: 0.95,
          );
      expect(run(), run(), reason: 'same input → byte-identical output');
    });

    test('rejects non-positive target dimensions', () {
      final bytes = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Dining Table',
        widthM: 1.0,
        heightM: 0.75,
        depthM: 0.6,
      );
      expect(
        () => rescaleGlbToDimensions(bytes,
            targetWidthM: 0, targetHeightM: 1, targetDepthM: 1),
        throwsArgumentError,
      );
    });

    test('rejects malformed input with a descriptive exception', () {
      expect(
        () => rescaleGlbToDimensions(Uint8List.fromList([1, 2, 3]),
            targetWidthM: 1, targetHeightM: 1, targetDepthM: 1),
        throwsA(isA<GlbParseException>()),
      );
    });

    test('rescaled model still parses identically on a second pass '
        '(round trip through GlbBounds)', () {
      final source = generateFurnitureGlb(
        category: 'Furniture',
        name: 'Bed',
        widthM: 1.6,
        heightM: 1.2,
        depthM: 2.0,
      );
      final once = rescaleGlbToDimensions(
        source,
        targetWidthM: 1.9,
        targetHeightM: 0.6,
        targetDepthM: 2.1,
      );
      // A second rescale of an already-ground model must behave (idempotent
      // grounding — minY is already 0, so it must NOT shift Y up).
      final twice = rescaleGlbToDimensions(
        once,
        targetWidthM: 1.9,
        targetHeightM: 0.6,
        targetDepthM: 2.1,
      );
      expectNear(parseGlb(twice).minY, 0.0, 1e-6,
          're-grounding keeps minY at 0');
      expectNear(parseGlb(twice).heightM, 0.6, 0.01, 'height');
      expectNear(parseGlb(twice).widthM, 1.9, 0.01, 'width');
      expectNear(parseGlb(twice).depthM, 2.1, 0.01, 'depth');
    });
  });
}
