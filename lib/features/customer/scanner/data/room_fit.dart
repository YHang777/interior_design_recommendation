import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Rect;

import '../../../../models/room_design.dart';
import 'furniture_catalog.dart' show heightCmForFurniture;

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
  List<List<Offset>> interiorWalls = const [],
}) {
  final fw = footprintW(f);
  final fh = footprintH(f);
  if (tl.dx < 0 || tl.dy < 0) return false;
  if (tl.dx + fw > roomW || tl.dy + fh > roomH) return false;
  if (interiorWalls.isNotEmpty &&
      rectHitsInteriorWalls(Rect.fromLTWH(tl.dx, tl.dy, fw, fh), interiorWalls)) {
    return false;
  }
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

// ── interior walls ──
// Partitions drawn inside the room are 10 cm slabs centered on their chain;
// a footprint may touch a face but never cross into the slab.
const double kInteriorWallHalfCm = 5.0;

bool rectHitsInteriorWalls(Rect r, List<List<Offset>> chains,
    {double halfThicknessCm = kInteriorWallHalfCm}) {
  // Shrink by a hair so a piece flush against a wall face still fits.
  final box = r.deflate(0.5);
  for (final chain in chains) {
    if (chain.isEmpty) continue;
    if (chain.length == 1) {
      if (distToRect(chain.first, box) < halfThicknessCm) return true;
      continue;
    }
    for (var i = 0; i + 1 < chain.length; i++) {
      if (_segmentRectDistance(chain[i], chain[i + 1], box) < halfThicknessCm) {
        return true;
      }
    }
  }
  return false;
}

double _segmentRectDistance(Offset a, Offset b, Rect r) {
  if (r.contains(a) || r.contains(b)) return 0;
  final c = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  for (var i = 0; i < 4; i++) {
    if (segmentsCross(a, b, c[i], c[(i + 1) % 4])) return 0;
  }
  var best = math.min(distToRect(a, r), distToRect(b, r));
  for (final p in c) {
    best = math.min(best, distToSegment(p, a, b));
  }
  return best;
}

// Wall-chain points flattened into segments (a lone corner is a post: a, a).
List<(Offset, Offset)> interiorWallSegments(List<List<Offset>> chains) => [
      for (final chain in chains)
        if (chain.length == 1)
          (chain.first, chain.first)
        else
          for (var i = 0; i + 1 < chain.length; i++) (chain[i], chain[i + 1]),
    ];

// Rugs and other flat floor coverings may sit under furniture; everything
// else needs its own floor patch.
bool isFloorCovering(FurniturePlacement f) =>
    heightCmForFurniture(f.iconName) < 5;

// Two footprints share real floor (touching edges is fine).
bool footprintsOverlap(FurniturePlacement a, FurniturePlacement b) {
  if (isFloorCovering(a) || isFloorCovering(b)) return false;
  final ra = furnitureRect(a).deflate(0.5);
  final rb = furnitureRect(b).deflate(0.5);
  return ra.overlaps(rb);
}

bool _clearOf(FurniturePlacement f, Offset tl, List<FurniturePlacement> others) {
  if (others.isEmpty) return true;
  final moved = f.copyWith(x: tl.dx, y: tl.dy);
  for (final o in others) {
    if (o.id == f.id) continue;
    if (footprintsOverlap(moved, o)) return false;
  }
  return true;
}

// Walk rings outward from the drop point (5 cm steps, 16 angles) and take
// the first spot that fits — the piece settles next to where the finger
// left it, never teleports to the room center. With [others], a spot must
// also be clear of the other pieces (a new chair can't vanish inside the
// sofa); a full room falls back to the walls-only fit.
FurniturePlacement resolveDrop(
  FurniturePlacement f, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
  List<FurniturePlacement> others = const [],
  List<List<Offset>> interiorWalls = const [],
}) {
  bool fits(Offset tl) => fitsAt(
      f: f,
      tl: tl,
      roomW: roomW,
      roomH: roomH,
      walls: walls,
      interiorWalls: interiorWalls);
  final found = _ringSearch(f, roomW, roomH,
      (tl) => fits(tl) && _clearOf(f, tl, others));
  if (found != null) return found;
  if (others.isEmpty) return f;
  return _ringSearch(f, roomW, roomH, fits) ?? f;
}

FurniturePlacement? _ringSearch(FurniturePlacement f, double roomW,
    double roomH, bool Function(Offset tl) ok) {
  if (ok(Offset(f.x, f.y))) return f;
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
      if (ok(cand)) return f.copyWith(x: cand.dx, y: cand.dy);
    }
  }
  return null;
}

// Room-size validation: the piece as given if it fits somewhere, else the
// piece turned 90° if THAT fits, else null — it is bigger than the room and
// must be refused, never parked half inside a wall.
FurniturePlacement? fitInRoom(
  FurniturePlacement f, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
  List<FurniturePlacement> others = const [],
  List<List<Offset>> interiorWalls = const [],
}) {
  for (final cand in [f, f.copyWith(rotation: (f.rotation + 90) % 360)]) {
    final r = resolveDrop(cand,
        roomW: roomW,
        roomH: roomH,
        walls: walls,
        others: others,
        interiorWalls: interiorWalls);
    if (placementFits(r,
        roomW: roomW,
        roomH: roomH,
        walls: walls,
        interiorWalls: interiorWalls)) {
      return r;
    }
  }
  return null;
}

// Pieces that fit nowhere in the room at either orientation.
List<FurniturePlacement> unfitPlacements(
  List<FurniturePlacement> items, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
  List<List<Offset>> interiorWalls = const [],
}) =>
    [
      for (final f in items)
        if (fitInRoom(f,
                roomW: roomW,
                roomH: roomH,
                walls: walls,
                interiorWalls: interiorWalls) ==
            null)
          f,
    ];

// ── placement guards ──

Rect furnitureRect(FurniturePlacement f) =>
    Rect.fromLTWH(f.x, f.y, footprintW(f), footprintH(f));

double distToRect(Offset p, Rect r) {
  final dx = max(max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = max(max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return sqrt(dx * dx + dy * dy);
}

bool placementFits(
  FurniturePlacement f, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
  List<List<Offset>> interiorWalls = const [],
}) =>
    fitsAt(
        f: f,
        tl: Offset(f.x, f.y),
        roomW: roomW,
        roomH: roomH,
        walls: walls,
        interiorWalls: interiorWalls);

// Render clamp for legacy/round-tripped designs: keep valid placements,
// settle the rest next to where they are — never drawn inside a wall.
List<FurniturePlacement> clampAllPlacements(
  List<FurniturePlacement> items, {
  required double roomW,
  required double roomH,
  required List<Offset> walls,
  List<List<Offset>> interiorWalls = const [],
}) =>
    [
      for (final f in items)
        placementFits(f,
                roomW: roomW,
                roomH: roomH,
                walls: walls,
                interiorWalls: interiorWalls)
            ? f
            : resolveDrop(f,
                roomW: roomW,
                roomH: roomH,
                walls: walls,
                interiorWalls: interiorWalls),
    ];
