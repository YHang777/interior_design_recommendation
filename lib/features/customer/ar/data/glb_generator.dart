import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'room_finishes.dart' show RoomFinishCatalog;

// ─────────────────────────────────────────────────────────────────────────────
// Pure-Dart procedural glTF 2.0 GLB writer.
//
// IMPORTANT — what this file is (and is NOT) for:
//   * PRODUCT AR MODELS DO NOT COME FROM HERE. A product's 3D model is a
//     Tripo AI model, rescaled to the seller's dimensions (see
//     services/model_generation/ + rescaleGlbToSellerSize). There is no
//     procedural furniture path anymore — this file only produces the
//     room-scanner's floor/wall finish overlay slabs (Room Planner), and
//     hosts resolveShapeFamily (the keyword classifier the supplier product
//     form shares for dimension autofill).
//
// Everything is authored IN METERS (Y-up, right-handed), so the bounding
// boxes of generated models are true 1:1 world dimensions and can be placed
// in AR at exact size without plugin-side normalization.
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

const int _kGrey = 0xFFA0A0A0;

List<double> _rgb(int argb) => [
      ((argb >> 16) & 0xFF) / 255.0,
      ((argb >> 8) & 0xFF) / 255.0,
      (argb & 0xFF) / 255.0,
    ];

// ─── Geometry ───────────────────────────────────────────────────────────────

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x, y, z;

  _Vec3 operator -(final _Vec3 o) => _Vec3(x - o.x, y - o.y, z - o.z);

  double dot(final _Vec3 o) => x * o.x + y * o.y + z * o.z;

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

/// Maps a product (category + name) onto a furniture shape family.
///
/// KEPT for the supplier product form: `product_form_screen.dart` imports
/// this classifier to pick the right default W/H/D when autofilling the
/// dimension fields. It is NOT part of any AR model path anymore — a
/// product's 3D model is a Tripo AI model rescaled to the seller's numbers,
/// never a procedurally built shape.
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

// ─── Deterministic seeding ───────────────────────────────────────────────────

/// Deterministic FNV-1a over the lower-cased [text]; model output must not
/// depend on VM string hashing.
int _nameSeed(String text) {
  var h = 0x811C9DC5;
  for (final c in text.toLowerCase().codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
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
  const plankW = 0.12;
  const grainLine = 0.003; // width of visible grain lines
  final darkGrain = _tone(base, 0.82);
  final lightGrain = _tone(base, 1.08);
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
        // Base plank color with moderate variation per plank.
        final plankBase = _tone(base, 1 + rng.range(-0.08, 0.08));
        _floorQuad(m, x, z, x1, z1, plankBase);
        // Grain lines: thin strips running along X within the plank.
        final grainCount = (plankW / 0.025).floor();
        for (var g = 0; g < grainCount; g++) {
          final gz = z + g * 0.025 + rng.range(0.002, 0.008);
          if (gz + grainLine < z1) {
            final gc = g.isEven ? darkGrain : lightGrain;
            _floorQuad(m, x, gz, x1, gz + grainLine, gc);
          }
        }
        // End joint line (dark seam between plank ends).
        if (x1 < -lo - 0.01) {
          _floorQuad(m, x1 - grainLine, z, x1, z1, _tone(base, 0.6));
        }
      }
      if (x1 >= -lo - 1e-9) break;
      x = x1;
      first = false;
    }
    // Row joint line (dark seam between plank rows).
    _floorQuad(m, lo, z1 - grainLine, -lo, z1, _tone(base, 0.55));
    z = z1;
  }
}

void _floorCement(_Mesh m, int base, double lo, double size, _Rand rng) {
  final crackColor = _tone(base, 0.75);
  _walkGrid(size, 0.4, (x0, z0, x1, z1) {
    // Base slab with moderate variation.
    _floorQuad(m, x0, z0, x1, z1, _tone(base, 1 + rng.range(-0.04, 0.04)));
    // Occasional crack lines (30% chance per cell).
    if (rng.nextDouble() < 0.3) {
      final cx = x0 + rng.range(0.05, 0.35);
      final cz = z0 + rng.range(0.05, 0.35);
      // Short crack segment.
      final dx = rng.range(-0.15, 0.15);
      final dz = rng.range(-0.15, 0.15);
      _floorQuad(m, cx - 0.002, cz, cx + dx + 0.002, cz + dz, crackColor);
    }
  });
}

void _floorTiles(_Mesh m, int base, double lo, double size, _Rand rng) {
  const tile = 0.5;
  const inset = 0.015; // half the grout line width (more visible)
  final grout = _mix(base, _kGrey, 0.6);
  final groutDark = _mix(base, _kGrey, 0.7);
  _walkGrid(size, tile, (x0, z0, x1, z1) {
    // Tile face with slight per-tile variation and a subtle highlight.
    final tileColor = _tone(base, 1 + rng.range(-0.05, 0.05));
    _floorQuad(m, x0 + inset, z0 + inset, x1 - inset, z1 - inset, tileColor);
    // Subtle highlight in the center of the tile (light reflection).
    final cx = (x0 + x1) / 2;
    final cz = (z0 + z1) / 2;
    final hs = (x1 - x0 - inset * 2) * 0.3;
    if (hs > 0.01) {
      _floorQuad(m, cx - hs, cz - hs, cx + hs, cz + hs,
          _tone(tileColor, 1.04));
    }
    // Grout lines (darker than before for visibility).
    _floorQuad(m, x0, z0, x0 + inset, z1, groutDark);
    _floorQuad(m, x1 - inset, z0, x1, z1, groutDark);
    _floorQuad(m, x0 + inset, z0, x1 - inset, z0 + inset, grout);
    _floorQuad(m, x0 + inset, z1 - inset, x1 - inset, z1, grout);
    // Corner grout dots.
    _floorQuad(m, x0, z0, x0 + inset, z0 + inset, groutDark);
    _floorQuad(m, x1 - inset, z0, x1, z0 + inset, groutDark);
    _floorQuad(m, x0, z1 - inset, x0 + inset, z1, groutDark);
    _floorQuad(m, x1 - inset, z1 - inset, x1, z1, groutDark);
  });
}

void _floorParquet(_Mesh m, int base, double lo, double size, _Rand rng) {
  // Herringbone pattern: small rectangular blocks arranged in a V pattern.
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
      if (x1 > x + 1e-6 && z1 > z + 1e-6) {
        // Alternate grain direction per block.
        final even = ((x - lo) / (blockH + gap)).floor().isEven;
        final p = 1 + rng.range(-0.06, 0.06);
        _floorQuad(m, x, z, x1, z1, _tone(base, p));
        // Thin grain line along the long axis of the block.
        if (even) {
          final midZ = (z + z1) / 2;
          _floorQuad(m, x, midZ - 0.001, x1, midZ + 0.001, _tone(base, 0.85));
        } else {
          final midX = (x + x1) / 2;
          _floorQuad(m, midX - 0.001, z, midX + 0.001, z1, _tone(base, 0.85));
        }
      }
    }
    // Joint line along the row.
    if (z1 < -lo - 0.01) {
      _floorQuad(m, lo, z1 - gap, -lo, z1, darkJoint);
    }
    row++;
  }
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
      const panelW = 0.18, seam = 0.008;
      final darkSeam = _tone(base, 0.35);
      final grainDark = _tone(base, 0.8);
      final grainLight = _tone(base, 1.1);
      for (var x = loX; x < -loX - 1e-9; x += panelW) {
        final x1 = math.min(x + panelW, -loX);
        if (x1 <= x + 1e-6) continue;
        // Panel face with per-panel color variation.
        final panelColor = _tone(base, 1 + rng.range(-0.08, 0.08));
        wallQuad(x + seam / 2, 0, x1 - seam / 2, heightM, panelColor);
        // Vertical seam between panels (dark groove).
        wallQuad(x, 0, x + seam, heightM, darkSeam);
        // Horizontal grain lines running across the panel.
        final grainCount = (heightM / 0.04).floor();
        for (var g = 0; g < grainCount; g++) {
          final gy = g * 0.04 + rng.range(0.005, 0.015);
          if (gy + 0.002 < heightM) {
            final gc = g.isEven ? grainDark : grainLight;
            wallQuad(x + seam / 2, gy, x1 - seam / 2, gy + 0.002, gc);
          }
        }
        // Knot highlight (occasional, 20% of panels).
        if (rng.nextDouble() < 0.2) {
          final ky = rng.range(0.3, heightM - 0.3);
          final kx = (x + x1) / 2;
          final kr = 0.02;
          wallQuad(kx - kr, ky - kr, kx + kr, ky + kr, _tone(base, 0.7));
        }
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
