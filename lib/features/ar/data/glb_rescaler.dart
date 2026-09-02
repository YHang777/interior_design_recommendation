import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
