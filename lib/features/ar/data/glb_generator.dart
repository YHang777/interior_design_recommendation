import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'room_finishes.dart' show RoomFinishCatalog;

// ─────────────────────────────────────────────────────────────────────────────
// Pure-Dart procedural glTF 2.0 GLB writer.
//
// Everything is authored IN METERS (Y-up, right-handed), so the bounding
// boxes of generated models are true 1:1 world dimensions and can be placed
// in AR at exact product size without plugin-side normalization.
//
// Geometry: one mesh with a single primitive. Vertices are interleaved into
// one bufferView as pos3 + normal3 + color3 (36-byte stride, float32);
// indices (uint16, uint32 fallback) live in a second bufferView. Per-face
// (flat) normals are emitted by duplicating vertices per face. COLOR_0
// vertex colors give every part / pattern cell its own tint (material
// baseColorFactor stays white — Filament/gltfio multiplies the two).
// POSITION accessors always carry the spec-required min/max arrays.
// ─────────────────────────────────────────────────────────────────────────────

// GLB constants.
const int _kGlbMagic = 0x46546C67; // 'glTF'
const int _kChunkJson = 0x4E4F534A; // 'JSON'
const int _kChunkBin = 0x004E4942; // 'BIN\0'
const int _kComponentFloat = 5126;
const int _kComponentUint16 = 5123;
const int _kComponentUint32 = 5125;

const double _kPi2 = 6.283185307179586;

// ─── Floor / wall finish specs (Loop 4 customization) ───────────────────────

enum FloorFinishType { woodPlanks, cement, ceramicTiles, parquet }

/// Describes a floor finish: pattern type, base color (ARGB — e.g. from a
/// color picker) and the total floor side length in meters (default 3 m,
/// i.e. a 3×3 m slab).
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

/// Describes a wall finish: pattern type and base color (ARGB). The panel
/// size is owned by [RoomFinishCatalog.wallWidthM] / [RoomFinishCatalog
/// .wallHeightM] (2.4 m wide × 2.7 m high × 0.05 m deep by default) and is
/// passed into [generateWallGlb] — never duplicated here.
class WallFinish {
  const WallFinish({
    this.type = WallFinishType.paint,
    required this.colorArgb,
  });

  final WallFinishType type;
  final int colorArgb;
}

// ─── Deterministic RNG + color helpers ──────────────────────────────────────

/// Small deterministic LCG — identical inputs yield byte-identical models
/// (no Math.random anywhere).
class _Rand {
  _Rand(int seed) : _state = (seed & 0x7FFFFFFF) == 0 ? 0x9E3779B9 : seed;

  int _state;

  void _advance() {
    _state = (_state * 1664525 + 1013904223) & 0x7FFFFFFF;
  }

  /// Uniform in [0, 1).
  double nextDouble() {
    _advance();
    return _state / 0x80000000;
  }

  /// Uniform int in [0, bound).
  int nextInt(int bound) {
    _advance();
    return _state % bound;
  }

  /// Uniform in [min, max].
  double range(double min, double max) => min + (max - min) * nextDouble();
}

/// Multiplies each sRGB channel of [argb] by [p] and re-clamps, so p in
/// 0.94–1.06 gives a subtle ±6 % tone variation, p < 1 darkens.
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

/// Channel-wise linear mix of two ARGB colors (t in [0, 1], 1 → b).
int _mix(int a, int b, double t) {
  int ch(int ca, int cb) => (ca + (cb - ca) * t).round();
  return 0xFF000000 |
      (ch((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16) |
      (ch((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8) |
      ch(a & 0xFF, b & 0xFF);
}

/// Clamp that can never throw. Dart's `num.clamp` requires `lo <= hi` and
/// throws an ArgumentError otherwise, which crashes the generator on absurdly
/// squat products. Callers that have no real room for a part additionally
/// degrade the part out of existence instead of clamping blindly.
double _clampSafe(double v, double lo, double hi) {
  final a = math.min(lo, hi);
  final b = math.max(lo, hi);
  return v.clamp(a, b).toDouble();
}

const int _kGrey = 0xFFA0A0A0;

List<double> _rgb(int argb) => [
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
    ];

/// Palettes per shape family; which entry is used is RNG-chosen (and
/// therefore still deterministic for a given name + seed).
const List<int> _wood = [
  0xFF8B5A2B, 0xFFA0714F, 0xFF6F4E37, 0xFF9C6B3E, 0xFF7C5433,
];
const List<int> _fabric = [
  0xFFB0A69A, 0xFF9C938A, 0xFFC2B8AA, 0xFF8D857B, 0xFFA79F96,
];
const List<int> _metal = [0xFF3B3B38, 0xFF55524E, 0xFF2B2B29, 0xFF45433F];
const List<int> _shadeWarm = [0xFFC9A878, 0xFFE3D2B3, 0xFFB98F63, 0xFFD8C3A5];
const List<int> _decor = [0xFF9A6B53, 0xFFC08552, 0xFFB99362, 0xFF8C6F5A];

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

/// Accumulates triangles and serializes one interleaved vertex stream.
class _Mesh {
  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _colors = [];
  final List<int> _indices = [];

  int get vertexCount => _positions.length ~/ 3;
  int get indexCount => _indices.length;

  /// Pushes a triangle, flipping winding when needed so the geometric
  /// normal points along [n] (flat, per-face shading).
  void _tri(_Vec3 a, _Vec3 b, _Vec3 c, _Vec3 n, int color) {
    var v0 = b - a;
    var v1 = c - a;
    if (n.dot(_Vec3.cross(v0, v1)) < 0) {
      final t = b;
      b = c;
      c = t;
      v0 = b - a;
      v1 = c - a;
    }
    if (n.dot(_Vec3.cross(v0, v1)) <= 0) return; // degenerate — drop
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
  }

  /// Planar quad; corners may be passed in any cyclic order (winding is
  /// corrected against [normal]).
  void quad(_Vec3 a, _Vec3 b, _Vec3 c, _Vec3 d, _Vec3 normal, int color) {
    _tri(a, b, c, normal, color);
    _tri(a, c, d, normal, color);
  }

  /// Axis-aligned box from (x0,y0,z0) to (x1,y1,z1).
  void box(
      double x0, double y0, double z0, double x1, double y1, double z1, int color) {
    quad(_Vec3(x1, y0, z0), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1),
        _Vec3(x1, y1, z0), const _Vec3(1, 0, 0), color);
    quad(_Vec3(x0, y0, z1), _Vec3(x0, y0, z0), _Vec3(x0, y1, z0),
        _Vec3(x0, y1, z1), const _Vec3(-1, 0, 0), color);
    quad(_Vec3(x0, y1, z0), _Vec3(x1, y1, z0), _Vec3(x1, y1, z1),
        _Vec3(x0, y1, z1), const _Vec3(0, 1, 0), color);
    quad(_Vec3(x0, y0, z1), _Vec3(x1, y0, z1), _Vec3(x1, y0, z0),
        _Vec3(x0, y0, z0), const _Vec3(0, -1, 0), color);
    quad(_Vec3(x0, y0, z1), _Vec3(x1, y0, z1), _Vec3(x1, y1, z1),
        _Vec3(x0, y1, z1), const _Vec3(0, 0, 1), color);
    quad(_Vec3(x1, y0, z0), _Vec3(x0, y0, z0), _Vec3(x0, y1, z0),
        _Vec3(x1, y1, z0), const _Vec3(0, 0, -1), color);
  }

  /// Regular [sides]-sided prism / frustum between y0 and y1 centered on
  /// (cx, cz), bottom radius r0, top radius r1 (r0 == r1 → cylinder, r0 >
  /// r1 → tapered shade). Flat per-side normals.
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
  }) {
    assert(sides >= 3 && y1 > y0);
    for (var k = 0; k < sides; k++) {
      final t0 = k * _kPi2 / sides;
      final t1 = (k + 1) * _kPi2 / sides;
      final a = _Vec3(cx + r0 * math.cos(t0), y0, cz + r0 * math.sin(t0));
      final b = _Vec3(cx + r0 * math.cos(t1), y0, cz + r0 * math.sin(t1));
      final c = _Vec3(cx + r1 * math.cos(t1), y1, cz + r1 * math.sin(t1));
      final d = _Vec3(cx + r1 * math.cos(t0), y1, cz + r1 * math.sin(t0));
      // Outward normal of the flat side plane.
      final tm = (t0 + t1) / 2;
      var n = _Vec3.cross(b - a, d - a);
      if (n.dot(_Vec3(math.cos(tm), 0, math.sin(tm))) < 0) {
        n = _Vec3.cross(d - a, b - a);
      }
      quad(a, b, c, d, n.normalized(), color);
    }
    if (closeBottom) _cap(r0, y0, cx, cz, false, sides, color);
    if (closeTop) _cap(r1, y1, cx, cz, true, sides, color);
  }

  void _cap(double r, double y, double cx, double cz, bool top, int sides,
      int color) {
    if (r <= 0) return;
    final center = _Vec3(cx, y, cz);
    final normal = top ? const _Vec3(0, 1, 0) : const _Vec3(0, -1, 0);
    for (var k = 0; k < sides; k++) {
      final t0 = k * _kPi2 / sides;
      final t1 = (k + 1) * _kPi2 / sides;
      final a = _Vec3(cx + r * math.cos(t0), y, cz + r * math.sin(t0));
      final b = _Vec3(cx + r * math.cos(t1), y, cz + r * math.sin(t1));
      _tri(center, b, a, normal, color);
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

/// Routes a decor-category product onto its decor shape family by name
/// keywords. Unknown decor names deliberately fall to 'default' — they are
/// full 3D objects (not 2 cm mats).
String _decorKeywordFamily(String n) {
  if (_hasAnyKeyword(n, const ['rug', 'carpet'])) return 'rug';
  if (_hasAnyKeyword(n, const ['vase', 'planter', 'pot'])) return 'vase';
  if (_hasAnyKeyword(n, const ['mirror', 'art', 'frame', 'picture'])) {
    return 'mirror';
  }
  if (_hasAnyKeyword(n, const ['cushion', 'pillow'])) return 'cushion';
  return 'default';
}

/// Maps a product (category + name) onto the furniture shape family to build.
/// This is the single implementation the generator AND the product form's
/// dimension guessing share, so both always mis-classify the same products
/// (and neither one does).
///
/// The category is the primary hint:
///  * 'lighting' → everything is a lamp (even a "Table Lamp" or "Desk");
///  * 'decor'    → name keywords pick rug / vase / mirror / cushion, anything
///                 else is 'default' (a real cuboid, never a mat);
///  * otherwise  → name keywords, with SPECIFIC matches before generic ones
///                 ('bedside'/'nightstand' before 'bed', 'lamp'/'light'
///                 before 'table', 'armchair' before 'chair', …).
///
/// Returns: 'table' | 'sofa' | 'chair' | 'armchair' | 'bed' | 'cabinet' |
/// 'lamp' | 'rug' | 'vase' | 'mirror' | 'cushion' | 'default'.
String resolveShapeFamily({required String category, required String name}) {
  final n = name.toLowerCase();
  final cat = category.trim().toLowerCase();

  if (cat == 'lighting') return 'lamp';
  if (cat == 'decor') return _decorKeywordFamily(n);

  if (_hasAnyKeyword(n, const ['rug', 'carpet'])) return 'rug';
  if (_hasAnyKeyword(n, const ['bedside', 'nightstand'])) return 'cabinet';
  if (_hasAnyKeyword(n, const ['vase', 'planter', 'pot'])) return 'vase';
  if (_hasAnyKeyword(n, const ['mirror', 'art', 'frame', 'picture'])) {
    return 'mirror';
  }
  if (_hasAnyKeyword(n, const ['cushion', 'pillow'])) return 'cushion';
  if (n.contains('armchair')) return 'armchair';
  if (n.contains('sofa')) return 'sofa';
  if (_hasAnyKeyword(n, const ['lamp', 'light'])) return 'lamp';
  if (n.contains('bed')) return 'bed';
  if (n.contains('chair')) return 'chair';
  if (_hasAnyKeyword(
      n, const ['cabinet', 'shelf', 'bookcase', 'wardrobe', 'chest'])) {
    return 'cabinet';
  }
  if (n.contains('table') || n.contains('dining')) return 'table';
  return 'default';
}

// ─── Public entry points ─────────────────────────────────────────────────────

/// Deterministic FNV-1a over the lower-cased [text]; model output must not
/// depend on VM string hashing.
int _nameSeed(String text) {
  var h = 0x811C9DC5;
  for (final c in text.toLowerCase().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Generates a furniture GLB (all dimensions real-world meters, Y-up,
/// base centered at the origin and resting on y = 0).
///
/// The shape is picked by [resolveShapeFamily] (category hint + name-keyword
/// sweep). [seedOrColor] varies the — still deterministic — palette/part
/// tones for a given name.
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
    case 'mirror':
      _buildWallArt(mesh, widthM, heightM, depthM, rng);
      break;
    case 'cushion':
      _buildCushion(mesh, widthM, heightM, depthM, rng);
      break;
    default:
      // Default cuboid (desk, stool, tv stand, unclassified decor…).
      final palette =
          cat.contains('textile') || cat.contains('fab') ? _fabric : _wood;
      mesh.box(-widthM / 2, 0, -depthM / 2, widthM / 2, heightM, depthM / 2,
          _tone(palette[rng.nextInt(palette.length)], 0.96));
  }

  if (mesh.indexCount == 0) {
    throw StateError('Shape "$name" produced no geometry.');
  }
  return mesh.buildGlb(name.isEmpty ? 'furniture' : name);
}

/// Flat rug / carpet slab, 2 cm thick. Only products whose NAME says rug or
/// carpet reach this builder (resolveShapeFamily never routes plain decor
/// here), so a 40 cm vase can never collapse into a mat.
void _buildRug(_Mesh m, double w, double d, _Rand rng) {
  m.box(-w / 2, 0, -d / 2, w / 2, 0.02, d / 2,
      _decor[rng.nextInt(_decor.length)]);
}

/// Round pot / vase: an 8-sided prism, grounded at y = 0. Prism radii are
/// circular, so the footprint fills min(w, d); the body tapers toward the
/// mouth and the bottom is capped (it reads as a vase/planter from above).
/// Bounds: min(w,d) × h × min(w,d) when w == d, i.e. the product's own
/// extents — never a 2 cm mat.
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
      closeBottom: true);
}

/// Wall art / mirror / framed picture: a thin slab of the full W×H face and
/// ~3 cm of depth (capped at the seller's depth when it is thinner).
void _buildWallArt(_Mesh m, double w, double h, double d, _Rand rng) {
  final halfT = math.min(0.03, d) / 2;
  m.box(-w / 2, 0, -halfT, w / 2, h, halfT,
      _tone(_metal[rng.nextInt(_metal.length)], 1.0));
}

/// Cushion / pillow: a soft low slab. Sellers often type a cubic "height"
/// for pillows; a cushion is flat, so the height is capped at 15 cm (the
/// thickness of a typical throw cushion) while W and D stay exact.
void _buildCushion(_Mesh m, double w, double h, double d, _Rand rng) {
  final hc = math.min(h, 0.15);
  m.box(-w / 2, 0, -d / 2, w / 2, hc, d / 2,
      _tone(_fabric[rng.nextInt(_fabric.length)], rng.range(0.95, 1.05)));
}

void _buildTable(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final topC = _tone(base, rng.range(0.96, 1.02));
  final legC = _tone(base, rng.range(0.8, 0.9));
  final topBottom = h - 0.05;
  if (topBottom <= 0.01) {
    m.box(-w / 2, 0, -d / 2, w / 2, h, d / 2, topC);
    return;
  }
  m.box(-w / 2, topBottom, -d / 2, w / 2, h, d / 2, topC); // top slab, 5 cm
  // 4 legs, 8×8 cm cross-section, inset 8 % from the edges.
  final insetX = w * 0.08;
  final insetZ = d * 0.08;
  for (final sx in const [-1.0, 1.0]) {
    for (final sz in const [-1.0, 1.0]) {
      final cx = sx * (w / 2 - insetX) - (sx > 0 ? 0.04 : -0.04);
      final cz = sz * (d / 2 - insetZ) - (sz > 0 ? 0.04 : -0.04);
      m.box(cx - 0.04, 0, cz - 0.04, cx + 0.04, topBottom, cz + 0.04, legC);
    }
  }
}

void _buildSofa(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _fabric[rng.nextInt(_fabric.length)];
  final seatH = _clampSafe(h * 0.42, h * 0.25, h * 0.5);
  m.box(-w / 2, 0, -d / 2, w / 2, seatH, d / 2,
      _tone(base, rng.range(0.88, 0.96))); // base / seat
  // Backrest and arms need ≥ 8 cm of headroom above the seat; an absurdly
  // squat product degrades to the seat slab instead of throwing (the old
  // clamps had lo > hi and crashed on small heights).
  final backRoom = h - seatH;
  if (backRoom < 0.08) return;
  m.box(-w / 2, seatH, -d / 2, w / 2, h, -d / 2 + 0.18,
      _tone(base, rng.range(1.0, 1.08))); // backrest (18 cm thick)
  final armTop = _clampSafe(h * 0.55, seatH + 0.03, h - 0.05);
  m.box(-w / 2, 0, -d / 2, -w / 2 + 0.18, armTop, d / 2,
      _tone(base, rng.range(0.92, 1.0))); // left arm
  m.box(w / 2 - 0.18, 0, -d / 2, w / 2, armTop, d / 2,
      _tone(base, rng.range(0.92, 1.0))); // right arm
}

void _buildChair(_Mesh m, double w, double h, double d, _Rand rng,
    {required bool armrests}) {
  final base = _fabric[rng.nextInt(_fabric.length)];
  if (h < 0.2) {
    // No room for legs + a raised seat (the formulas below need h ≥ 0.2):
    // degrade to a low stool slab with a short back instead of throwing.
    final seatTop = _clampSafe(h * 0.75, 0.03, h);
    m.box(-w / 2, 0, -d / 2, w / 2, seatTop, d / 2,
        _tone(base, rng.range(0.95, 1.05))); // seat slab
    final backH = h - seatTop;
    if (backH > 0.02) {
      m.box(-w / 2, seatTop, -d / 2, w / 2, h, -d / 2 + 0.06,
          _tone(base, rng.range(1.0, 1.1))); // back (6 cm thick)
    }
    return;
  }
  final seatTop = _clampSafe(h * 0.45, 0.1, h - 0.1);
  final legH = _clampSafe(seatTop - 0.08, 0.02, seatTop);
  // 4 legs, 5 cm cross-section, inset 8 %.
  final insetX = w * 0.08;
  final insetZ = d * 0.08;
  for (final sx in const [-1.0, 1.0]) {
    for (final sz in const [-1.0, 1.0]) {
      final cx = sx * (w / 2 - insetX) - (sx > 0 ? 0.025 : -0.025);
      final cz = sz * (d / 2 - insetZ) - (sz > 0 ? 0.025 : -0.025);
      m.box(cx - 0.025, 0, cz - 0.025, cx + 0.025, legH, cz + 0.025,
          _tone(base, rng.range(0.8, 0.9)));
    }
  }
  m.box(-w / 2, seatTop - 0.08, -d / 2, w / 2, seatTop, d / 2,
      _tone(base, rng.range(0.95, 1.05))); // seat slab
  m.box(-w / 2, seatTop, -d / 2, w / 2, h, -d / 2 + 0.06,
      _tone(base, rng.range(1.0, 1.1))); // back (6 cm thick)
  if (armrests) {
    final armTop = _clampSafe(h * 0.6, seatTop + 0.02, h - 0.05);
    final armC = _tone(base, rng.range(0.9, 1.0));
    m.box(-w / 2, seatTop - 0.05, -d / 2 + 0.03, -w / 2 + 0.08, armTop,
        d / 2 - 0.03, armC);
    m.box(w / 2 - 0.08, seatTop - 0.05, -d / 2 + 0.03, w / 2, armTop,
        d / 2 - 0.03, armC);
  }
}

void _buildBed(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final frameH = math.min(0.3, h * 0.5);
  m.box(-w / 2, 0, -d / 2, w / 2, frameH, d / 2,
      _tone(base, rng.range(0.85, 0.95))); // frame
  m.box(-w / 2, frameH, -d / 2, w / 2, h, -d / 2 + 0.1,
      _tone(base, rng.range(1.0, 1.1))); // headboard at the back edge
}

void _buildCabinet(_Mesh m, double w, double h, double d, _Rand rng) {
  final base = _wood[rng.nextInt(_wood.length)];
  final bodyC = _tone(base, rng.range(0.92, 1.0));
  final shelfC = _tone(base, rng.range(0.6, 0.74));
  m.box(-w / 2, 0, -d / 2, w / 2, h, d / 2, bodyC);
  // Shelf slabs: dark bands just proud of the front (−Z) face so they read
  // as shelf lines head-on.
  final shelves = h > 1.2 ? 3 : 2;
  const bandThick = 0.025;
  for (var i = 1; i <= shelves; i++) {
    final y0 = h * i / (shelves + 1) - bandThick / 2;
    m.box(-w / 2 + 0.02, y0, -d / 2 - 0.007, w / 2 - 0.02, y0 + bandThick,
        -d / 2 + 0.01, shelfC);
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
  // Pedestal.
  m.prism(
      sides: 8,
      r0: rBase,
      r1: rBase * 0.9,
      y0: 0,
      y1: baseH,
      color: _tone(metalC, 0.85),
      closeBottom: true);
  // 8-sided pole stem.
  m.prism(sides: 8, r0: rStem, r1: rStem, y0: baseH, y1: shadeBottomY, color: metalC);
  // Tapered shade — widest at the bottom so the model's max width ≈ W.
  m.prism(
      sides: 8,
      r0: 0.48 * w,
      r1: 0.24 * w,
      y0: shadeBottomY,
      y1: h * 0.95,
      color: shadeC);
}

// ─── Floor / wall generators ─────────────────────────────────────────────────

/// 3×3 m floor slab (top surface at y = 0, pattern in vertex colors).
Uint8List generateFloorGlb({required FloorFinish finish}) {
  final size = finish.sizeM;
  if (size <= 0) {
    throw ArgumentError.value(size, 'finish.sizeM', 'must be positive');
  }
  final base = finish.colorArgb;
  final mesh = _Mesh();
  final lo = -size / 2;
  final rng = _Rand(_nameSeed('floor:${finish.type.name}:$base'));
  // Solid slab with a darker underside.
  mesh.box(lo, -0.01, lo, -lo, 0, -lo, _tone(base, 0.72));
  switch (finish.type) {
    case FloorFinishType.woodPlanks:
      _floorWoodPlanks(mesh, base, lo, size, rng);
    case FloorFinishType.cement:
      _floorCement(mesh, base, lo, size, rng);
    case FloorFinishType.ceramicTiles:
      _floorTiles(mesh, base, lo, size, rng);
    case FloorFinishType.parquet:
      _floorParquet(mesh, base, lo, size, rng);
  }
  return mesh.buildGlb('floor_${finish.type.name}');
}

/// Top-surface quad from (x0, z0) to (x1, z1) at y = 0.
void _floorQuad(_Mesh m, double x0, double z0, double x1, double z1, int color) {
  m.quad(_Vec3(x0, 0, z0), _Vec3(x1, 0, z0), _Vec3(x1, 0, z1),
      _Vec3(x0, 0, z1), const _Vec3(0, 1, 0), color);
}

/// Walks a [cell]×[cell] square grid over [-size/2, size/2] calling [cellFn]
/// with clamped (x0, x1, z0, z1).
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

void _floorWoodPlanks(_Mesh m, int base, double lo, double size, _Rand rng) {
  const plankW = 0.15;
  var z = lo;
  while (z < -lo - 1e-9) {
    final z1 = math.min(z + plankW, -lo);
    // Planks run along X. Random lengths make row joints stagger; the
    // first plank of each row is shorter to decorrelate the rows.
    var x = lo;
    var first = true;
    while (x < -lo - 1e-9) {
      final len = first ? rng.range(0.4, 1.0) : rng.range(0.9, 1.5);
      final x1 = math.min(x + len, -lo);
      if (x1 > x + 1e-6) {
        final c = _tone(base, 1 + rng.range(-0.06, 0.06));
        _floorQuad(m, x, z, x1, z1, c);
      }
      if (x1 >= -lo - 1e-9) break;
      x = x1;
      first = false;
    }
    z = z1;
  }
}

void _floorCement(_Mesh m, int base, double lo, double size, _Rand rng) {
  _walkGrid(size, 0.5,
      (x0, z0, x1, z1) => _floorQuad(m, x0, z0, x1, z1,
          _tone(base, 1 + rng.range(-0.02, 0.02))));
}

void _floorTiles(_Mesh m, int base, double lo, double size, _Rand rng) {
  const tile = 0.6;
  const inset = 0.01; // half the grout line width
  final grout = _mix(base, _kGrey, 0.55);
  _walkGrid(size, tile, (x0, z0, x1, z1) {
    // 9 quads per tile: center tile face + 8 grout-border quads.
    _floorQuad(
        m,
        x0 + inset,
        z0 + inset,
        x1 - inset,
        z1 - inset,
        _tone(base, 1 + rng.range(-0.04, 0.04)));
    _floorQuad(m, x0, z0, x0 + inset, z1, grout);
    _floorQuad(m, x1 - inset, z0, x1, z1, grout);
    _floorQuad(m, x0 + inset, z0, x1 - inset, z0 + inset, grout);
    _floorQuad(m, x0 + inset, z1 - inset, x1 - inset, z1, grout);
    _floorQuad(m, x0, z0 + inset, x0 + inset, z1 - inset, grout);
    _floorQuad(m, x1 - inset, z0 + inset, x1, z1 - inset, grout);
    _floorQuad(m, x0, z0, x0 + inset, z0 + inset, grout);
    _floorQuad(m, x1 - inset, z1 - inset, x1, z1, grout);
  });
}

void _floorParquet(_Mesh m, int base, double lo, double size, _Rand rng) {
  // Small squares tinted in alternating 45° bands (x + z ≈ const).
  _walkGrid(size, 0.075, (x0, z0, x1, z1) {
    final even = ((x0 + z0) / 0.3).floor().isEven;
    final p = 1 + (even ? rng.range(0.0, 0.02) : rng.range(-0.06, -0.02));
    _floorQuad(m, x0, z0, x1, z1, _tone(base, p));
  });
}

/// Wall panel [widthM] × [heightM] × 0.05 m standing upright on y = 0
/// (centered on X), pattern on the +Z face. The size defaults come from the
/// Room panel's single source of truth — [RoomFinishCatalog.wallWidthM] /
/// [RoomFinishCatalog.wallHeightM] (2.4 × 2.7 m) — so the generator never
/// re-declares the dimensions.
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
  // Under the pattern, the panel front doubles as seam/mortar color.
  final underC = switch (finish.type) {
    WallFinishType.paint => base,
    WallFinishType.woodPanels => _tone(base, 0.45),
    WallFinishType.brick => _mix(_tone(base, 0.5), _kGrey, 0.45),
  };
  mesh.box(loX, 0, -halfD, -loX, heightM, halfD, underC);
  const frontZ = halfD; // pattern sits on the +Z face

  void wallQuad(double x0, double y0, double x1, double y1, int color) {
    if (x1 <= x0 || y1 <= y0) return;
    mesh.quad(_Vec3(x0, y0, frontZ), _Vec3(x1, y0, frontZ),
        _Vec3(x1, y1, frontZ), _Vec3(x0, y1, frontZ),
        const _Vec3(0, 0, 1), color);
  }

  switch (finish.type) {
    case WallFinishType.paint:
      // Flat paint with very subtle per-cell variation (0.48 × 0.54 m cells
      // tile the default 2.4 × 2.7 m panel; other sizes end on a partial
      // cell).
      for (var x = loX; x < -loX - 1e-9; x += 0.48) {
        final x1 = math.min(x + 0.48, -loX);
        for (var y = 0.0; y < heightM - 1e-9; y += 0.54) {
          final y1 = math.min(y + 0.54, heightM);
          wallQuad(x, y, x1, y1, _tone(base, 1 + rng.range(-0.015, 0.015)));
        }
      }
      break;
    case WallFinishType.woodPanels:
      const panelW = 0.2, seam = 0.006;
      for (var x = loX; x < -loX - 1e-9; x += panelW) {
        final x1 = math.min(x + panelW, -loX);
        wallQuad(x + seam / 2, 0, x1 - seam / 2, heightM,
            _tone(base, 1 + rng.range(-0.06, 0.06)));
        wallQuad(x, 0, x + seam, heightM, _tone(base, 0.4));
      }
      break;
    case WallFinishType.brick:
      _wallBrick(wallQuad, base, loX, heightM, rng);
      break;
  }
  return mesh.buildGlb('wall_${finish.type.name}');
}

/// Running-bond brick pattern: 0.25 m × ~0.08 m bricks with staggered
/// joints; mortar shows through as the darker gaps between bricks.
void _wallBrick(void Function(double x0, double y0, double x1, double y1, int c) quad,
    int base, double loX, double wallH, _Rand rng) {
  const rowCount = 34;
  final rowH = wallH / rowCount;
  const colW = 0.25; // brick length
  const mortar = 0.008;
  for (var row = 0; row < rowCount; row++) {
    final y0 = row * rowH + (row == 0 ? 0 : mortar / 2);
    final y1 = row == rowCount - 1 ? wallH : (row + 1) * rowH - mortar / 2;
    final stagger = (row.isEven ? 0.0 : colW / 2);
    // Leading half-brick on staggered rows fills the row start.
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

// ─── GLB serialization ───────────────────────────────────────────────────────

/// Serializes the accumulated mesh into a valid binary glTF 2.0 file.
Uint8List _buildGlb(_Mesh mesh, String nodeName) {
  final vCount = mesh.vertexCount;
  final iCount = mesh.indexCount;
  if (vCount == 0 || iCount == 0) {
    throw StateError('Cannot serialize an empty mesh.');
  }
  final use32 = vCount >= 0xFFFF;
  const vertexStride = 36; // pos3 + normal3 + color3, float32 each
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
  for (var i = 0; i < iCount; i++) {
    final idx = mesh._indices[i];
    if (use32) {
      bin.setUint32(o, idx, Endian.little);
      o += 4;
    } else {
      bin.setUint16(o, idx, Endian.little);
      o += 2;
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
  final json = <String, dynamic>{
    'asset': {
      'version': '2.0',
      'generator': 'interior_design_recommendation/glb_generator.dart',
    },
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
          {
            'attributes': {'POSITION': 0, 'NORMAL': 1, 'COLOR_0': 2},
            'indices': 3,
            'material': 0,
          }
        ],
      }
    ],
    'materials': [
      {
        'name': 'vertexColored',
        'pbrMetallicRoughness': {
          'baseColorFactor': [1.0, 1.0, 1.0, 1.0],
          'metallicFactor': 0.0,
          'roughnessFactor': 1.0,
        },
        'doubleSided': true,
      }
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
      {
        'bufferView': 1,
        'byteOffset': 0,
        'componentType': use32 ? _kComponentUint32 : _kComponentUint16,
        'count': iCount,
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
  // Pad with spaces (0x20) per the GLB spec.
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
