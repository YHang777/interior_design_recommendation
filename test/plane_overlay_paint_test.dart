import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:interior_design_recommendation/features/customer/ar/presentation/widgets/plane_overlay.dart';
import 'package:vector_math/vector_math_64.dart';

// vertical: true gives world-Y extent — under the identity vp a horizontal
// quad collapses to a line, and the paint-time dust cull (rightly) drops
// it; the cache test needs a polygon that survives to the booleans.
PlaneQuad _floorQuad() => PlaneQuad(
      center: Vector3(0, 0, 0),
      yaw: 0,
      extentX: 2,
      extentZ: 2,
      vertical: true,
      kind: PlaneQuadKind.floor,
    );

PlaneQuad _maskQuad() => PlaneQuad(
      center: Vector3(0, 0.5, 0),
      yaw: 0,
      extentX: 1,
      extentZ: 1,
      vertical: false,
      kind: PlaneQuadKind.floor,
    );

void main() {
  final vp = Matrix4.identity();
  final quads = <PlaneQuad>[_floorQuad()];
  final masks = <PlaneQuad>[_maskQuad()];

  group('PlaneOverlayPainter.shouldRepaint', () {
    test('same vp/quads/masks instances → no repaint', () {
      final a = PlaneOverlayPainter(vp, quads, masks);
      final b = PlaneOverlayPainter(vp, quads, masks);
      expect(b.shouldRepaint(a), isFalse,
          reason: 'snap.renderQuads relies on stable list identity');
    });

    test('a fresh quads list → repaint', () {
      final a = PlaneOverlayPainter(vp, quads, masks);
      final b = PlaneOverlayPainter(vp, <PlaneQuad>[...quads], masks);
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  group('PlaneOverlayPainter zone cache', () {
    test('zones are cached per viewport and reused across paints', () {
      final cache = OverlayZoneCache();
      final painter = PlaneOverlayPainter(vp, quads, masks, cache);

      painter.paint(Canvas(PictureRecorder()), const Size(400, 600));
      expect(cache.floor, isNotNull);
      expect(cache.size, const Size(400, 600));
      final before = cache.floor;

      // Same snapshot, same viewport: the Skia path booleans must be
      // skipped — the cache hands back the very same Path.
      painter.paint(Canvas(PictureRecorder()), const Size(400, 600));
      expect(identical(cache.floor, before), isTrue);

      // A viewport change must reproject instead of drawing stale zones.
      painter.paint(Canvas(PictureRecorder()), const Size(800, 600));
      expect(cache.size, const Size(800, 600));
      expect(identical(cache.floor, before), isFalse);
    });

    test('a changed viewProjection at the same size rebuilds the zones',
        () {
      final cache = OverlayZoneCache();
      final painter = PlaneOverlayPainter(vp, quads, masks, cache);

      painter.paint(Canvas(PictureRecorder()), const Size(400, 600));
      final before = cache.floor;
      expect(identical(cache.vp, vp), isTrue);

      // Camera moved, viewport unchanged: a size-only cache hit would
      // redraw screen-space paths frozen at the old matrix — the painted
      // plane would slide with the preview instead of holding world pos.
      final moved = Matrix4.translationValues(5.0, 0, 0);
      final movedPainter = PlaneOverlayPainter(moved, quads, masks, cache);
      movedPainter.paint(Canvas(PictureRecorder()), const Size(400, 600));
      expect(cache.vp, moved);
      expect(identical(cache.floor, before), isFalse);
    });
  });

  group('boundZonePolys', () {
    List<Offset> rect(double l, double t, double r, double b) =>
        [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];

    test('off-screen polygons never enter the boolean', () {
      final kept = boundZonePolys(
        [rect(5000, 5000, 5200, 5200), rect(100, 100, 300, 300)],
        const Size(400, 600),
        14,
      );
      expect(kept, hasLength(1));
      expect(kept.single, hasLength(4));
      expect(kept.single.first, const Offset(100, 100));
    });

    test('dust-sized specks are dropped', () {
      final kept = boundZonePolys(
        [rect(10, 10, 20, 20), rect(50, 50, 350, 400)],
        const Size(400, 600),
        14,
      );
      expect(kept, hasLength(1));
      expect(kept.single.first, const Offset(50, 50));
    });

    test('past the cap only the largest screen regions remain', () {
      final polys = [
        for (var i = 0; i < 6; i++) rect(0, 0, 50.0 + i * 40, 50.0 + i * 40),
      ];
      final kept = boundZonePolys(polys, const Size(400, 600), 3);
      expect(kept, hasLength(3));
      expect(identical(kept.first, polys.last), isTrue,
          reason: 'largest screen area ranks first');
      expect(kept.contains(polys.first), isFalse,
          reason: 'smallest falls past the cap');
    });

    test('under the cap every on-screen polygon survives', () {
      final polys = [rect(0, 0, 100, 100), rect(120, 120, 380, 500)];
      final kept = boundZonePolys(polys, const Size(400, 600), 14);
      expect(kept, hasLength(2));
    });
  });
}
