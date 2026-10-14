import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../../models/product.dart';
import 'glb_bounds.dart';

/// Thrown when a GLB cannot be rescaled (degenerate geometry, missing BIN
/// chunk, …). Container/accessor-level malformations surface as
/// [GlbParseException] from the shared reader ([GlbStructure]) instead —
/// there is no second parser in here to throw its own flavour.
class GlbRescaleException implements Exception {
  const GlbRescaleException(this.message);

  final String message;

  @override
  String toString() => 'GlbRescaleException: $message';
}

/// Thrown when the seller declared no usable dimension at all (every axis is
/// missing or ≤ 0). AR then refuses to size — and therefore refuses to place —
/// the model. A guessed size is never acceptable: the seller's numbers are
/// the only source of truth for how big a product is.
class MissingDimensionsException implements Exception {
  const MissingDimensionsException();

  @override
  String toString() => 'MissingDimensionsException: the product declares no '
      'Width/Height/Depth (meters).';
}

/// Whether the seller declared at least one usable dimension (> 0 m). Only
/// these products may be modeled / placed in AR; a product with none may not.
bool hasAnySellerDimension(ProductDimensions? dims) =>
    dims != null && (dims.widthM > 0 || dims.heightM > 0 || dims.depthM > 0);

/// The product form caps every axis at 10 m, so any stored value above that
/// is a cm-vs-m unit slip (e.g. 250 typed for a 2.50 m sofa). Normalize it
/// back to meters before rescaling — otherwise the model renders 100× too
/// big ("the sofa is too big").
double _normalizeSellerMeters(double v) => v > 10.0 ? v / 100.0 : v;

/// Rescales a downloaded Tripo GLB (arbitrary baked scale — e.g. a 0.70 m
/// mesh for a product the seller declared as 0.50 m) to the SELLER's declared
/// size and grounds it at y = 0.
///
/// The seller's dimensions in the product form are the single source of
/// truth for size:
///  * all three of W/H/D present → per-axis rescale to exactly those
///    dimensions (true size);
///  * only some present → a UNIFORM scale driven by the dimension(s) that
///    were given, HEIGHT preferred, so "height 0.50 m" turns a 0.70 m mesh
///    into a 0.50 m mesh while the proportions stay intact;
///  * none present → [MissingDimensionsException]. Never a guessed size.
///
/// The heavy lifting (per-axis factors, Y grounding, normal repair) is
/// [rescaleGlbToDimensions] — this function only decides the target size.
Uint8List rescaleGlbToSellerSize(Uint8List glbBytes, ProductDimensions? dims) {
  if (!hasAnySellerDimension(dims)) throw const MissingDimensionsException();
  // Bake node transforms into the vertex data first (identity → same bytes),
  // so accessor-space extents below ARE the model's rendered size — a root
  // Z-up→Y-up rotation or unit scale in the node chain used to make the
  // parsed bounds disagree with what SceneView renders ("too big" / floating).
  glbBytes = bakeGlbNodeTransforms(glbBytes);
  final d = dims!; // non-null: the guard above throws otherwise
  // cm-vs-m guard: values above the form's 10 m cap are unit slips.
  final widthM = _normalizeSellerMeters(d.widthM);
  final heightM = _normalizeSellerMeters(d.heightM);
  final depthM = _normalizeSellerMeters(d.depthM);
  if (widthM > 0 && heightM > 0 && depthM > 0) {
    return rescaleGlbToDimensions(
      glbBytes,
      targetWidthM: widthM,
      targetHeightM: heightM,
      targetDepthM: depthM,
    );
  }

  // Partial dimensions → one uniform scale so the mesh keeps its shape.
  // Height is preferred (the declared height is what a seller measures a
  // piece of furniture by), then width, then depth.
  final bounds = GlbBounds.fromGlbBytes(glbBytes);
  if (bounds.isDegenerate) {
    throw GlbRescaleException('Cannot rescale: source geometry is degenerate '
        '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m).');
  }
  final double scale;
  if (heightM > 0) {
    scale = heightM / bounds.heightM;
  } else if (widthM > 0) {
    scale = widthM / bounds.widthM;
  } else {
    scale = depthM / bounds.depthM;
  }
  return rescaleGlbToDimensions(
    glbBytes,
    targetWidthM: bounds.widthM * scale,
    targetHeightM: bounds.heightM * scale,
    targetDepthM: bounds.depthM * scale,
  );
}

/// Rescales a binary glTF 2.0 (GLB) model so its geometry exactly spans
/// [targetWidthM] × [targetHeightM] × [targetDepthM] real-world meters, then
/// grounds it (minY → 0) so the model rests on the floor when placed in AR.
///
/// Usage contract:
/// - Downloaded AI models (e.g. Tripo) carry arbitrary baked scale. The AR
///   plugin (`ar_flutter_plugin_2`) only supports UNIFORM scaling at
///   placement (`scaleToUnitCube`), so true W×H×D must be baked into the
///   GLB geometry itself — that is what this function does.
/// - After rescaling, placement applies `scaleToUnitCube(maxExtent)` → the
///   uniform factor is 1.0 and the model renders at true size.
///
/// Implementation notes:
/// - All parsing + accessor validation goes through the ONE shared GLB
///   reader ([GlbStructure.parse] / [GlbStructure.dataAccessor] — see
///   glb_bounds.dart). The historical second parser lived here; it is gone.
/// - POSITION float32 data is patched in place inside a private copy of the
///   BIN chunk: x' = x·sx, y' = (y − minY)·sy, z' = z·sz. The accessor's
///   spec-required `min`/`max` arrays are recomputed from the stored values.
/// - NORMAL accessors are patched per-axis with the inverse scale and
///   re-normalized — n' = normalize(nx/sx, ny/sy, nz/sz) — so flat-shaded
///   lighting stays correct after non-uniform scaling (each normal's length
///   does not matter to the renderer, only its direction, but leaving the
///   distorted vectors breaks shading). Degenerate (zero-length) vectors are
///   left untouched. NORMAL `min`/`max` keys are not spec-required; when a
///   file happens to carry them, they are refreshed to match the stored
///   data, never left stale.
/// - A malformed NORMAL stream never aborts the rescale (strict: false) —
///   the worst case is untouched normals on that primitive, while POSITION
///   data remains authoritative and validated (strict: true).
/// - Sparse-accessor POSITION data is rejected with a descriptive error —
///   patching `bufferView` floats cannot see the sparse delta stream.
///
/// Throws [ArgumentError] for non-positive target dimensions,
/// [GlbRescaleException] when the source geometry cannot be rescaled, and
/// [GlbParseException] when the source GLB is malformed.
Uint8List rescaleGlbToDimensions(
  Uint8List glbBytes, {
  required double targetWidthM,
  required double targetHeightM,
  required double targetDepthM,
}) {
  if (targetWidthM <= 0 || targetHeightM <= 0 || targetDepthM <= 0) {
    throw ArgumentError.value(
      [targetWidthM, targetHeightM, targetDepthM],
      'target dimensions',
      'rescaleGlbToDimensions requires positive targets '
          '(got $targetWidthM × $targetHeightM × $targetDepthM m).',
    );
  }

  // Fold non-identity node transforms into the vertex data (identity →
  // same bytes) so the accessor-level bounds and per-axis factors below
  // describe what the renderer will actually show.
  glbBytes = bakeGlbNodeTransforms(glbBytes);

  // Bounds of the WHOLE model (merged over every primitive), used for the
  // per-axis factors and for the Y grounding (minY of the file, so separate
  // primitives stay consistent with each other).
  final bounds = GlbBounds.fromGlbBytes(glbBytes);
  if (bounds.isDegenerate) {
    throw GlbRescaleException('Cannot rescale: source geometry is degenerate '
        '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m).');
  }
  final sx = targetWidthM / bounds.widthM;
  final sy = targetHeightM / bounds.heightM;
  final sz = targetDepthM / bounds.depthM;
  final minY = bounds.minY;

  // One shared parse; the BIN chunk comes back as a mutable private copy.
  final glb = GlbStructure.parse(glbBytes, mutableBin: true);
  final binBytes = glb.binChunk;
  if (binBytes == null) {
    throw const GlbRescaleException('GLB has no BIN chunk — nothing to rescale.');
  }
  final bin = ByteData.sublistView(binBytes);

  // An accessor shared by several primitives must only be patched ONCE
  // (a second pass over already-transformed data would re-scale it).
  final patchedPositions = <int>{};
  final patchedNormals = <int>{};

  for (final primitive in glb.primitives) {
    // strict mode throws on any violation, so the non-null assertion holds.
    final positionAccessor =
        glb.dataAccessor(primitive, 'POSITION')!; // strict — always required
    if (patchedPositions.add(primitive.positionAccessorIndex)) {
      _patchStream(
        accessor: positionAccessor,
        bin: bin,
        transform: (x, y, z) => ((x * sx), (y - minY) * sy, z * sz),
        refreshMinMax: true, // spec REQUIRES min/max on POSITION accessors
      );
    }
    // NORMAL is optional + best-effort: a malformed stream is skipped
    // (strict: false → null) — never an error.
    final normalIndex = primitive.attributes['NORMAL'];
    if (normalIndex is int && patchedNormals.add(normalIndex)) {
      final normalAccessor = glb.dataAccessor(primitive, 'NORMAL',
          strict: false);
      if (normalAccessor != null) {
        _patchStream(
          accessor: normalAccessor,
          bin: bin,
          // Per-axis inverse of the position scale, re-normalized:
          // n' = normalize(nx/sx, ny/sy, nz/sz). A unit vector scaled
          // anisotropically points along the WRONG direction afterwards;
          // normalizing undoes the distortion.
          transform: (nx, ny, nz) {
            final l = math.sqrt(
                (nx * nx) / (sx * sx) +
                    (ny * ny) / (sy * sy) +
                    (nz * nz) / (sz * sz));
            if (!l.isFinite || l < 1e-9) return null; // degenerate — keep
            return (nx / (sx * l), ny / (sy * l), nz / (sz * l));
          },
          refreshMinMax: _jsonHasMinMax(glb, normalIndex),
        );
      }
    }
  }

  return _toBytes(glb, binBytes);
}

/// Reads the transform's inputs, writes its outputs back at the same slot.
/// [transform] returns null to keep an element untouched (degenerate
/// normals). Every write happens after the element's own read, and writes
/// only touch the accessor's own 12-byte slot per element — streams are
/// never re-laid out, and bytes outside the patched ranges are preserved.
void _patchStream({
  required GlbDataAccessor accessor,
  required ByteData bin,
  required (double, double, double)? Function(double x, double y, double z)
      transform,
  required bool refreshMinMax,
}) {
  // dataAccessor already validated elementStart + count + stride inside the
  // BIN chunk. Reads and writes go through the same [bin] view of the
  // mutable private copy — each element is fully read before its own bytes
  // are overwritten, so in-place patching is safe for any stride.
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = double.negativeInfinity,
      maxY = double.negativeInfinity,
      maxZ = double.negativeInfinity;
  var touched = false;

  for (var i = 0; i < accessor.count; i++) {
    final at = accessor.elementStart + i * accessor.byteStride;
    final x = bin.getFloat32(at, Endian.little);
    final y = bin.getFloat32(at + 4, Endian.little);
    final z = bin.getFloat32(at + 8, Endian.little);
    final result = transform(x, y, z);
    if (result == null) continue;
    final (nx, ny, nz) = result;
    bin.setFloat32(at, nx, Endian.little);
    bin.setFloat32(at + 4, ny, Endian.little);
    bin.setFloat32(at + 8, nz, Endian.little);
    if (nx < minX) minX = nx;
    if (ny < minY) minY = ny;
    if (nz < minZ) minZ = nz;
    if (nx > maxX) maxX = nx;
    if (ny > maxY) maxY = ny;
    if (nz > maxZ) maxZ = nz;
    touched = true;
  }

  if (!refreshMinMax) return;
  if (touched) {
    accessor.json['min'] = [minX, minY, minZ];
    accessor.json['max'] = [maxX, maxY, maxZ];
  } else {
    // Every element was skipped (all-degenerate stream): min/max of the
    // stored (unchanged) data still describe the file — rescan rather than
    // invent values.
    var aX = double.infinity, aY = double.infinity, aZ = double.infinity;
    var bX = double.negativeInfinity,
        bY = double.negativeInfinity,
        bZ = double.negativeInfinity;
    for (var i = 0; i < accessor.count; i++) {
      final at = accessor.elementStart + i * accessor.byteStride;
      final x = bin.getFloat32(at, Endian.little);
      final y = bin.getFloat32(at + 4, Endian.little);
      final z = bin.getFloat32(at + 8, Endian.little);
      if (x < aX) aX = x;
      if (y < aY) aY = y;
      if (z < aZ) aZ = z;
      if (x > bX) bX = x;
      if (y > bY) bY = y;
      if (z > bZ) bZ = z;
    }
    accessor.json['min'] = [aX, aY, aZ];
    accessor.json['max'] = [bX, bY, bZ];
  }
}

/// Whether accessor #index already carries min/max keys (so stale metadata
/// gets refreshed rather than newly invented for non-POSITION streams).
bool _jsonHasMinMax(GlbStructure glb, int index) {
  final accessor = glb.rawAccessor(index);
  if (accessor == null) return false;
  return accessor.containsKey('min') || accessor.containsKey('max');
}

/// Re-serializes the GLB: header + re-encoded JSON chunk (space-padded) +
/// patched BIN chunk (NUL-padded) + trailing bytes.
Uint8List _toBytes(GlbStructure glb, Uint8List binBytes) {
  final jsonBytes = _utf8Encode(glb.json);
  final jsonPadded = (jsonBytes.length + 3) & ~3;
  final binPadded = (binBytes.length + 3) & ~3;
  final totalLength = 12 + 8 + jsonPadded + 8 + binPadded + glb.trailing.length;

  final out = BytesBuilder(copy: false);

  final header = ByteData(12);
  header.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, totalLength, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHead = ByteData(8);
  jsonHead.setUint32(0, jsonPadded, Endian.little);
  jsonHead.setUint32(4, 0x4E4F534A, Endian.little); // 'JSON'
  out.add(jsonHead.buffer.asUint8List());
  out.add(jsonBytes);
  // GLB JSON padding must be spaces (0x20), not NULs.
  if (jsonPadded > jsonBytes.length) {
    out.add(Uint8List(jsonPadded - jsonBytes.length)
      ..fillRange(0, jsonPadded - jsonBytes.length, 0x20));
  }

  final binHead = ByteData(8);
  binHead.setUint32(0, binPadded, Endian.little);
  binHead.setUint32(4, 0x004E4942, Endian.little); // 'BIN\0'
  out.add(binHead.buffer.asUint8List());
  out.add(binBytes);
  if (binPadded > binBytes.length) {
    out.add(Uint8List(binPadded - binBytes.length));
  }

  out.add(glb.trailing);
  return out.toBytes();
}

Uint8List _utf8Encode(Map<String, dynamic> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return Uint8List.fromList(bytes);
}

// ─── Node-transform baking ───────────────────────────────────────────────
//
// glTF nodes may carry a transform (matrix OR translation/rotation/scale)
// that the renderer applies on top of the raw POSITION data. The rescaler
// and GlbBounds read ACCESSOR data only, so a model whose node chain holds
// a Z-up→Y-up rotation or a unit scale (common in AI/marketplace exports)
// would be measured, grounded and per-axis scaled against the wrong axes —
// the sofa then rendered too big, floating, or sunk. [bakeGlbNodeTransforms]
// folds every scene-graph node transform into the vertex streams and resets
// those nodes to identity, making accessor-space == world-space. Identity
// files (our own generator, unit-test fixtures) fast-path to the same
// bytes unchanged.

/// Bakes scene-graph node transforms into POSITION/NORMAL vertex data.
///
/// For each mesh whose scene nodes share ONE non-identity matrix, the
/// positions are transformed by that matrix and normals by its
/// inverse-transpose (renormalized); the referencing nodes are then reset
/// to identity. Meshes with several DIFFERENT instance transforms, skinned
/// nodes, or anything unexpected are left untouched (never worse than the
/// previous accessor-only behavior). Identity files return [glbBytes]
/// unchanged, so the function is free on already-baked/procedural models.
Uint8List bakeGlbNodeTransforms(Uint8List glbBytes) {
  final probe = GlbStructure.parse(glbBytes);
  final json = probe.json;
  final nodes = json['nodes'];
  if (nodes is! List || nodes.isEmpty) return glbBytes;

  // Roots: the default scene's nodes, else every node that no one parents.
  final List<int> roots;
  final scenes = json['scenes'];
  final sceneIndex = json['scene'];
  if (scenes is List &&
      sceneIndex is int &&
      sceneIndex >= 0 &&
      sceneIndex < scenes.length &&
      scenes[sceneIndex] is Map &&
      (scenes[sceneIndex] as Map)['nodes'] is List) {
    roots = [
      for (final n in (scenes[sceneIndex] as Map)['nodes'] as List)
        if (n is int && n >= 0 && n < nodes.length) n,
    ];
  } else {
    final hasParent = <int>{};
    for (final node in nodes) {
      if (node is Map && node['children'] is List) {
        for (final c in node['children'] as List) {
          if (c is int) hasParent.add(c);
        }
      }
    }
    roots = [for (var i = 0; i < nodes.length; i++) if (!hasParent.contains(i)) i];
  }
  if (roots.isEmpty) return glbBytes;

  // Compose world matrices down the graph (identity fast-check per node).
  final composed = <int, List<double>>{};
  final visiting = <int>{};
  void walk(int nodeIndex, List<double> parentM, int depth) {
    if (depth > 64 || !visiting.add(nodeIndex)) return; // cycle guard
    final node = nodes[nodeIndex];
    if (node is Map<String, dynamic>) {
      final world = _mat4Multiply(parentM, _nodeLocalMatrix(node));
      composed[nodeIndex] = world;
      final children = node['children'];
      if (children is List) {
        for (final c in children) {
          if (c is int && c >= 0 && c < nodes.length) walk(c, world, depth + 1);
        }
      }
    }
    visiting.remove(nodeIndex);
  }

  var sawSkin = false;
  for (final r in roots) {
    final node = nodes[r];
    if (node is Map && node.containsKey('skin')) sawSkin = true;
    walk(r, _mat4Identity(), 0);
  }
  // Skinned meshes are driven by joints, not the node matrix — leave them.
  if (sawSkin || composed.isEmpty) return glbBytes;

  // Fast path: no mesh-referencing node has a non-identity transform.
  bool needsBake = false;
  for (final entry in composed.entries) {
    final node = nodes[entry.key];
    if (node is Map &&
        node['mesh'] is int &&
        !_isIdentityMat4(entry.value)) {
      needsBake = true;
      break;
    }
  }
  if (!needsBake) return glbBytes;

  // Re-parse with a mutable BIN copy and patch vertex floats in place.
  final glb = GlbStructure.parse(glbBytes, mutableBin: true);
  final binChunk = glb.binChunk;
  final meshes = glb.json['meshes'];
  if (binChunk == null || meshes is! List) return glbBytes;
  final bin = ByteData.sublistView(binChunk);

  // Group mesh-referencing scene nodes by mesh index.
  final meshInstances = <int, List<int>>{};
  for (final entry in composed.entries) {
    final node = nodes[entry.key];
    if (node is Map && node['mesh'] is int) {
      final meshIndex = node['mesh'] as int;
      if (meshIndex >= 0 && meshIndex < meshes.length) {
        meshInstances.putIfAbsent(meshIndex, () => []).add(entry.key);
      }
    }
  }

  for (final entry in meshInstances.entries) {
    final meshIndex = entry.key;
    final nodeIndices = entry.value;

    // One shared matrix for every instance of this mesh?
    final shared = composed[nodeIndices.first]!;
    var uniform = true;
    for (final ni in nodeIndices.skip(1)) {
      if (!_mat4Equals(shared, composed[ni]!)) {
        uniform = false;
        break;
      }
    }
    if (!uniform || _isIdentityMat4(shared)) continue;

    final mesh = meshes[meshIndex];
    if (mesh is! Map<String, dynamic>) continue;

    // Validate EVERY primitive's POSITION stream BEFORE patching anything —
    // a half-patched mesh would render wrong. An invalid stream leaves the
    // whole mesh untouched (the rescaler surfaces its own error later).
    final meshPrimitives =
        glb.primitives.where((p) => p.meshIndex == meshIndex).toList();
    final positions = <GlbPrimitive, GlbDataAccessor>{};
    var valid = true;
    try {
      for (final gp in meshPrimitives) {
        final position = glb.dataAccessor(gp, 'POSITION');
        if (position == null) {
          valid = false;
          break;
        }
        positions[gp] = position;
      }
    } on GlbParseException {
      valid = false;
    }
    if (!valid) continue;

    for (final gp in meshPrimitives) {
      _patchStream(
        accessor: positions[gp]!,
        bin: bin,
        transform: (x, y, z) {
          final v = _transformPoint(shared, x, y, z);
          return (v[0], v[1], v[2]);
        },
        refreshMinMax: true, // spec REQUIRES min/max on POSITION
      );
      final normalIndex = gp.attributes['NORMAL'];
      if (normalIndex is int) {
        final normal = glb.dataAccessor(gp, 'NORMAL', strict: false);
        if (normal != null) {
          final invT = _inverseTranspose3(shared);
          _patchStream(
            accessor: normal,
            bin: bin,
            transform: (nx, ny, nz) {
              if (invT == null) return null; // singular — keep original
              final x = invT[0] * nx + invT[1] * ny + invT[2] * nz;
              final y = invT[3] * nx + invT[4] * ny + invT[5] * nz;
              final z = invT[6] * nx + invT[7] * ny + invT[8] * nz;
              final l = math.sqrt(x * x + y * y + z * z);
              if (!l.isFinite || l < 1e-9) return null; // keep
              return (x / l, y / l, z / l);
            },
            refreshMinMax: _jsonHasMinMax(glb, normalIndex),
          );
        }
      }
    }

    // Baked — reset every referencing node to identity (no matrix/TRS).
    // NOTE: mutate the RE-PARSED glb.json (the object _toBytes serializes),
    // not the earlier probe copy — they are distinct maps from two parses.
    final outNodes = glb.json['nodes'];
    for (final ni in nodeIndices) {
      final node =
          outNodes is List && ni >= 0 && ni < outNodes.length ? outNodes[ni] : null;
      if (node is Map<String, dynamic>) {
        node.remove('matrix');
        node.remove('translation');
        node.remove('rotation');
        node.remove('scale');
      }
    }
  }

  return _toBytes(glb, binChunk);
}

/// Column-major 4×4 identity (glTF storage order).
List<double> _mat4Identity() =>
    <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

/// Column-major 4×4 multiply: `a * b` (apply b first, then a).
List<double> _mat4Multiply(List<double> a, List<double> b) {
  final c = List<double>.filled(16, 0);
  for (var col = 0; col < 4; col++) {
    for (var row = 0; row < 4; row++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[k * 4 + row] * b[col * 4 + k];
      }
      c[col * 4 + row] = sum;
    }
  }
  return c;
}

bool _mat4Equals(List<double> a, List<double> b) {
  for (var i = 0; i < 16; i++) {
    if ((a[i] - b[i]).abs() > 1e-6) return false;
  }
  return true;
}

bool _isIdentityMat4(List<double> m) => _mat4Equals(m, _mat4Identity());

/// The node's local transform: `matrix` when present, else T·R·S from
/// translation / rotation (quaternion [x,y,z,w]) / scale. Defaults per glTF.
List<double> _nodeLocalMatrix(Map<String, dynamic> node) {
  final matrix = node['matrix'];
  if (matrix is List && matrix.length == 16) {
    return [for (final v in matrix) (v as num).toDouble()];
  }
  final t = node['translation'];
  final r = node['rotation'];
  final s = node['scale'];
  final tx = t is List && t.length >= 3 ? (t[0] as num).toDouble() : 0.0;
  final ty = t is List && t.length >= 3 ? (t[1] as num).toDouble() : 0.0;
  final tz = t is List && t.length >= 3 ? (t[2] as num).toDouble() : 0.0;
  final qx = r is List && r.length >= 4 ? (r[0] as num).toDouble() : 0.0;
  final qy = r is List && r.length >= 4 ? (r[1] as num).toDouble() : 0.0;
  final qz = r is List && r.length >= 4 ? (r[2] as num).toDouble() : 0.0;
  final qw = r is List && r.length >= 4 ? (r[3] as num).toDouble() : 1.0;
  final sx = s is List && s.length >= 3 ? (s[0] as num).toDouble() : 1.0;
  final sy = s is List && s.length >= 3 ? (s[1] as num).toDouble() : 1.0;
  final sz = s is List && s.length >= 3 ? (s[2] as num).toDouble() : 1.0;

  // Rotation matrix from the unit quaternion (column-major).
  final x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  final xx = qx * x2, xy = qx * y2, xz = qx * z2;
  final yy = qy * y2, yz = qy * z2, zz = qz * z2;
  final wx = qw * x2, wy = qw * y2, wz = qw * z2;
  return <double>[
    (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0, //
    (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0, //
    (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0, //
    tx, ty, tz, 1,
  ];
}

/// Affine point transform: `M · (x, y, z, 1)`.
List<double> _transformPoint(List<double> m, double x, double y, double z) {
  return [
    m[0] * x + m[4] * y + m[8] * z + m[12],
    m[1] * x + m[5] * y + m[9] * z + m[13],
    m[2] * x + m[6] * y + m[10] * z + m[14],
  ];
}

/// Row-major 3×3 transpose(inverse(M₃)) for NORMAL streams, or null when
/// the matrix is singular (caller keeps the original normals).
List<double>? _inverseTranspose3(List<double> m) {
  final a00 = m[0], a01 = m[4], a02 = m[8];
  final a10 = m[1], a11 = m[5], a12 = m[9];
  final a20 = m[2], a21 = m[6], a22 = m[10];
  final det = a00 * (a11 * a22 - a12 * a21) -
      a01 * (a10 * a22 - a12 * a20) +
      a02 * (a10 * a21 - a11 * a20);
  if (!det.isFinite || det.abs() < 1e-12) return null;
  // adjugate / det == inverse; then transpose by swapping index roles below.
  final b00 = (a11 * a22 - a12 * a21) / det;
  final b01 = (a02 * a21 - a01 * a22) / det;
  final b02 = (a01 * a12 - a02 * a11) / det;
  final b10 = (a12 * a20 - a10 * a22) / det;
  final b11 = (a00 * a22 - a02 * a20) / det;
  final b12 = (a02 * a10 - a00 * a12) / det;
  final b20 = (a10 * a21 - a11 * a20) / det;
  final b21 = (a01 * a20 - a00 * a21) / det;
  final b22 = (a00 * a11 - a01 * a10) / det;
  // transpose(inverse) applied as row-major rows:
  return <double>[
    b00, b10, b20, //
    b01, b11, b21, //
    b02, b12, b22, //
  ];
}
