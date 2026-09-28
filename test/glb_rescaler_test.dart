// Tests for the GLB rescaler: downloaded AI models (arbitrary baked scale,
// e.g. a 0.70 m mesh for a product the seller declared as 0.50 m) must be
// re-baked to the SELLER's declared size and grounded at y = 0 so AR
// placement can use a uniform scale of 1.0.
//
// Two layers:
//  * rescaleGlbToDimensions — the per-axis engine (exact W×H×D targets);
//  * rescaleGlbToSellerSize — the decision layer the pipeline calls:
//    all three dims → per-axis; some dims → uniform (height preferred);
//    no dims → MissingDimensionsException (never a guessed size).
//
// Pure Dart tests (no widgets / platform channels) — fast and deterministic.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_rescaler.dart';
import 'package:interior_design_recommendation/models/product.dart';

/// A deterministic mesh from the (still-supported) finish generator: a wall
/// panel 2.4 × 2.7 × 0.05 m before any rescale.
Uint8List wallSource() => generateWallGlb(
    finish: const WallFinish(
        type: WallFinishType.paint, colorArgb: 0xFFE9E4DA));

/// A mesh at a known arbitrary scale: 0.6 × 0.7 × 0.4 m — the 0.70 m
/// height of the spec's "seller 0.50 m vs Tripo 0.70 m" example.
Uint8List meshAt070Height() => rescaleGlbToDimensions(
      wallSource(),
      targetWidthM: 0.6,
      targetHeightM: 0.7,
      targetDepthM: 0.4,
    );

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

/// The POSITION accessor whose min/max match [bounds] (there may be several
/// accessors — normals/UVs — so we locate the position one by value).
Map<String, dynamic> positionAccessor(Map<String, dynamic> json, GlbBounds b) {
  final accessors = json['accessors'] as List<dynamic>;
  for (final a in accessors) {
    final m = a as Map<String, dynamic>;
    if (m['min'] is! List || m['max'] is! List) continue;
    final min = (m['min'] as List).cast<num>();
    final max = (m['max'] as List).cast<num>();
    if (min.length != 3 || max.length != 3) continue;
    if ((min[0].toDouble() - b.minX).abs() < 1e-5 &&
        (max[1].toDouble() - b.maxY).abs() < 1e-5) {
      return m;
    }
  }
  fail('no POSITION accessor with min/max matching the parsed bounds');
}

void main() {
  group('rescaleGlbToDimensions (per-axis engine)', () {
    test('wall 2.4 × 2.7 × 0.05 m → 1.0 × 1.5 × 0.6 m extents match', () {
      final rescaled = rescaleGlbToDimensions(
        wallSource(),
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
      final source = wallSource();
      final srcBounds = GlbBounds.fromGlbBytes(source);
      final before = jsonChunkOf(source);
      final posBefore = positionAccessor(before, srcBounds);
      expectNear((posBefore['min'] as List)[0] as double, srcBounds.minX,
          1e-6, 'src minX');
      expectNear((posBefore['max'] as List)[1] as double, srcBounds.maxY,
          1e-6, 'src maxY');

      final rescaled = rescaleGlbToDimensions(
        source,
        targetWidthM: 1.0,
        targetHeightM: 1.5,
        targetDepthM: 0.6,
      );
      final json = jsonChunkOf(rescaled);
      final target = GlbBounds.fromGlbBytes(rescaled);
      final accessors = json['accessors'] as List<dynamic>;
      expect(accessors.length, before['accessors'].length,
          reason: 'accessor count unchanged');
      final pos = positionAccessor(json, target);
      final min = (pos['min'] as List).cast<num>();
      final max = (pos['max'] as List).cast<num>();
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
      final source = wallSource();
      Uint8List run() => rescaleGlbToDimensions(
            source,
            targetWidthM: 1.8,
            targetHeightM: 1.1,
            targetDepthM: 0.95,
          );
      expect(run(), run(), reason: 'same input → byte-identical output');
    });

    test('rejects non-positive target dimensions', () {
      expect(
        () => rescaleGlbToDimensions(wallSource(),
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
      final source = wallSource();
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

  group('rescaleGlbToSellerSize (seller dims drive the final size)', () {
    test('SPEC EXAMPLE: seller height 0.50 m, mesh height 0.70 m → 0.50 m '
        '(uniform, height-driven)', () {
      final mesh = meshAt070Height();
      expectNear(GlbBounds.fromGlbBytes(mesh).heightM, 0.70, 0.005,
          'source mesh really is 0.70 m tall');

      final out = rescaleGlbToSellerSize(
        mesh,
        const ProductDimensions(heightM: 0.50),
      );
      final bounds = parseGlb(out);
      expectNear(bounds.heightM, 0.50, 0.005, 'output height is 0.50 m');
      // Uniform: the other axes scale by the same 50/70 factor.
      expectNear(bounds.widthM, 0.6 * 50 / 70, 0.005, 'width follows');
      expectNear(bounds.depthM, 0.4 * 50 / 70, 0.005, 'depth follows');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded');
    });

    test('all three dims present → per-axis rescale to the exact W×H×D',
        () {
      final out = rescaleGlbToSellerSize(
        meshAt070Height(),
        const ProductDimensions(widthM: 1.2, heightM: 0.5, depthM: 0.7),
      );
      final bounds = parseGlb(out);
      expectNear(bounds.widthM, 1.2, 0.01, 'exact width');
      expectNear(bounds.heightM, 0.5, 0.01, 'exact height');
      expectNear(bounds.depthM, 0.7, 0.01, 'exact depth');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded');
    });

    test('only width given → uniform scale driven by the width', () {
      final out = rescaleGlbToSellerSize(
        meshAt070Height(),
        const ProductDimensions(widthM: 1.2), // 0.6 → 1.2, factor 2
      );
      final bounds = parseGlb(out);
      expectNear(bounds.widthM, 1.2, 0.01, 'width honored');
      expectNear(bounds.heightM, 1.4, 0.01, 'height scaled uniformly (×2)');
      expectNear(bounds.depthM, 0.8, 0.01, 'depth scaled uniformly (×2)');
    });

    test('only depth given → uniform scale driven by the depth', () {
      final out = rescaleGlbToSellerSize(
        meshAt070Height(),
        const ProductDimensions(depthM: 0.2), // 0.4 → 0.2, factor 0.5
      );
      final bounds = parseGlb(out);
      expectNear(bounds.depthM, 0.2, 0.01, 'depth honored');
      expectNear(bounds.widthM, 0.3, 0.01, 'width scaled uniformly (×0.5)');
      expectNear(bounds.heightM, 0.35, 0.01, 'height scaled uniformly (×0.5)');
    });

    test('height wins when several axes are given but not all three', () {
      final out = rescaleGlbToSellerSize(
        meshAt070Height(),
        const ProductDimensions(widthM: 9.9, heightM: 0.35), // 0.7 → 0.35
      );
      final bounds = parseGlb(out);
      expectNear(bounds.heightM, 0.35, 0.005, 'height drives the scale');
      expectNear(bounds.widthM, 0.3, 0.005, 'width NOT forced to 9.9');
    });

    test('zero dims → MissingDimensionsException (never a guessed size)',
        () {
      expect(
        () => rescaleGlbToSellerSize(
            meshAt070Height(), const ProductDimensions()),
        throwsA(isA<MissingDimensionsException>()),
      );
      expect(
        () => rescaleGlbToSellerSize(
            meshAt070Height(),
            const ProductDimensions(
                widthM: 0, heightM: 0, depthM: 0)),
        throwsA(isA<MissingDimensionsException>()),
      );
      expect(
        () => rescaleGlbToSellerSize(meshAt070Height(), null),
        throwsA(isA<MissingDimensionsException>()),
      );
    });

    test('negative dims are treated as absent', () {
      expect(
        () => rescaleGlbToSellerSize(meshAt070Height(),
            const ProductDimensions(widthM: -1, heightM: -1, depthM: -1)),
        throwsA(isA<MissingDimensionsException>()),
      );
    });

    test('malformed source → parse failure surfaces (no silent default)',
        () {
      expect(
        () => rescaleGlbToSellerSize(
          Uint8List.fromList([1, 2, 3]),
          const ProductDimensions(widthM: 1),
        ),
        throwsA(isA<GlbParseException>()),
      );
    });
  });
}
