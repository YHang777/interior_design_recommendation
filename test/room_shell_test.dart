import 'package:flutter/material.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart'
    show pointInPolygon;
import 'package:interior_design_recommendation/features/customer/scanner/data/room_shell.dart';

void main() {
  const squareCCW = [Offset(0, 0), Offset(400, 0), Offset(400, 500), Offset(0, 500)];
  const squareCW = [Offset(0, 0), Offset(0, 500), Offset(400, 500), Offset(400, 0)];
  const lShape = [
    Offset(0, 0),
    Offset(200, 0),
    Offset(200, 100),
    Offset(100, 100),
    Offset(100, 200),
    Offset(0, 200),
  ];

  void expectOffset(Offset actual, Offset expected, {double tol = 1e-6}) {
    expect(actual.dx, closeTo(expected.dx, tol), reason: 'x of $actual vs $expected');
    expect(actual.dy, closeTo(expected.dy, tol), reason: 'y of $actual vs $expected');
  }

  group('offsetRing', () {
    test('square outer offset is the expanded square, both windings', () {
      final ccw = offsetRing(squareCCW, 10);
      expectOffset(ccw[0], const Offset(-10, -10));
      expectOffset(ccw[1], const Offset(410, -10));
      expectOffset(ccw[2], const Offset(410, 510));
      expectOffset(ccw[3], const Offset(-10, 510));

      final cw = offsetRing(squareCW, 10);
      expectOffset(cw[0], const Offset(-10, -10));
      expectOffset(cw[1], const Offset(-10, 510));
      expectOffset(cw[2], const Offset(410, 510));
      expectOffset(cw[3], const Offset(410, -10));
    });

    test('outward normals point away from the interior for any winding', () {
      for (final ring in [squareCCW, squareCW, lShape]) {
        final shell = ShellGeometry(ringCm: ring);
        expect(shell.wallSegments, hasLength(ring.length));
        for (final seg in shell.wallSegments) {
          expect(seg.outward.distance, closeTo(1, 1e-9));
          final mid = Offset((seg.a.dx + seg.b.dx) / 2, (seg.a.dy + seg.b.dy) / 2);
          expect(pointInPolygon(mid + seg.outward * 3, ring), isFalse,
              reason: 'outward probe must land outside');
          expect(pointInPolygon(mid - seg.outward * 3, ring), isTrue,
              reason: 'inward probe must land inside');
        }
      }
    });

    test('L-shape reflex corner miters to the outer notch corner', () {
      final outer = offsetRing(lShape, 10);
      // Ring vertex (100,100) is the reflex corner; its miter point is the
      // intersection of the two outer wall faces at (110,110).
      final reflexMiter = outer[3];
      expectOffset(reflexMiter, const Offset(110, 110));
      // Convex corner (200,0) miter-checks to (210,-10).
      expectOffset(outer[1], const Offset(210, -10));
    });

    test('negative delta offsets into the room (baseboard face)', () {
      final inner = offsetRing(squareCCW, -1.5);
      expectOffset(inner[0], const Offset(1.5, 1.5));
      expectOffset(inner[1], const Offset(398.5, 1.5));
      expectOffset(inner[2], const Offset(398.5, 498.5));
      expectOffset(inner[3], const Offset(1.5, 498.5));
    });
  });

  group('ShellGeometry', () {
    test('wall corners are watertight around the whole ring', () {
      for (final ring in [squareCCW, lShape]) {
        final shell = ShellGeometry(ringCm: ring);
        final segs = shell.wallSegments;
        for (var i = 0; i < segs.length; i++) {
          expectOffset(segs[i].outerB, segs[(i + 1) % segs.length].outerA);
          expectOffset(segs[i].b, segs[(i + 1) % segs.length].a);
        }
      }
    });

    test('baseboard quads sit on the inner face, proud into the room', () {
      final shell = ShellGeometry(ringCm: squareCCW);
      final quads = shell.baseboardPlanQuads;
      expect(quads, hasLength(4));
      expectOffset(quads[0][0], const Offset(0, 0));
      expectOffset(quads[0][1], const Offset(400, 0));
      expectOffset(quads[0][2], const Offset(398.5, 1.5));
      expectOffset(quads[0][3], const Offset(1.5, 1.5));
    });

    test('floor triangulation covers square and L-shape exactly', () {
      final sq = ShellGeometry(ringCm: squareCCW);
      expect(sq.floorTriangles, hasLength(2));
      expect(sq.floorAreaCm2, closeTo(400 * 500, 1e-6));

      final l = ShellGeometry(ringCm: lShape);
      expect(l.floorTriangles, hasLength(lShape.length - 2));
      expect(l.floorAreaCm2, closeTo(30000, 1e-6));
      var triSum = 0.0;
      for (final t in l.floorTriangles) {
        triSum += ((t[1].dx - t[0].dx) * (t[2].dy - t[0].dy) -
                (t[1].dy - t[0].dy) * (t[2].dx - t[0].dx)) /
            2;
      }
      expect(triSum.abs(), closeTo(l.floorAreaCm2, 1e-6));
    });

    test('collinear extra vertices do not change the floor area', () {
      const withMid = [
        Offset(0, 0),
        Offset(200, 0),
        Offset(400, 0),
        Offset(400, 500),
        Offset(0, 500),
      ];
      final shell = ShellGeometry(ringCm: withMid);
      expect(shell.floorAreaCm2, closeTo(400 * 500, 1e-6));
      expect(shell.floorTriangles, hasLength(withMid.length - 2));
    });

    test('degenerate rings produce an empty shell', () {
      final shell = ShellGeometry(ringCm: const [Offset(0, 0), Offset(10, 0)]);
      expect(shell.wallSegments, isEmpty);
      expect(shell.floorTriangles, isEmpty);
      expect(shell.floorAreaCm2, 0);
    });

    test('bounds include the outer wall faces', () {
      final shell = ShellGeometry(ringCm: squareCCW);
      expect(shell.boundsCm, const Rect.fromLTRB(-10, -10, 410, 510));
    });
  });
}
