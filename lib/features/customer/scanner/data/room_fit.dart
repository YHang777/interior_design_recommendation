import 'dart:math';

import 'package:flutter/material.dart' show Offset;

import '../../../../models/room_design.dart';

// Shared room geometry: the planner and the walkthrough must agree on what
// "fits" means, so one implementation backs both.

double footprintW(FurniturePlacement f) =>
    f.rotation % 180 == 90 ? f.height : f.width;

double footprintH(FurniturePlacement f) =>
    f.rotation % 180 == 90 ? f.width : f.height;

double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
      .clamp(0.0, 1.0);
  final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
  return (p - proj).distance;
}

// Boundary counts as inside — pure ray-casting reports points exactly on a
// wall as outside, which would ban flush placement.
bool pointInPolygon(Offset p, List<Offset> walls) {
  if (walls.length < 3) return true;
  for (int i = 0, j = walls.length - 1; i < walls.length; j = i++) {
    if (distToSegment(p, walls[i], walls[j]) < 0.5) return true;
  }
  var inside = false;
  for (int i = 0, j = walls.length - 1; i < walls.length; j = i++) {
    final a = walls[i];
    final b = walls[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

bool segmentsCross(Offset p1, Offset p2, Offset q1, Offset q2) {
  double cross(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final d1 = cross(q1, q2, p1);
  final d2 = cross(q1, q2, p2);
  final d3 = cross(p1, p2, q1);
  final d4 = cross(p1, p2, q2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

// A drop is valid when the footprint sits inside the room rectangle and,
// if walls outline a polygon, fully inside it (all four corners in the
// polygon AND no wall edge slicing through the footprint — the corner
// test alone fails for concave outlines).
bool fitsAt({
  required FurniturePlacement f,
  required Offset tl,
  required double roomW,
  required double roomH,
  required List<Offset> walls,
}) {
  final fw = footprintW(f);
  final fh = footprintH(f);
  if (tl.dx < 0 || tl.dy < 0) return false;
  if (tl.dx + fw > roomW || tl.dy + fh > roomH) return false;
  if (walls.length < 3) return true;

  final corners = [
    tl,
    tl + Offset(fw, 0),
    tl + Offset(0, fh),
    tl + Offset(fw, fh),
  ];
  for (final c in corners) {
    if (!pointInPolygon(c, walls)) return false;
  }
  for (var i = 0; i < walls.length; i++) {
    final a1 = walls[i];
    final a2 = walls[(i + 1) % walls.length];
    if (segmentsCross(a1, a2, corners[0], corners[1]) ||
        segmentsCross(a1, a2, corners[1], corners[3]) ||
        segmentsCross(a1, a2, corners[3], corners[2]) ||
        segmentsCross(a1, a2, corners[2], corners[0])) {
      return false;
    }
  }
  return true;
}

// Walk rings outward from the drop point (5 cm steps, 16 angles) and take
// the first spot that fits — the piece settles next to where the finger
// left it, never teleports to the room center.
FurniturePlacement resolveDrop(
  FurniturePlacement f, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
}) {
  if (fitsAt(f: f, tl: Offset(f.x, f.y), roomW: roomW, roomH: roomH, walls: walls)) {
    return f;
  }
  final fw = footprintW(f);
  final fh = footprintH(f);
  final maxX = max(0.0, roomW - fw);
  final maxY = max(0.0, roomH - fh);

  final maxR = sqrt(roomW * roomW + roomH * roomH);
  for (var r = 5.0; r <= maxR; r += 5.0) {
    const steps = 16;
    for (var i = 0; i < steps; i++) {
      final a = 2 * pi * i / steps;
      final cand = Offset(
        (f.x + cos(a) * r).clamp(0.0, maxX).toDouble(),
        (f.y + sin(a) * r).clamp(0.0, maxY).toDouble(),
      );
      if (fitsAt(f: f, tl: cand, roomW: roomW, roomH: roomH, walls: walls)) {
        return f.copyWith(x: cand.dx, y: cand.dy);
      }
    }
  }
  return f;
}
