import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../scanner/data/room_shell.dart'
    show ShellGeometry, kShellCutawayHeightCm;
import 'plane_overlay_math.dart' show rectHitsPolygons;
import 'room_finishes.dart' show RoomFinishCatalog;

const int _kGlbMagic = 0x46546C67;
const int _kChunkJson = 0x4E4F534A;
const int _kChunkBin = 0x004E4942;
const int _kComponentFloat = 5126;
const int _kComponentUint16 = 5123;
const int _kComponentUint32 = 5125;

const double _kPi2 = 6.283185307179586;

// ─── Floor / wall finish specs (Loop 4 customization) ───────────────────────

enum FloorFinishType { woodPlanks, cement, ceramicTiles, parquet }

class FloorFinish {
  const FloorFinish({
    this.type = FloorFinishType.woodPlanks,
    required this.colorArgb,
    this.sizeM = 3.0,
  });

  final FloorFinishType type;
  final int colorArgb;
  final double sizeM;
}

enum WallFinishType { paint, woodPanels, brick }

class WallFinish {
  const WallFinish({
    this.type = WallFinishType.paint,
    required this.colorArgb,
  });

  final WallFinishType type;
  final int colorArgb;
}

// ─── Deterministic RNG + color helpers ──────────────────────────────────────

class _Rand {
  _Rand(int seed) : _state = (seed & 0x7FFFFFFF) == 0 ? 0x9E3779B9 : seed;

  int _state;

  void _advance() {
    _state = (_state * 1664525 + 1013904223) & 0x7FFFFFFF;
  }

  double nextDouble() {
    _advance();
    return _state / 0x80000000;
  }

  int nextInt(int bound) {
    _advance();
    return _state % bound;
  }

  double range(double min, double max) => min + (max - min) * nextDouble();
}

int _tone(int argb, double p) {
  int ch(int c) {
    final v = c * p;
    return v < 0 ? 0 : (v > 255 ? 255 : v.round());
  }

  return 0xFF000000 |
      (ch((argb >> 16) & 0xFF) << 16) |
      (ch((argb >> 8) & 0xFF) << 8) |
      ch(argb & 0xFF);
}

int _mix(int a, int b, double t) {
  int ch(int ca, int cb) => (ca + (cb - ca) * t).round();
  return 0xFF000000 |
      (ch((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16) |
      (ch((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8) |
      ch(a & 0xFF, b & 0xFF);
}

const int _kGrey = 0xFFA0A0A0;

List<double> _rgb(int argb) => [
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
    ];

// num.clamp throws when lo > hi and would crash the generator on absurdly
// squat products; callers still degrade parts out of existence when there is
// no real room for them.
double _clampSafe(double v, double lo, double hi) {
  final a = math.min(lo, hi);
  final b = math.max(lo, hi);
  return v.clamp(a, b).toDouble();
}

const List<int> _wood = [
  0xFF8B5A2B, 0xFFA0714F, 0xFF6F4E37, 0xFF9C6B3E, 0xFF7C5433,
];
const List<int> _fabric = [
  0xFFB0A69A, 0xFF9C938A, 0xFFC2B8AA, 0xFF8D857B, 0xFFA79F96,
];
const List<int> _metal = [0xFF3B3B38, 0xFF55524E, 0xFF2B2B29, 0xFF45433F];
const List<int> _shadeWarm = [0xFFC9A878, 0xFFE3D2B3, 0xFFB98F63, 0xFFD8C3A5];
const List<int> _decor = [0xFF9A6B53, 0xFFC08552, 0xFFB99362, 0xFF8C6F5A];
const List<int> _foliage = [0xFF4E7A4A, 0xFF5F8C52, 0xFF3F6B3E, 0xFF6B9458];

// ─── Geometry ───────────────────────────────────────────────────────────────

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;

  _Vec3 operator -(final _Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);

  double dot(final _Vec3 o) => x * o.x + y * o.y + z * o.z;

  _Vec3 normalized() {
    final l = math.sqrt(dot(this));
    return l == 0 ? this : _Vec3(x / l, y / l, z / l);
  }

  static _Vec3 cross(final _Vec3 a, final _Vec3 b) => _Vec3(
      a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

class _Mesh {
  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _colors = [];
  final List<int> _indices = [];
  final List<int> _mats = [];

  int get vertexCount => _positions.length ~/ 3;
  int get indexCount => _indices.length;

  void _tri(_Vec3 a, _Vec3 b, _Vec3 c, _Vec3 n, int color, [int mat = 0]) {
    var v0 = b - a;
    var v1 = c - a;
    if (n.dot(_Vec3.cross(v0, v1)) < 0) {
      final t = b;
      b = c;
      c = t;
      v0 = b - a;
      v1 = c - a;
    }
    if (n.dot(_Vec3.cross(v0, v1)) <= 0) return;
    final base = vertexCount;
    final col = _rgb(color);
    for (final v in [a, b, c]) {
      _positions
        ..add(v.x)
        ..add(v.y)
        ..add(v.z);
      _normals
        ..add(n.x)
        ..add(n.y)
        ..add(n.z);
      _colors.addAll(col);
    }
    _indices
      ..add(base)
      ..add(base + 1)
      ..add(base + 2);
    _mats.add(mat);
  }

  void quad(_Vec3 a, _Vec3 b, _Vec3 c, _Vec3 d, _Vec3 normal, int color,
      [int mat = 0]) {
    _tri(a, b, c, normal, color, mat);
    _tri(a, c, d, normal, color, mat);
  }

  void box(double x0, double y0, double z0, double x1, double y1, double z1,
      int color,
      [int mat = 0]) {
    quad(_Vec3(x1, y0, z0), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1),
        _Vec3(x1, y1, z0), const _Vec3(1, 0, 0), color, mat);
    quad(_Vec3(x0, y0, z1), _Vec3(x0, y0, z0), _Vec3(x0, y1, z0),
        _Vec3(x0, y1, z1), const _Vec3(-1, 0, 0), color, mat);
    quad(_Vec3(x0, y1, z0), _Vec3(x1, y1, z0), _Vec3(x1, y1, z1),
        _Vec3(x0, y1, z1), const _Vec3(0, 1, 0), color, mat);
    quad(_Vec3(x0, y0, z1), _Vec3(x1, y0, z1), _Vec3(x1, y0, z0),
        _Vec3(x0, y0, z0), const _Vec3(0, -1, 0), color, mat);
    quad(_Vec3(x0, y0, z1), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1),
        _Vec3(x0, y1, z1), const _Vec3(0, 0, 1), color, mat);
    quad(_Vec3(x1, y0, z0), _Vec3(x0, y0, z0), _Vec3(x0, y1, z0),
        _Vec3(x1, y1, z0), const _Vec3(0, 0, -1), color, mat);
  }

  // Regular [sides]-sided prism / frustum between y0 and y1 on (cx, cz),
  // bottom radius r0, top radius r1 (r0 == r1 cylinder, r0 > r1 shade).
  void prism({
    required int sides,
    required double r0,
    required double r1,
    required double y0,
    required double y1,
    double cx = 0,
    double cz = 0,
    required int color,
    bool closeBottom = false,
    bool closeTop = false,
    int mat = 0,
  }) {
    assert(sides >= 3 && y1 > y0);
    for (var k = 0; k < sides; k++) {
      final t0 = k * _kPi2 / sides;
      final t1 = (k + 1) * _kPi2 / sides;
      final a = _Vec3(cx + r0 * math.cos(t0), y0, cz + r0 * math.sin(t0));
      final b = _Vec3(cx + r0 * math.cos(t1), y0, cz + r0 * math.sin(t1));
      final c = _Vec3(cx + r1 * math.cos(t1), y1, cz + r1 * math.sin(t1));
      final d = _Vec3(cx + r1 * math.cos(t0), y1, cz + r1 * math.sin(t0));
      final tm = (t0 + t1) / 2;
      var n = _Vec3.cross(b - a, d - a);
      if (n.dot(_Vec3(math.cos(tm), 0, math.sin(tm))) < 0) {
        n = _Vec3.cross(d - a, b - a);
      }
      quad(a, b, c, d, n.normalized(), color, mat);
    }
    if (closeBottom) _cap(r0, y0, cx, cz, false, sides, color, mat);
    if (closeTop) _cap(r1, y1, cx, cz, true, sides, color, mat);
  }

  void _cap(double r, double y, double cx, double cz, bool top, int sides,
      int color, int mat) {
    if (r <= 0) return;
    final center = _Vec3(cx, y, cz);
    final normal = top ? const _Vec3(0, 1, 0) : const _Vec3(0, -1, 0);
    for (var k = 0; k < sides; k++) {
      final t0 = k * _kPi2 / sides;
      final t1 = (k + 1) * _kPi2 / sides;
      final a = _Vec3(cx + r * math.cos(t0), y, cz + r * math.sin(t0));
      final b = _Vec3(cx + r * math.cos(t1), y, cz + r * math.sin(t1));
      _tri(center, b, a, normal, color, mat);
    }
  }
}

// ─── Shape-family classification (shared with product_form_screen.dart) ──────

bool _hasAnyKeyword(String name, List<String> keywords) {
  for (final k in keywords) {
    if (name.contains(k)) return true;
  }
  return false;
}

String _decorKeywordFamily(String n) {
  if (_hasAnyKeyword(n, const ['rug', 'carpet'])) return 'rug';
  if (_hasAnyKeyword(n, const ['vase', 'planter', 'pot'])) return 'vase';
  // 'planter' contains 'plant', so the vase sweep must run first.
  if (_hasAnyKeyword(n, const ['plant', 'fern', 'ficus'])) return 'plant';
  if (_hasAnyKeyword(n, const ['mirror', 'art', 'frame', 'picture'])) {
    return 'mirror';
  }
  if (_hasAnyKeyword(n, const ['cushion', 'pillow'])) return 'cushion';
  if (_hasAnyKeyword(n, const ['lamp', 'light', 'chandelier', 'sconce', 'lantern'])) {
    return 'lamp';
  }
  return 'default';
}

String resolveShapeFamily({required String category, required String name}) {
  final n = name.toLowerCase();
  final cat = category.trim().toLowerCase();

  if (cat == 'lighting') return 'lamp';
  if (cat == 'decor') return _decorKeywordFamily(n);

  if (_hasAnyKeyword(n, const ['rug', 'carpet'])) return 'rug';
  if (_hasAnyKeyword(n, const ['bedside', 'nightstand'])) return 'cabinet';
  if (_hasAnyKeyword(n, const ['vase', 'planter', 'pot'])) return 'vase';
  // 'planter' contains 'plant', so the vase sweep must run first.
  if (_hasAnyKeyword(n, const ['plant', 'fern', 'ficus'])) return 'plant';
  if (_hasAnyKeyword(n, const ['mirror', 'art', 'frame', 'picture'])) {
    return 'mirror';
  }
  if (_hasAnyKeyword(n, const ['cushion', 'pillow'])) return 'cushion';
  // Specific seats before the sofa sweep so 'Recliner Armchair' stays an
  // armchair while a bare 'Recliner' reads as sofa seating.
  if (n.contains('armchair')) return 'armchair';
  if (_hasAnyKeyword(n, const [
    'sofa',
    'couch',
    'loveseat',
    'settee',
    'futon',
    'sectional',
    'recliner',
  ])) {
    return 'sofa';
  }
  if (_hasAnyKeyword(n, const ['lamp', 'light', 'chandelier', 'sconce', 'lantern'])) {
    return 'lamp';
  }
  if (_hasAnyKeyword(n, const ['bed', 'mattress', 'crib', 'bunk'])) return 'bed';
  if (_hasAnyKeyword(n, const ['chair', 'stool', 'bench', 'ottoman', 'pouf'])) {
    return 'chair';
  }
  // 'tv stand' (not bare 'stand') so a standing desk still reads as a table.
  if (_hasAnyKeyword(n, const [
    'cabinet',
    'shelf',
    'bookcase',
    'wardrobe',
    'chest',
    'tv stand',
    'tvstand',
    'dresser',
    'sideboard',
    'buffet',
    'vanity',
    'credenza',
    'rack',
    'counter',
    'island',
    'fridge',
    'refrigerator',
    'oven',
    'stove',
    'washer',
    'dryer',
    'dishwasher',
  ])) {
    return 'cabinet';
  }
  if (n.contains('table') || n.contains('dining') || n.contains('desk')) {
    return 'table';
  }
  // A screen named as itself reads as a thin wall panel — checked AFTER the
  // cabinet sweep so 'TV Stand' furniture keeps winning.
  if (_hasAnyKeyword(n, const ['tv', 'television', 'monitor'])) return 'mirror';
  return 'default';
}

// ─── Deterministic seeding ───────────────────────────────────────────────────

int _nameSeed(String text) {
  var h = 0x811C9DC5;
  for (final c in text.toLowerCase().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

// ─── Furniture generators ───────────────────────────────────────────────────

// Real-world meters, Y-up, base on y = 0, centered on X/Z. Squat or absurd
// seller sizes degrade parts out of existence — never throw on proportions
// that are merely extreme.
Uint8List generateFurnitureGlb({
  required String category,
  required String name,
  required double widthM,
  required double heightM,
  required double depthM,
  int seedOrColor = 0,
}) {
  if (widthM <= 0 || heightM <= 0 || depthM <= 0) {
    throw ArgumentError.value(
      [widthM, heightM, depthM],
      'dimensions',
      'generateFurnitureGlb requires positive widthM/heightM/depthM '
          '(got $widthM × $heightM × $depthM m).',
    );
  }
  final rng = _Rand(_nameSeed(name) ^ (seedOrColor & 0x7FFFFFFF));
  final cat = category.toLowerCase();
  final mesh = _Mesh();
  final family = resolveShapeFamily(category: category, name: name);

  switch (family) {
    case 'table':
      _buildTable(mesh, widthM, heightM, depthM, rng);
      break;
    case 'sofa':
      _buildSofa(mesh, widthM, heightM, depthM, rng);
      break;
    case 'chair':
    case 'armchair':
      _buildChair(mesh, widthM, heightM, depthM, rng,
          armrests: family == 'armchair');
      break;
    case 'bed':
      _buildBed(mesh, widthM, heightM, depthM, rng);
      break;
    case 'cabinet':
      _buildCabinet(mesh, widthM, heightM, depthM, rng);
      break;
    case 'lamp':
      _buildLamp(mesh, widthM, heightM, rng);
      break;
    case 'rug':
      _buildRug(mesh, widthM, depthM, rng);
      break;
    case 'vase':
      _buildVase(mesh, widthM, heightM, depthM, rng);
      break;
    case 'plant':
      _buildPlant(mesh, widthM, heightM, depthM, rng);
      break;
    case 'mirror':
      _buildWallArt(mesh, widthM, heightM, depthM, rng);
      break;
    case 'cushion':
      _buildCushion(mesh, widthM, heightM, depthM, rng);
      break;
    default:
      final textile = cat.contains('textile') || cat.contains('fab');
      final palette = textile ? _fabric : _wood;
      mesh.box(-widthM / 2, 0, -depthM / 2, widthM / 2, heightM, depthM / 2,
          _tone(palette[rng.nextInt(palette.length)], 0.96),
          textile ? _kMatMatte : _kMatSatin);
  }

  if (mesh.indexCount == 0) {
    throw StateError('Shape "$name" produced no geometry.');
  }
  return mesh.buildGlb(name.isEmpty ? 'furniture' : name);
}

void _buildRug(_Mesh m, double w, double d, _Rand rng) {
  m.box(-w / 2, 0, -d / 2, w / 2, 0.02, d / 2,
      _decor[rng.nextInt(_decor.length)], _kMatMatte);
}

void _buildVase(_Mesh m, double w, double h, double d, _Rand rng) {
  final c = _decor[rng.nextInt(_decor.length)];
  final r = math.min(w, d) / 2;
  m.prism(
      sides: 8,
      r0: r,
      r1: r * 0.55,
      y0: 0,
      y1: h,
      color: _tone(c, rng.range(0.95, 1.05)),
      closeBottom: true,
      mat: _kMatGloss);
}

void _buildPlant(_Mesh m, double w, double h, double d, _Rand rng) {
  final r = math.min(w, d) / 2;
  final potC = _tone(_decor[rng.nextInt(_decor.length)], 0.85);
  final potH = _clampSafe(h * 0.22, 0.05, h * 0.4);
  m.prism(
      sides: 8,
      r0: r * 0.55,
      r1: r * 0.8,
      y0: 0,
      y1: potH,
      color: potC,
      closeBottom: true,
      closeTop: true,
      mat: _kMatGloss);
  final stemC = _tone(_wood[rng.nextInt(_wood.length)], 0.7);
  m.prism(
      sides: 6,
      r0: r * 0.12,
      r1: r * 0.1,
      y0: potH,
      y1: h * 0.92,
      color: stemC,
      mat: _kMatSatin);
  final leafC = _foliage[rng.nextInt(_foliage.length)];
  const tiers = 3;
  for (var i = 0; i < tiers; i++) {
    final y0 = potH + (h - potH) * (0.18 + 0.26 * i);
    final y1 = math.min(h, y0 + (h - potH) * 0.34);
    final taper = 1.0 - 0.22 * i;
    m.prism(
        sides: 7,
        r0: r * 0.95 * taper,
        r1: r * 0.55 * taper,
        y0: y0,
        y1: y1,
        color: _tone(leafC, 1 + rng.range(-0.08, 0.08)),
        mat: _kMatMatte);
  }
}

void _buildWallArt(_Mesh m, double w, double h, double d, _Rand rng) {
  final halfT = math.min(0.03, d) / 2;
  m.box(-w / 2, 0, -halfT, w / 2, h, halfT,
      _tone(_metal[rng.nextInt(_metal.length)], 1.0), _kMatGloss);
}

void _buildCushion(_Mesh m, double w, double h, double d, _Rand rng) {
  final hc = math.min(h, 0.15);
  m.box(-w / 2, 0, -d / 2, w / 2, hc, d / 2,
      _tone(_fabric[rng.nextInt(_fabric.length)], rng.range(0.95, 1.05)),
      _kMatMatte);
}

void _buildTable(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final topC = _tone(base, rng.range(0.96, 1.02));
  final legC = _tone(base, rng.range(0.8, 0.9));
  final topBottom = h - 0.05;
  if (topBottom <= 0.01) {
    m.box(-w / 2, 0, -d / 2, w / 2, h, d / 2, topC, _kMatSatin);
    return;
  }
  m.box(-w / 2, topBottom, -d / 2, w / 2, h, d / 2, topC,
      _kMatSatin); // top slab, 5 cm
  final insetX = w * 0.08;
  final insetZ = d * 0.08;
  for (final sx in const [-1.0, 1.0]) {
    for (final sz in const [-1.0, 1.0]) {
      final cx = sx * (w / 2 - insetX) - (sx > 0 ? 0.04 : -0.04);
      final cz = sz * (d / 2 - insetZ) - (sz > 0 ? 0.04 : -0.04);
      m.box(cx - 0.04, 0, cz - 0.04, cx + 0.04, topBottom, cz + 0.04, legC,
          _kMatSatin);
    }
  }
}

void _buildSofa(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _fabric[rng.nextInt(_fabric.length)];
  final seatH = _clampSafe(h * 0.42, h * 0.25, h * 0.5);
  final metalC = _tone(_metal[rng.nextInt(_metal.length)], 1.0);
  // Feet lift the carcass so the piece reads as furniture, not a block —
  // skipped on squat products where they would eat the whole seat.
  final footH = h >= 0.35 ? 0.05 : 0.0;
  if (footH > 0) {
    for (final sx in const [-1.0, 1.0]) {
      for (final sz in const [-1.0, 1.0]) {
        final cx = sx * (w / 2 - 0.07);
        final cz = sz * (d / 2 - 0.07);
        m.box(cx - 0.03, 0, cz - 0.03, cx + 0.03, footH, cz + 0.03, metalC,
            _kMatMetal);
      }
    }
  }
  // Seat cushions rest on the carcass and bring the seat back up to seatH.
  final cushT = math.min(0.09, math.max(0.0, seatH - footH - 0.02));
  final carcassTop = seatH - cushT;
  m.box(-w / 2, footH, -d / 2, w / 2, carcassTop, d / 2,
      _tone(base, rng.range(0.88, 0.96)), _kMatMatte);
  final cushC = _tone(base, rng.range(1.02, 1.1));
  final gap = math.min(0.03, w * 0.02);
  final cushW = (w - gap) / 2;
  for (final sx in const [-1.0, 1.0]) {
    final cx = sx * (gap / 2 + cushW / 2);
    m.box(cx - cushW / 2, carcassTop, -d / 2 + 0.02, cx + cushW / 2, seatH,
        d / 2 - 0.02, cushC, _kMatMatte);
  }
  // Backrest and arms need ≥ 8 cm above the seat; an absurdly squat product
  // degrades to the seat slab instead of crashing a clamp with lo > hi.
  final backRoom = h - seatH;
  if (backRoom < 0.08) return;
  m.box(-w / 2, seatH, -d / 2, w / 2, h, -d / 2 + 0.18,
      _tone(base, rng.range(1.0, 1.08)), _kMatMatte); // backrest (18 cm thick)
  // Back cushions lean on the backrest slab, between the arms.
  final backCushD = math.min(0.1, d * 0.18);
  final backCushH = math.min(0.42, backRoom * 0.8);
  final innerW = w - 0.36;
  if (backCushH > 0.06 && innerW > 0.5) {
    final bw = (innerW - gap) / 2;
    m.box(-w / 2 + 0.18, seatH, -d / 2 + 0.18, -w / 2 + 0.18 + bw,
        seatH + backCushH, -d / 2 + 0.18 + backCushD, cushC, _kMatMatte);
    m.box(w / 2 - 0.18 - bw, seatH, -d / 2 + 0.18, w / 2 - 0.18,
        seatH + backCushH, -d / 2 + 0.18 + backCushD, cushC, _kMatMatte);
  }
  final armTop = _clampSafe(h * 0.55, seatH + 0.03, h - 0.05);
  m.box(-w / 2, footH, -d / 2, -w / 2 + 0.18, armTop, d / 2,
      _tone(base, rng.range(0.92, 1.0)), _kMatMatte);
  m.box(w / 2 - 0.18, footH, -d / 2, w / 2, armTop, d / 2,
      _tone(base, rng.range(0.92, 1.0)), _kMatMatte);
}

void _buildChair(_Mesh m, double w, double h, double d, _Rand rng,
    {required bool armrests}) {
  final base = _fabric[rng.nextInt(_fabric.length)];
  if (h < 0.2) {
    // Legs + raised seat need h ≥ 0.2 — below that a low stool slab instead.
    final seatTop = _clampSafe(h * 0.75, 0.03, h);
    m.box(-w / 2, 0, -d / 2, w / 2, seatTop, d / 2,
        _tone(base, rng.range(0.95, 1.05)), _kMatMatte);
    final backH = h - seatTop;
    if (backH > 0.02) {
      m.box(-w / 2, seatTop, -d / 2, w / 2, h, -d / 2 + 0.06,
          _tone(base, rng.range(1.0, 1.1)), _kMatMatte);
    }
    return;
  }
  final seatTop = _clampSafe(h * 0.45, 0.1, h - 0.1);
  final legH = _clampSafe(seatTop - 0.08, 0.02, seatTop);
  final insetX = w * 0.08;
  final insetZ = d * 0.08;
  for (final sx in const [-1.0, 1.0]) {
    for (final sz in const [-1.0, 1.0]) {
      final cx = sx * (w / 2 - insetX) - (sx > 0 ? 0.025 : -0.025);
      final cz = sz * (d / 2 - insetZ) - (sz > 0 ? 0.025 : -0.025);
      m.box(cx - 0.025, 0, cz - 0.025, cx + 0.025, legH, cz + 0.025,
          _tone(base, rng.range(0.8, 0.9)), _kMatSatin);
    }
  }
  m.box(-w / 2, seatTop - 0.08, -d / 2, w / 2, seatTop, d / 2,
      _tone(base, rng.range(0.95, 1.05)), _kMatMatte);
  m.box(-w / 2, seatTop, -d / 2, w / 2, h, -d / 2 + 0.06,
      _tone(base, rng.range(1.0, 1.1)), _kMatMatte);
  if (armrests) {
    final armTop = _clampSafe(h * 0.6, seatTop + 0.02, h - 0.05);
    final armC = _tone(base, rng.range(0.9, 1.0));
    m.box(-w / 2, seatTop - 0.05, -d / 2 + 0.03, -w / 2 + 0.08, armTop,
        d / 2 - 0.03, armC, _kMatMatte);
    m.box(w / 2 - 0.08, seatTop - 0.05, -d / 2 + 0.03, w / 2, armTop,
        d / 2 - 0.03, armC, _kMatMatte);
  }
}

void _buildBed(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final frameH = math.min(0.3, h * 0.5);
  m.box(-w / 2, 0, -d / 2, w / 2, frameH, d / 2,
      _tone(base, rng.range(0.85, 0.95)), _kMatSatin);
  m.box(-w / 2, frameH, -d / 2, w / 2, h, -d / 2 + 0.1,
      _tone(base, rng.range(1.0, 1.1)),
      _kMatSatin); // headboard at the back edge
  // Bedding layers share the space between the frame top and the headboard
  // crest; each one clamps so nothing escapes the seller box.
  final room = h - frameH;
  if (room < 0.06) return;
  final fabric = _fabric[rng.nextInt(_fabric.length)];
  final mattT = math.min(0.16, math.max(0.05, room - 0.02));
  m.box(-w / 2 + 0.03, frameH, -d / 2 + 0.03, w / 2 - 0.03, frameH + mattT,
      d / 2 - 0.03, _tone(fabric, 1.06), _kMatMatte);
  // Pillows live at the head end; the duvet starts past them so the layers
  // never intersect.
  final pillowH = math.min(0.12, h - frameH - mattT);
  var duvetZ0 = -d / 2 + 0.05;
  if (pillowH > 0.03 && d > 0.9) {
    duvetZ0 = -d / 2 + 0.56;
    final pw = math.min(w * 0.38, w - 0.2);
    for (final sx in const [-1.0, 1.0]) {
      final cx = sx * w * 0.22;
      m.box(cx - pw / 2, frameH + mattT, -d / 2 + 0.12, cx + pw / 2,
          frameH + mattT + pillowH, -d / 2 + 0.54,
          _tone(fabric, 1.14), _kMatMatte);
    }
  }
  final duvetT = math.min(0.06, h - frameH - mattT);
  final duvetZ1 = d / 2 - 0.05;
  if (duvetT > 0.01 && duvetZ1 > duvetZ0 && w > 0.12) {
    m.box(-w / 2 + 0.05, frameH + mattT, duvetZ0, w / 2 - 0.05,
        frameH + mattT + duvetT, duvetZ1, _tone(fabric, 0.92), _kMatMatte);
  }
}

void _buildCabinet(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final bodyC = _tone(base, rng.range(0.92, 1.0));
  final shelfC = _tone(base, rng.range(0.6, 0.74));
  final metalC = _tone(_metal[rng.nextInt(_metal.length)], 1.0);
  m.box(-w / 2, 0, -d / 2, w / 2, h, d / 2, bodyC, _kMatSatin);
  // Top slab and a dark kick band frame the carcass; the slab overhangs the
  // front and sides only (flush at the wall side) so every proud stays inside
  // the seller box contract.
  if (h > 0.12) {
    m.box(-w / 2 - 0.004, h - 0.04, -d / 2 - 0.004, w / 2 + 0.004, h, d / 2,
        _tone(bodyC, 1.1), _kMatSatin);
    m.box(-w / 2 + 0.02, 0, -d / 2 - 0.004, w / 2 - 0.02, 0.1, -d / 2 + 0.01,
        _tone(bodyC, 0.55), _kMatMatte);
  }
  // Shelf bands proud of the front (−Z) face so they read head-on.
  final shelves = h > 1.2 ? 3 : 2;
  const bandThick = 0.025;
  for (var i = 1; i <= shelves; i++) {
    final y0 = h * i / (shelves + 1) - bandThick / 2;
    m.box(-w / 2 + 0.02, y0, -d / 2 - 0.007, w / 2 - 0.02, y0 + bandThick,
        -d / 2 + 0.01, shelfC, _kMatSatin);
  }
  // Door seams and metal handles, where there is front face to work with.
  if (w > 0.3 && h > 0.3) {
    final seams = w > 1.2 ? 2 : 1;
    for (var i = 1; i <= seams; i++) {
      final x = -w / 2 + w * i / (seams + 1);
      m.box(x - 0.012, 0.1, -d / 2 - 0.005, x + 0.012, h - 0.04, -d / 2 + 0.005,
          _tone(bodyC, 0.62), _kMatSatin);
    }
    for (var i = 0; i <= seams; i++) {
      final x = -w / 2 + w * (i + 0.5) / (seams + 1);
      m.box(x - 0.055, h * 0.55, -d / 2 - 0.007, x + 0.055, h * 0.55 + 0.025,
          -d / 2 + 0.001, metalC, _kMatMetal);
    }
  }
}

void _buildLamp(_Mesh m, double w, double h, _Rand rng) {
  final metal = _metal[rng.nextInt(_metal.length)];
  final metalC = _tone(metal, 1.0);
  final shadeC = _shadeWarm[rng.nextInt(_shadeWarm.length)];
  final rStem = math.max(0.008, math.min(0.03, 0.03 * w));
  final rBase = _clampSafe(0.1 * w, rStem * 2, 0.15);
  final baseH = _clampSafe(h * 0.04, 0.015, 0.05);
  final shadeBottomY = h * 0.6;
  m.prism(
      sides: 8,
      r0: rBase,
      r1: rBase * 0.9,
      y0: 0,
      y1: baseH,
      color: _tone(metalC, 0.85),
      closeBottom: true,
      mat: _kMatMetal);
  m.prism(
      sides: 8,
      r0: rStem,
      r1: rStem,
      y0: baseH,
      y1: shadeBottomY,
      color: metalC,
      mat: _kMatMetal);
  // Tapered shade — widest at the bottom so max width ≈ W.
  m.prism(
      sides: 8,
      r0: 0.48 * w,
      r1: 0.24 * w,
      y0: shadeBottomY,
      y1: h * 0.95,
      color: shadeC,
      mat: _kMatMatte);
}

// ─── Floor / wall generators ─────────────────────────────────────────────────

Uint8List generateFloorGlb({
  required FloorFinish finish,
  List<List<double>> holes = const [],
}) {
  final size = finish.sizeM;
  if (size <= 0) {
    throw ArgumentError.value(size, 'finish.sizeM', 'must be positive');
  }
  final base = finish.colorArgb;
  final mesh = _Mesh();
  final lo = -size / 2;
  final rng = _Rand(_nameSeed('floor:${finish.type.name}:$base'));
  // Flat [x0, z0, …] outlines (finish-local XZ) → polygons for the cut test.
  final polys = <List<Vector3>>[];
  for (final flat in holes) {
    if (flat.length < 6 || flat.length.isOdd) continue;
    polys.add([
      for (var i = 0; i < flat.length; i += 2) Vector3(flat[i], 0, flat[i + 1]),
    ]);
  }
  var cuts = 0;
  bool blocked(double x0, double z0, double x1, double z1) {
    final hit = rectHitsPolygons(
      center: Vector3((x0 + x1) / 2, 0, (z0 + z1) / 2),
      yaw: 0,
      widthM: x1 - x0,
      depthM: z1 - z0,
      polygons: polys,
      clearanceM: 0.05,
    );
    if (hit) cuts++;
    return hit;
  }

  switch (finish.type) {
    case FloorFinishType.woodPlanks:
      _floorWoodPlanks(mesh, base, lo, size, rng, blocked);
    case FloorFinishType.cement:
      _floorCement(mesh, base, lo, size, rng, blocked);
    case FloorFinishType.ceramicTiles:
      _floorTiles(mesh, base, lo, size, rng, blocked);
    case FloorFinishType.parquet:
      _floorParquet(mesh, base, lo, size, rng, blocked);
  }
  final slab = _tone(base, 0.72);
  if (cuts == 0) {
    mesh.box(lo, -0.01, lo, -lo, 0, -lo, slab);
  } else {
    // Sides only — a top/bottom face would show through the cut-outs
    // instead of the real floor.
    mesh.quad(_Vec3(lo, -0.01, lo), _Vec3(-lo, -0.01, lo), _Vec3(-lo, 0, lo),
        _Vec3(lo, 0, lo), const _Vec3(0, 0, 1), slab);
    mesh.quad(_Vec3(-lo, -0.01, -lo), _Vec3(lo, -0.01, -lo), _Vec3(lo, 0, -lo),
        _Vec3(-lo, 0, -lo), const _Vec3(0, 0, -1), slab);
    mesh.quad(_Vec3(lo, -0.01, -lo), _Vec3(lo, -0.01, lo), _Vec3(lo, 0, lo),
        _Vec3(lo, 0, -lo), const _Vec3(-1, 0, 0), slab);
    mesh.quad(_Vec3(-lo, -0.01, lo), _Vec3(-lo, -0.01, -lo), _Vec3(-lo, 0, -lo),
        _Vec3(-lo, 0, lo), const _Vec3(1, 0, 0), slab);
  }
  return mesh.buildGlb('floor_${finish.type.name}');
}

// Pattern quads float 1 mm above the slab top (y=0) and detail quads 2 mm —
// coplanar layers at the exact same y z-fight in the depth buffer and the
// finish flickers ("pixel shaking") as the camera moves.
void _floorQuad(_Mesh m, double x0, double z0, double x1, double z1, int color,
    [double y = 0.001]) {
  m.quad(_Vec3(x0, y, z0), _Vec3(x1, y, z0), _Vec3(x1, y, z1),
      _Vec3(x0, y, z1), const _Vec3(0, 1, 0), color);
}

void _walkGrid(
    double size, double cell, void Function(double x0, double z0, double x1, double z1) cellFn) {
  final lo = -size / 2;
  for (var z = lo; z < -lo - 1e-9; z += cell) {
    final z1 = math.min(z + cell, -lo);
    for (var x = lo; x < -lo - 1e-9; x += cell) {
      final x1 = math.min(x + cell, -lo);
      cellFn(x, z, x1, z1);
    }
  }
}

// Pattern bodies emit through this so a caller can clip/skip each quad
// (the room shell clips to the ring); plain floors pass nothing and get the
// default y tiers unchanged.
typedef _FloorEmit = void Function(double x0, double z0, double x1, double z1,
    int color, [double y]);

_FloorEmit _bindFloorEmit(_Mesh m, _FloorEmit? emit) =>
    emit ??
    ((x0, z0, x1, z1, c, [y = 0.001]) => _floorQuad(m, x0, z0, x1, z1, c, y));

void _floorWoodPlanks(_Mesh m, int base, double lo, double size, _Rand rng,
    bool Function(double, double, double, double) blocked,
    [_FloorEmit? emit]) {
  final e = _bindFloorEmit(m, emit);
  const plankW = 0.12;
  const grainLine = 0.003;
  final darkGrain = _tone(base, 0.82);
  final lightGrain = _tone(base, 1.08);
  var z = lo;
  while (z < -lo - 1e-9) {
    final z1 = math.min(z + plankW, -lo);
    var x = lo;
    var first = true;
    while (x < -lo - 1e-9) {
      final len = first ? rng.range(0.4, 1.0) : rng.range(0.9, 1.5);
      final x1 = math.min(x + len, -lo);
      if (x1 > x + 1e-6 && !blocked(x, z, x1, z1)) {
        final plankBase = _tone(base, 1 + rng.range(-0.08, 0.08));
        e(x, z, x1, z1, plankBase);
        final grainCount = (plankW / 0.025).floor();
        for (var g = 0; g < grainCount; g++) {
          final gz = z + g * 0.025 + rng.range(0.002, 0.008);
          if (gz + grainLine < z1) {
            final gc = g.isEven ? darkGrain : lightGrain;
            e(x, gz, x1, gz + grainLine, gc, 0.002);
          }
        }
        if (x1 < -lo - 0.01) {
          e(x1 - grainLine, z, x1, z1, _tone(base, 0.6), 0.002);
        }
        // Row seam drawn per plank so a cut cell leaves the seam open too.
        e(x, z1 - grainLine, x1, z1, _tone(base, 0.55), 0.002);
      }
      if (x1 >= -lo - 1e-9) break;
      x = x1;
      first = false;
    }
    z = z1;
  }
}

void _floorCement(_Mesh m, int base, double lo, double size, _Rand rng,
    bool Function(double, double, double, double) blocked,
    [_FloorEmit? emit]) {
  final e = _bindFloorEmit(m, emit);
  final crackColor = _tone(base, 0.75);
  _walkGrid(size, 0.4, (x0, z0, x1, z1) {
    if (blocked(x0, z0, x1, z1)) return;
    e(x0, z0, x1, z1, _tone(base, 1 + rng.range(-0.04, 0.04)));
    if (rng.nextDouble() < 0.3) {
      final cx = x0 + rng.range(0.05, 0.35);
      final cz = z0 + rng.range(0.05, 0.35);
      final dx = rng.range(-0.15, 0.15);
      final dz = rng.range(-0.15, 0.15);
      e(cx - 0.002, cz, cx + dx + 0.002, cz + dz, crackColor, 0.002);
    }
  });
}

void _floorTiles(_Mesh m, int base, double lo, double size, _Rand rng,
    bool Function(double, double, double, double) blocked,
    [_FloorEmit? emit]) {
  final e = _bindFloorEmit(m, emit);
  const tile = 0.5;
  const inset = 0.015;
  final grout = _mix(base, _kGrey, 0.6);
  final groutDark = _mix(base, _kGrey, 0.7);
  _walkGrid(size, tile, (x0, z0, x1, z1) {
    if (blocked(x0, z0, x1, z1)) return;
    final tileColor = _tone(base, 1 + rng.range(-0.05, 0.05));
    e(x0 + inset, z0 + inset, x1 - inset, z1 - inset, tileColor);
    final cx = (x0 + x1) / 2;
    final cz = (z0 + z1) / 2;
    final hs = (x1 - x0 - inset * 2) * 0.3;
    if (hs > 0.01) {
      e(cx - hs, cz - hs, cx + hs, cz + hs, _tone(tileColor, 1.04), 0.002);
    }
    e(x0, z0, x0 + inset, z1, groutDark);
    e(x1 - inset, z0, x1, z1, groutDark);
    e(x0 + inset, z0, x1 - inset, z0 + inset, grout);
    e(x0 + inset, z1 - inset, x1 - inset, z1, grout);
    e(x0, z0, x0 + inset, z0 + inset, groutDark, 0.002);
    e(x1 - inset, z0, x1, z0 + inset, groutDark, 0.002);
    e(x0, z1 - inset, x0 + inset, z1, groutDark, 0.002);
    e(x1 - inset, z1 - inset, x1, z1, groutDark, 0.002);
  });
}

void _floorParquet(_Mesh m, int base, double lo, double size, _Rand rng,
    bool Function(double, double, double, double) blocked,
    [_FloorEmit? emit]) {
  final e = _bindFloorEmit(m, emit);
  const blockW = 0.06;
  const blockH = 0.18;
  const gap = 0.002;
  final darkJoint = _tone(base, 0.6);
  var row = 0;
  for (var z = lo; z < -lo - 1e-9; z += blockW + gap) {
    final z1 = math.min(z + blockW, -lo);
    final offset = (row % 2 == 0) ? 0.0 : blockH / 2;
    for (var x = lo + offset; x < -lo - 1e-9; x += blockH + gap) {
      final x1 = math.min(x + blockH, -lo);
      if (x1 > x + 1e-6 && z1 > z + 1e-6 && !blocked(x, z, x1, z1)) {
        final even = ((x - lo) / (blockH + gap)).floor().isEven;
        final p = 1 + rng.range(-0.06, 0.06);
        e(x, z, x1, z1, _tone(base, p));
        if (even) {
          final midZ = (z + z1) / 2;
          e(x, midZ - 0.001, x1, midZ + 0.001, _tone(base, 0.85), 0.002);
        } else {
          final midX = (x + x1) / 2;
          e(midX - 0.001, z, midX + 0.001, z1, _tone(base, 0.85), 0.002);
        }
      }
    }
    if (z1 < -lo - 0.01) {
      // Row joint segmented across the full width so cut cells (and the
      // odd-row offset head) stay open.
      for (var jx = lo; jx < -lo - 1e-9; jx += blockH + gap) {
        final jx1 = math.min(jx + blockH + gap, -lo);
        if (jx1 <= jx + 1e-6) break;
        if (blocked(jx, z, jx1, z1)) continue;
        e(jx, z1 - gap, jx1, z1, darkJoint, 0.002);
      }
    }
    row++;
  }
}

typedef _WallQuadEmit = void Function(
    double x0, double y0, double x1, double y1, int color,
    [int detail]);

// Wall-face pattern shared by the finish panel (generateWallGlb) and the
// room shell's per-segment inner faces. Local x spans [−widthM/2, widthM/2],
// y spans [0, heightM]; the caller's quad callback places it in the world.
// detail 0 = base pattern tier, 1 = finer tier (seams/grain) that must sit
// a millimetre proud of it or the finish z-fights while the camera moves.
void _wallFacePattern(_WallQuadEmit wallQuad, WallFinish finish, double widthM,
    double heightM, _Rand rng) {
  final base = finish.colorArgb;
  final loX = -widthM / 2;
  switch (finish.type) {
    case WallFinishType.paint:
      for (var x = loX; x < -loX - 1e-9; x += 0.48) {
        final x1 = math.min(x + 0.48, -loX);
        for (var y = 0.0; y < heightM - 1e-9; y += 0.54) {
          final y1 = math.min(y + 0.54, heightM);
          wallQuad(x, y, x1, y1, _tone(base, 1 + rng.range(-0.015, 0.015)));
        }
      }
      break;
    case WallFinishType.woodPanels:
      const panelW = 0.18, seam = 0.008;
      final darkSeam = _tone(base, 0.35);
      final grainDark = _tone(base, 0.8);
      final grainLight = _tone(base, 1.1);
      for (var x = loX; x < -loX - 1e-9; x += panelW) {
        final x1 = math.min(x + panelW, -loX);
        if (x1 <= x + 1e-6) continue;
        final panelColor = _tone(base, 1 + rng.range(-0.08, 0.08));
        wallQuad(x + seam / 2, 0, x1 - seam / 2, heightM, panelColor);
        wallQuad(x, 0, x + seam, heightM, darkSeam, 1);
        final grainCount = (heightM / 0.04).floor();
        for (var g = 0; g < grainCount; g++) {
          final gy = g * 0.04 + rng.range(0.005, 0.015);
          if (gy + 0.002 < heightM) {
            final gc = g.isEven ? grainDark : grainLight;
            wallQuad(x + seam / 2, gy, x1 - seam / 2, gy + 0.002, gc, 1);
          }
        }
        if (rng.nextDouble() < 0.2) {
          final ky = rng.range(0.3, heightM - 0.3);
          final kx = (x + x1) / 2;
          final kr = 0.02;
          wallQuad(kx - kr, ky - kr, kx + kr, ky + kr, _tone(base, 0.7), 1);
        }
      }
      break;
    case WallFinishType.brick:
      _wallBrick(wallQuad, base, loX, heightM, rng);
      break;
  }
}

Uint8List generateWallGlb({
  required WallFinish finish,
  double widthM = RoomFinishCatalog.wallWidthM,
  double heightM = RoomFinishCatalog.wallHeightM,
}) {
  if (widthM <= 0 || heightM <= 0) {
    throw ArgumentError.value(
      [widthM, heightM],
      'wall size',
      'generateWallGlb requires positive widthM/heightM '
          '(got $widthM × $heightM m).',
    );
  }
  const halfD = 0.025;
  final base = finish.colorArgb;
  final mesh = _Mesh();
  final loX = -widthM / 2;
  final rng = _Rand(_nameSeed('wall:${finish.type.name}:$base'));
  final underC = switch (finish.type) {
    WallFinishType.paint => base,
    WallFinishType.woodPanels => _tone(base, 0.45),
    WallFinishType.brick => _mix(_tone(base, 0.5), _kGrey, 0.45),
  };
  mesh.box(loX, 0, -halfD, -loX, heightM, halfD, underC);
  // Pattern floats 1 mm in front of the box face, detail quads 2 mm —
  // coplanar layers z-fight and the finish flickers as the camera moves.
  final frontZ = halfD + 0.001;

  void wallQuad(double x0, double y0, double x1, double y1, int color,
      [int detail = 0]) {
    if (x1 <= x0 || y1 <= y0) return;
    final zz = detail == 0 ? frontZ : frontZ + 0.001;
    mesh.quad(_Vec3(x0, y0, zz), _Vec3(x1, y0, zz),
        _Vec3(x1, y1, zz), _Vec3(x0, y1, zz),
        const _Vec3(0, 0, 1), color);
  }

  _wallFacePattern(wallQuad, finish, widthM, heightM, rng);
  return mesh.buildGlb('wall_${finish.type.name}');
}

void _wallBrick(_WallQuadEmit quad, int base, double loX, double wallH,
    _Rand rng) {
  const rowCount = 34;
  final rowH = wallH / rowCount;
  const colW = 0.25;
  const mortar = 0.008;
  for (var row = 0; row < rowCount; row++) {
    final y0 = row * rowH + (row == 0 ? 0 : mortar / 2);
    final y1 = row == rowCount - 1 ? wallH : (row + 1) * rowH - mortar / 2;
    final stagger = (row.isEven ? 0.0 : colW / 2);
    var xStart = loX + stagger;
    if (xStart > loX + 1e-9) {
      quad(loX, y0, xStart - mortar / 2, y1,
          _tone(base, 1 + rng.range(-0.08, 0.08)));
    }
    for (var x = xStart; x < -loX - 1e-9; x += colW) {
      final x0 = x + mortar / 2;
      final x1 = math.min(x + colW, -loX) - mortar / 2;
      if (x1 > x0) {
        quad(x0, y0, x1, y1, _tone(base, 1 + rng.range(-0.08, 0.08)));
      }
    }
  }
}

// ─── Room shell generator ──────────────────────────────────────────────────

// Plan cm → scene meters: plan (x, y) → world (x/100, h, y/100). The shell
// is emitted in plan coordinates so furniture placed at plan-meters lands
// inside it without extra offsets.
double _cmToM(double cm) => cm / 100.0;

Offset _dir2(Offset v) {
  final len = v.distance;
  return len == 0 ? Offset.zero : v / len;
}

Uint8List generateRoomShellGlb({
  required ShellGeometry shell,
  required FloorFinish floor,
  required WallFinish wall,
  List<bool>? cutMask,
  List<DraftWall> draftWalls = const [],
}) {
  if (shell.floorTriangles.isEmpty) {
    throw ArgumentError.value(
      shell.ringCm.length,
      'shell.ringCm',
      'generateRoomShellGlb requires a closed ring of at least 3 corners',
    );
  }
  final mesh = _Mesh();
  final wallH = _cmToM(shell.wallHeightCm);
  final cutH = _cmToM(kShellCutawayHeightCm);
  final floorBase = floor.colorArgb;
  final wallBase = wall.colorArgb;
  final floorMat = switch (floor.type) {
    FloorFinishType.woodPlanks => _kMatSatin,
    FloorFinishType.parquet => _kMatSatin,
    FloorFinishType.ceramicTiles => _kMatGloss,
    FloorFinishType.cement => _kMatMatte,
  };
  final wallMat =
      wall.type == WallFinishType.woodPanels ? _kMatSatin : _kMatMatte;
  final rng = _Rand(_nameSeed(
      'shell:${floor.type.name}:${wall.type.name}:$floorBase:$wallBase'));

  // ── floor ──
  // Exact ear-clipped triangles under the pattern layer: any micro-gap the
  // per-cell clip leaves at the wall line shows base color, never sky.
  final floorUnder = _tone(floorBase, 0.9);
  for (final tri in shell.floorTriangles) {
    mesh._tri(
        _Vec3(_cmToM(tri[0].dx), 0, _cmToM(tri[0].dy)),
        _Vec3(_cmToM(tri[1].dx), 0, _cmToM(tri[1].dy)),
        _Vec3(_cmToM(tri[2].dx), 0, _cmToM(tri[2].dy)),
        const _Vec3(0, 1, 0),
        floorUnder,
        floorMat);
  }

  final bounds = shell.boundsCm;
  final minX = _cmToM(bounds.left), maxX = _cmToM(bounds.right);
  final minZ = _cmToM(bounds.top), maxZ = _cmToM(bounds.bottom);
  final cx = (minX + maxX) / 2;
  final cz = (minZ + maxZ) / 2;
  final size = math.max(maxX - minX, maxZ - minZ) + 0.6;
  final ringM = <Offset>[
    for (final p in shell.ringCm) Offset(_cmToM(p.dx), _cmToM(p.dy)),
  ];
  // Pattern walks a centered frame; every quad is translated back to plan
  // coordinates and clipped to the room ring so nothing floats outside.
  void shellEmit(double x0, double z0, double x1, double z1, int color,
      [double y = 0.001]) {
    _emitFloorRectClipped(
        mesh, x0 + cx, z0 + cz, x1 + cx, z1 + cz, ringM, color, y, floorMat);
  }

  bool noHoles(double x0, double z0, double x1, double z1) => false;
  final lo = -size / 2;
  switch (floor.type) {
    case FloorFinishType.woodPlanks:
      _floorWoodPlanks(mesh, floorBase, lo, size, rng, noHoles, shellEmit);
    case FloorFinishType.cement:
      _floorCement(mesh, floorBase, lo, size, rng, noHoles, shellEmit);
    case FloorFinishType.ceramicTiles:
      _floorTiles(mesh, floorBase, lo, size, rng, noHoles, shellEmit);
    case FloorFinishType.parquet:
      _floorParquet(mesh, floorBase, lo, size, rng, noHoles, shellEmit);
  }

  // ── walls ──
  // Inner face (pattern 1–2 mm proud into the room), flat outer face and a
  // top cap visible from the open ceiling. End caps are skipped — the outer
  // ring miter-joins, so runs meet watertight. A cut segment runs only to the
  // dollhouse height, so the orbit view sees over it into the room.
  for (var si = 0; si < shell.wallSegments.length; si++) {
    final seg = shell.wallSegments[si];
    final segH = (cutMask != null && si < cutMask.length && cutMask[si])
        ? cutH
        : wallH;
    final a = Offset(_cmToM(seg.a.dx), _cmToM(seg.a.dy));
    final b = Offset(_cmToM(seg.b.dx), _cmToM(seg.b.dy));
    final oa = Offset(_cmToM(seg.outerA.dx), _cmToM(seg.outerA.dy));
    final ob = Offset(_cmToM(seg.outerB.dx), _cmToM(seg.outerB.dy));
    final inDir = _dir2(Offset(-seg.outward.dx, -seg.outward.dy));
    final outDir = _dir2(seg.outward);
    final inN = _Vec3(inDir.dx, 0, inDir.dy);
    final len = (b - a).distance;

    mesh.quad(_Vec3(a.dx, 0, a.dy), _Vec3(b.dx, 0, b.dy),
        _Vec3(b.dx, segH, b.dy), _Vec3(a.dx, segH, a.dy), inN, wallBase,
        wallMat);
    if (len > 1e-6) {
      final dir = (b - a) / len;
      final segRng = _Rand(_nameSeed(
          'wallrun:${seg.a.dx}:${seg.a.dy}:${seg.b.dx}:${seg.b.dy}:$wallBase'));
      void wallQuad(double x0, double y0, double x1, double y1, int color,
          [int detail = 0]) {
        if (x1 <= x0 || y1 <= y0) return;
        // Local x is centered on the run (same frame as the pattern
        // helpers); tiers float 1–2 mm off the inner face.
        final proud = detail == 0 ? 0.001 : 0.002;
        Offset at(double x) => Offset(
            a.dx + dir.dx * (x + len / 2) + inDir.dx * proud,
            a.dy + dir.dy * (x + len / 2) + inDir.dy * proud);
        final p0 = at(x0), p1 = at(x1);
        mesh.quad(_Vec3(p0.dx, y0, p0.dy), _Vec3(p1.dx, y0, p1.dy),
            _Vec3(p1.dx, y1, p1.dy), _Vec3(p0.dx, y1, p0.dy), inN, color,
            wallMat);
      }

      _wallFacePattern(wallQuad, wall, len, segH, segRng);
    }
    mesh.quad(
        _Vec3(oa.dx, 0, oa.dy),
        _Vec3(ob.dx, 0, ob.dy),
        _Vec3(ob.dx, segH, ob.dy),
        _Vec3(oa.dx, segH, oa.dy),
        _Vec3(outDir.dx, 0, outDir.dy),
        _tone(wallBase, 0.82),
        wallMat);
    mesh.quad(
        _Vec3(a.dx, segH, a.dy),
        _Vec3(b.dx, segH, b.dy),
        _Vec3(ob.dx, segH, ob.dy),
        _Vec3(oa.dx, segH, oa.dy),
        const _Vec3(0, 1, 0),
        _tone(wallBase, 1.08),
        wallMat);
  }

  // ── baseboards ──
  // Trim is the one satin accent on an otherwise painted shell.
  final bbH = _cmToM(shell.baseboardHeightCm);
  final bbC = _tone(wallBase, 0.78);
  for (final q in shell.baseboardPlanQuads) {
    final a = Offset(_cmToM(q[0].dx), _cmToM(q[0].dy));
    final b = Offset(_cmToM(q[1].dx), _cmToM(q[1].dy));
    final ib = Offset(_cmToM(q[2].dx), _cmToM(q[2].dy));
    final ia = Offset(_cmToM(q[3].dx), _cmToM(q[3].dy));
    final inDir = _dir2(ia - a);
    mesh.quad(_Vec3(ia.dx, 0, ia.dy), _Vec3(ib.dx, 0, ib.dy),
        _Vec3(ib.dx, bbH, ib.dy), _Vec3(ia.dx, bbH, ia.dy),
        _Vec3(inDir.dx, 0, inDir.dy), bbC, _kMatSatin);
    mesh.quad(_Vec3(a.dx, bbH, a.dy), _Vec3(b.dx, bbH, b.dy),
        _Vec3(ib.dx, bbH, ib.dy), _Vec3(ia.dx, bbH, ia.dy),
        const _Vec3(0, 1, 0), _tone(bbC, 1.06), _kMatSatin);
  }

  // ── draft walls ──
  // A part-drawn outline (1–2 corners) still shows real walls: each run is
  // a solid 10 cm slab centered on its line, a lone corner a square post.
  for (final d in draftWalls) {
    _emitDraftWall(mesh, d, d.cut ? cutH : wallH, wallBase, wallMat,
        _cmToM(shell.wallThicknessCm));
  }

  return mesh.buildGlb('room_shell');
}

class DraftWall {
  const DraftWall(this.aCm, this.bCm, {this.cut = false});

  final Offset aCm;
  final Offset bCm;

  // Dollhouse height: the run stands between the planner camera and the
  // room.
  final bool cut;
}

void _emitDraftWall(_Mesh mesh, DraftWall d, double h, int base, int mat,
    double t) {
  final a = Offset(_cmToM(d.aCm.dx), _cmToM(d.aCm.dy));
  final b = Offset(_cmToM(d.bCm.dx), _cmToM(d.bCm.dy));
  final len = (b - a).distance;
  final dir = len < 1e-6 ? const Offset(1, 0) : (b - a) / len;
  final n = Offset(-dir.dy, dir.dx);
  final half = t / 2;
  // End caps extend half a thickness so consecutive runs overlap into a
  // solid corner.
  final a0 = a - dir * half;
  final b0 = b + dir * half;
  final c = [
    a0 + n * half,
    b0 + n * half,
    b0 - n * half,
    a0 - n * half,
  ];
  _Vec3 lo(Offset p) => _Vec3(p.dx, 0, p.dy);
  _Vec3 hi(Offset p) => _Vec3(p.dx, h, p.dy);
  for (var i = 0; i < 4; i++) {
    final p = c[i];
    final q = c[(i + 1) % 4];
    final e = q - p;
    final el = e.distance;
    if (el < 1e-9) continue;
    final out = Offset(e.dy / el, -e.dx / el);
    final mid = (p + q) / 2;
    final centre = (a + b) / 2;
    final flip = (mid - centre).dx * out.dx + (mid - centre).dy * out.dy < 0;
    final nn = flip ? Offset(-out.dx, -out.dy) : out;
    mesh.quad(lo(p), lo(q), hi(q), hi(p), _Vec3(nn.dx, 0, nn.dy),
        _tone(base, i.isEven ? 1.0 : 0.9), mat);
  }
  mesh.quad(hi(c[0]), hi(c[1]), hi(c[2]), hi(c[3]), const _Vec3(0, 1, 0),
      _tone(base, 1.08), mat);
}

// First-person ceiling: the floor ring lifted to wall height, facing down.
// A separate node so it can opt out of shadow casting.
Uint8List generateRoomCeilingGlb({
  required ShellGeometry shell,
  required WallFinish wall,
}) {
  if (shell.floorTriangles.isEmpty) {
    throw ArgumentError.value(shell.ringCm.length, 'shell.ringCm',
        'generateRoomCeilingGlb requires a closed ring of at least 3 corners');
  }
  final mesh = _Mesh();
  final h = _cmToM(shell.wallHeightCm);
  // Ceilings read soft warm white whatever the wall paint; unlit, so the
  // tone shows as authored instead of the IBL's dim underside.
  final color = _tone(0xFFE9E5DE, 1.0);
  for (final tri in shell.outerFloorTriangles) {
    mesh._tri(
        _Vec3(_cmToM(tri[0].dx), h, _cmToM(tri[0].dy)),
        _Vec3(_cmToM(tri[1].dx), h, _cmToM(tri[1].dy)),
        _Vec3(_cmToM(tri[2].dx), h, _cmToM(tri[2].dy)),
        const _Vec3(0, -1, 0),
        color,
        _kMatUnlit);
  }
  return mesh.buildGlb('room_ceiling');
}

void _emitFloorRectClipped(_Mesh m, double x0, double z0, double x1, double z1,
    List<Offset> ringM, int color, double y, [int mat = 0]) {
  const up = _Vec3(0, 1, 0);
  final corners = <Offset>[
    Offset(x0, z0),
    Offset(x1, z0),
    Offset(x1, z1),
    Offset(x0, z1),
  ];
  var allIn = true;
  for (final c in corners) {
    if (!_insideRing(c, ringM)) {
      allIn = false;
      break;
    }
  }
  if (allIn && !_rectCrossesRing(x0, z0, x1, z1, ringM)) {
    m.quad(_Vec3(x0, y, z0), _Vec3(x1, y, z0), _Vec3(x1, y, z1),
        _Vec3(x0, y, z1), up, color, mat);
    return;
  }
  // Boundary cell: fan the rect∩ring intersection around its centroid.
  final pts = <Offset>[];
  for (final c in corners) {
    if (_insideRing(c, ringM)) pts.add(c);
  }
  for (final r in ringM) {
    if (r.dx > x0 && r.dx < x1 && r.dy > z0 && r.dy < z1) pts.add(r);
  }
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    for (var j = 0; j < ringM.length; j++) {
      final hit = _segIntersect2(a, b, ringM[j], ringM[(j + 1) % ringM.length]);
      if (hit != null) pts.add(hit);
    }
  }
  final uniq = <Offset>[];
  for (final p in pts) {
    var dup = false;
    for (final u in uniq) {
      if ((u - p).distance < 1e-4) {
        dup = true;
        break;
      }
    }
    if (!dup) uniq.add(p);
  }
  if (uniq.length < 3) return;
  var mx = 0.0, mz = 0.0;
  for (final p in uniq) {
    mx += p.dx;
    mz += p.dy;
  }
  final mid = Offset(mx / uniq.length, mz / uniq.length);
  final ordered = List<Offset>.of(uniq)
    ..sort((p, q) => math
        .atan2(p.dy - mid.dy, p.dx - mid.dx)
        .compareTo(math.atan2(q.dy - mid.dy, q.dx - mid.dx)));
  for (var i = 0; i < ordered.length; i++) {
    final a = ordered[i];
    final b = ordered[(i + 1) % ordered.length];
    m._tri(_Vec3(mid.dx, y, mid.dy), _Vec3(a.dx, y, a.dy), _Vec3(b.dx, y, b.dy),
        up, color, mat);
  }
}

// Strict even-odd test — room_fit.pointInPolygon blurs 0.5 cm around walls
// for the planner, which is 50 cm in these meter coordinates and would leak
// pattern outside the shell.
bool _insideRing(Offset p, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

bool _rectCrossesRing(double x0, double z0, double x1, double z1,
    List<Offset> ringM) {
  final corners = <Offset>[
    Offset(x0, z0),
    Offset(x1, z0),
    Offset(x1, z1),
    Offset(x0, z1),
  ];
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    for (var j = 0; j < ringM.length; j++) {
      if (_segIntersect2(a, b, ringM[j], ringM[(j + 1) % ringM.length]) !=
          null) {
        return true;
      }
    }
  }
  return false;
}

Offset? _segIntersect2(Offset a, Offset b, Offset c, Offset d) {
  final r = b - a;
  final s = d - c;
  final denom = r.dx * s.dy - r.dy * s.dx;
  if (denom.abs() < 1e-12) return null;
  final t = ((c.dx - a.dx) * s.dy - (c.dy - a.dy) * s.dx) / denom;
  final u = ((c.dx - a.dx) * r.dy - (c.dy - a.dy) * r.dx) / denom;
  if (t < -1e-9 || t > 1 + 1e-9 || u < -1e-9 || u > 1 + 1e-9) return null;
  return a + r * t;
}

// ─── GLB serialization ───────────────────────────────────────────────────────

// PBR response per material group (see _Mesh._mats). Vertex colors carry the
// palette; these carry the sheen, so furniture reads as a physical toy model
// instead of one flat matte.
const int _kMatMatte = 0;
const int _kMatSatin = 1;
const int _kMatMetal = 2;
const int _kMatGloss = 3;
// Emitted only when a mesh uses it (KHR_materials_unlit) — the walkthrough
// ceiling faces away from the key light and read as a dull grey slab lit.
const int _kMatUnlit = 4;

const List<Map<String, dynamic>> _kMaterials = [
  {'name': 'matte', 'metallicFactor': 0.0, 'roughnessFactor': 0.92},
  {'name': 'satin', 'metallicFactor': 0.0, 'roughnessFactor': 0.55},
  {'name': 'metal', 'metallicFactor': 0.85, 'roughnessFactor': 0.38},
  {'name': 'gloss', 'metallicFactor': 0.0, 'roughnessFactor': 0.22},
];

Uint8List _buildGlb(_Mesh mesh, String nodeName) {
  final vCount = mesh.vertexCount;
  final iCount = mesh.indexCount;
  if (vCount == 0 || iCount == 0) {
    throw StateError('Cannot serialize an empty mesh.');
  }
  final use32 = vCount >= 0xFFFF;
  const vertexStride = 36;
  final vertexBytes = vCount * vertexStride;
  final indexBytes = iCount * (use32 ? 4 : 2);
  final bin = ByteData(vertexBytes + indexBytes);

  // ── Interleave positions / normals / colors ─────────────────────────────
  var o = 0;
  for (var v = 0; v < vCount; v++) {
    final p3 = v * 3;
    bin.setFloat32(o, mesh._positions[p3], Endian.little);
    bin.setFloat32(o + 4, mesh._positions[p3 + 1], Endian.little);
    bin.setFloat32(o + 8, mesh._positions[p3 + 2], Endian.little);
    bin.setFloat32(o + 12, mesh._normals[p3], Endian.little);
    bin.setFloat32(o + 16, mesh._normals[p3 + 1], Endian.little);
    bin.setFloat32(o + 20, mesh._normals[p3 + 2], Endian.little);
    bin.setFloat32(o + 24, mesh._colors[p3], Endian.little);
    bin.setFloat32(o + 28, mesh._colors[p3 + 1], Endian.little);
    bin.setFloat32(o + 32, mesh._colors[p3 + 2], Endian.little);
    o += vertexStride;
  }
  // One primitive per used material: indices are written grouped by the
  // triangle's material so each primitive owns a contiguous index range.
  final groups = <int, List<int>>{};
  for (var t = 0; t < mesh._mats.length; t++) {
    final base = t * 3;
    groups.putIfAbsent(mesh._mats[t], () => <int>[]).addAll([
      mesh._indices[base],
      mesh._indices[base + 1],
      mesh._indices[base + 2],
    ]);
  }
  final usedMats = groups.keys.toList()..sort();
  final groupOffsets = <int>[];
  final groupCounts = <int>[];
  for (final mat in usedMats) {
    final idxs = groups[mat]!;
    // Accessor byteOffset is relative to bufferView 1, which already starts
    // at vertexBytes — the absolute write cursor would double-count it and
    // point every loader past the end of the buffer.
    groupOffsets.add(o - vertexBytes);
    groupCounts.add(idxs.length);
    for (final idx in idxs) {
      if (use32) {
        bin.setUint32(o, idx, Endian.little);
        o += 4;
      } else {
        bin.setUint16(o, idx, Endian.little);
        o += 2;
      }
    }
  }

  // ── POSITION min/max scanned from the exact float32 payload ─────────────
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = double.negativeInfinity,
      maxY = double.negativeInfinity,
      maxZ = double.negativeInfinity;
  for (var v = 0; v < vCount; v++) {
    final at = v * vertexStride;
    final x = bin.getFloat32(at, Endian.little);
    final y = bin.getFloat32(at + 4, Endian.little);
    final z = bin.getFloat32(at + 8, Endian.little);
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  // ── JSON chunk ───────────────────────────────────────────────────────────
  final usesUnlit = usedMats.contains(_kMatUnlit);
  final json = <String, dynamic>{
    'asset': {
      'version': '2.0',
      'generator': 'interior_design_recommendation/glb_generator.dart',
    },
    if (usesUnlit) 'extensionsUsed': ['KHR_materials_unlit'],
    'scene': 0,
    'scenes': [
      {
        'nodes': [0]
      }
    ],
    'nodes': [
      {
        'mesh': 0,
        'name': nodeName,
      }
    ],
    'meshes': [
      {
        'name': nodeName,
        'primitives': [
          for (var gi = 0; gi < usedMats.length; gi++)
            {
              'attributes': {'POSITION': 0, 'NORMAL': 1, 'COLOR_0': 2},
              'indices': 3 + gi,
              'material': usedMats[gi],
            }
        ],
      }
    ],
    'materials': [
      for (final spec in _kMaterials)
        {
          'name': spec['name'],
          'pbrMetallicRoughness': {
            'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
            'metallicFactor': spec['metallicFactor'],
            'roughnessFactor': spec['roughnessFactor'],
          },
          'doubleSided': true,
        },
      if (usesUnlit)
        {
          'name': 'unlit',
          'pbrMetallicRoughness': {
            'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
            'metallicFactor': 0.0,
            'roughnessFactor': 1.0,
          },
          'extensions': {'KHR_materials_unlit': <String, dynamic>{}},
          'doubleSided': true,
        },
    ],
    'buffers': [
      {'byteLength': vertexBytes + indexBytes}
    ],
    'bufferViews': [
      {
        'buffer': 0,
        'byteOffset': 0,
        'byteLength': vertexBytes,
        'byteStride': vertexStride,
      },
      {
        'buffer': 0,
        'byteOffset': vertexBytes,
        'byteLength': indexBytes,
      },
    ],
    'accessors': [
      {
        'bufferView': 0,
        'byteOffset': 0,
        'componentType': _kComponentFloat,
        'count': vCount,
        'type': 'VEC3',
        'min': [minX, minY, minZ],
        'max': [maxX, maxY, maxZ],
      },
      {
        'bufferView': 0,
        'byteOffset': 12,
        'componentType': _kComponentFloat,
        'count': vCount,
        'type': 'VEC3',
      },
      {
        'bufferView': 0,
        'byteOffset': 24,
        'componentType': _kComponentFloat,
        'count': vCount,
        'type': 'VEC3',
      },
      for (var gi = 0; gi < usedMats.length; gi++)
        {
          'bufferView': 1,
          'byteOffset': groupOffsets[gi],
          'componentType': use32 ? _kComponentUint32 : _kComponentUint16,
          'count': groupCounts[gi],
          'type': 'SCALAR',
        },
    ],
  };
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonPadded = (jsonBytes.length + 3) & ~3;
  final binPadded = (bin.lengthInBytes + 3) & ~3;
  final totalLength = 12 + 8 + jsonPadded + 8 + binPadded;

  final out = BytesBuilder(copy: false);
  final header = ByteData(12);
  header.setUint32(0, _kGlbMagic, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, totalLength, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHead = ByteData(8);
  jsonHead.setUint32(0, jsonPadded, Endian.little);
  jsonHead.setUint32(4, _kChunkJson, Endian.little);
  out.add(jsonHead.buffer.asUint8List());
  out.add(jsonBytes);
  out.add(Uint8List(jsonPadded - jsonBytes.length)
    ..fillRange(0, jsonPadded - jsonBytes.length, 0x20));

  final binHead = ByteData(8);
  binHead.setUint32(0, binPadded, Endian.little);
  binHead.setUint32(4, _kChunkBin, Endian.little);
  out.add(binHead.buffer.asUint8List());
  out.add(bin.buffer.asUint8List());
  out.add(Uint8List(binPadded - bin.lengthInBytes));
  return out.toBytes();
}

extension _MeshGlb on _Mesh {
  Uint8List buildGlb(String name) => _buildGlb(this, name);
}
