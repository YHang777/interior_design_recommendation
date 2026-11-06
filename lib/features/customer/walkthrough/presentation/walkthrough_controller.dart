import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../models/room_design.dart';
import '../../scanner/data/room_fit.dart';

// Pose + movement + placement for the 2D walkthrough. Deliberately pure
// data behind ChangeNotifier: position/heading is the stream a future 3D/VR
// renderer will consume — only the painter changes when VR arrives.
class WalkthroughController extends ChangeNotifier {
  WalkthroughController({required RoomDesign design})
      : roomW = design.widthCm,
        roomH = design.heightCm,
        walls = List.of(design.walls),
        furniture = List.of(design.furniture) {
    walker = _findSpawn();
  }

  final double roomW;
  final double roomH;
  final List<Offset> walls;
  final List<FurniturePlacement> furniture;

  // Room coords in cm (y grows south); heading in radians, 0 = east.
  late Offset walker;
  double heading = 0;
  double zoom = 1;

  static const stepCm = 30.0;
  static const walkerRadiusCm = 18.0;
  static const turnStepRad = pi / 12; // 15° per press — Street View feel

  bool _validSpot(Offset p) {
    if (p.dx < walkerRadiusCm ||
        p.dy < walkerRadiusCm ||
        p.dx > roomW - walkerRadiusCm ||
        p.dy > roomH - walkerRadiusCm) {
      return false;
    }
    if (walls.length < 3) return true;
    if (!pointInPolygon(p, walls)) return false;
    for (var i = 0; i < walls.length; i++) {
      final a = walls[i];
      final b = walls[(i + 1) % walls.length];
      if (distToSegment(p, a, b) < walkerRadiusCm) return false;
    }
    return true;
  }

  Offset _findSpawn() {
    final c = Offset(roomW / 2, roomH / 2);
    if (_validSpot(c)) return c;
    // Same ring walk the planner uses on a bad drop — spawn at the first
    // free spot instead of materializing inside a wall.
    final maxR = sqrt(roomW * roomW + roomH * roomH);
    for (var r = 5.0; r <= maxR; r += 5.0) {
      for (var i = 0; i < 16; i++) {
        final a = 2 * pi * i / 16;
        final cand = Offset(c.dx + cos(a) * r, c.dy + sin(a) * r);
        if (_validSpot(cand)) return cand;
      }
    }
    return c;
  }

  // Street View semantics: forward/back travel along wherever the camera
  // faces; the arrows only turn when you ask them to.
  void walk(double along) {
    if (along == 0) return;
    move(Offset(cos(heading) * along, sin(heading) * along));
  }

  void turn(double delta) {
    if (delta == 0) return;
    heading += delta;
    notifyListeners();
  }

  // One arrow press = one step; blocked moves slide along a single axis so
  // walking beside a wall keeps forward progress instead of stalling.
  void move(Offset dir) {
    if (dir == Offset.zero) return;
    final target = walker + dir * stepCm;
    Offset? next;
    if (_validSpot(target)) {
      next = target;
    } else if (_validSpot(Offset(target.dx, walker.dy))) {
      next = Offset(target.dx, walker.dy);
    } else if (_validSpot(Offset(walker.dx, target.dy))) {
      next = Offset(walker.dx, target.dy);
    }
    final turned = atan2(dir.dy, dir.dx) != heading;
    heading = atan2(dir.dy, dir.dx);
    if (next != null && next != walker) {
      walker = next;
      notifyListeners();
    } else if (turned) {
      notifyListeners();
    }
  }

  void setZoom(double z) {
    final clamped = z.clamp(0.6, 3.0);
    if (clamped == zoom) return;
    zoom = clamped;
    notifyListeners();
  }

  // Walker-centered drop target, settled by the planner's ring search so
  // the ghost always shows where the piece will actually land.
  FurniturePlacement resolveGhost(FurniturePlacement f) {
    final tl = Offset(
      walker.dx - footprintW(f) / 2,
      walker.dy - footprintH(f) / 2,
    );
    return resolveDrop(
      f.copyWith(x: tl.dx, y: tl.dy),
      roomW: roomW,
      roomH: roomH,
      walls: walls,
    );
  }

  FurniturePlacement place(FurniturePlacement f) {
    final placed = resolveGhost(f);
    furniture.add(placed);
    notifyListeners();
    return placed;
  }
}
