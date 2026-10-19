import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../../models/product.dart';
import 'glb_bounds.dart';

class GlbRescaleException implements Exception {
  const GlbRescaleException(this.message);

  final String message;

  @override
  String toString() => 'GlbRescaleException: $message';
}

class MissingDimensionsException implements Exception {
  const MissingDimensionsException();

  @override
  String toString() => 'MissingDimensionsException: the product declares no '
      'Width/Height/Depth (meters).';
}

bool hasAnySellerDimension(ProductDimensions? dims) =>
    dims != null && (dims.widthM > 0 || dims.heightM > 0 || dims.depthM > 0);

double _normalizeSellerMeters(double v) => v > 10.0 ? v / 100.0 : v;

Uint8List rescaleGlbToSellerSize(Uint8List glbBytes, ProductDimensions? dims) {
  if (!hasAnySellerDimension(dims)) throw const MissingDimensionsException();
  glbBytes = bakeGlbNodeTransforms(glbBytes);
  final d = dims!;
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

  glbBytes = bakeGlbNodeTransforms(glbBytes);

  final bounds = GlbBounds.fromGlbBytes(glbBytes);
  if (bounds.isDegenerate) {
    throw GlbRescaleException('Cannot rescale: source geometry is degenerate '
        '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m).');
  }
  final sx = targetWidthM / bounds.widthM;
  final sy = targetHeightM / bounds.heightM;
  final sz = targetDepthM / bounds.depthM;
  final minY = bounds.minY;

  final glb = GlbStructure.parse(glbBytes, mutableBin: true);
  final binBytes = glb.binChunk;
  if (binBytes == null) {
    throw const GlbRescaleException('GLB has no BIN chunk — nothing to rescale.');
  }
  final bin = ByteData.sublistView(binBytes);

  final patchedPositions = <int>{};
  final patchedNormals = <int>{};

  for (final primitive in glb.primitives) {
    final positionAccessor =
        glb.dataAccessor(primitive, 'POSITION')!;
    if (patchedPositions.add(primitive.positionAccessorIndex)) {
      _patchStream(
        accessor: positionAccessor,
        bin: bin,
        transform: (x, y, z) => ((x * sx), (y - minY) * sy, z * sz),
        refreshMinMax: true,
      );
    }
    final normalIndex = primitive.attributes['NORMAL'];
    if (normalIndex is int && patchedNormals.add(normalIndex)) {
      final normalAccessor = glb.dataAccessor(primitive, 'NORMAL',
          strict: false);
      if (normalAccessor != null) {
        _patchStream(
          accessor: normalAccessor,
          bin: bin,
          transform: (nx, ny, nz) {
            final l = math.sqrt(
                (nx * nx) / (sx * sx) +
                    (ny * ny) / (sy * sy) +
                    (nz * nz) / (sz * sz));
            if (!l.isFinite || l < 1e-9) return null;
            return (nx / (sx * l), ny / (sy * l), nz / (sz * l));
          },
          refreshMinMax: _jsonHasMinMax(glb, normalIndex),
        );
      }
    }
  }

  return _toBytes(glb, binBytes);
}

void _patchStream({
  required GlbDataAccessor accessor,
  required ByteData bin,
  required (double, double, double)? Function(double x, double y, double z)
      transform,
  required bool refreshMinMax,
}) {
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

bool _jsonHasMinMax(GlbStructure glb, int index) {
  final accessor = glb.rawAccessor(index);
  if (accessor == null) return false;
  return accessor.containsKey('min') || accessor.containsKey('max');
}

Uint8List _toBytes(GlbStructure glb, Uint8List binBytes) {
  final jsonBytes = _utf8Encode(glb.json);
  final jsonPadded = (jsonBytes.length + 3) & ~3;
  final binPadded = (binBytes.length + 3) & ~3;
  final totalLength = 12 + 8 + jsonPadded + 8 + binPadded + glb.trailing.length;

  final out = BytesBuilder(copy: false);

  final header = ByteData(12);
  header.setUint32(0, 0x46546C67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, totalLength, Endian.little);
  out.add(header.buffer.asUint8List());

  final jsonHead = ByteData(8);
  jsonHead.setUint32(0, jsonPadded, Endian.little);
  jsonHead.setUint32(4, 0x4E4F534A, Endian.little);
  out.add(jsonHead.buffer.asUint8List());
  out.add(jsonBytes);
  if (jsonPadded > jsonBytes.length) {
    out.add(Uint8List(jsonPadded - jsonBytes.length)
      ..fillRange(0, jsonPadded - jsonBytes.length, 0x20));
  }

  final binHead = ByteData(8);
  binHead.setUint32(0, binPadded, Endian.little);
  binHead.setUint32(4, 0x004E4942, Endian.little);
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

Uint8List bakeGlbNodeTransforms(Uint8List glbBytes) {
  final probe = GlbStructure.parse(glbBytes);
  final json = probe.json;
  final nodes = json['nodes'];
  if (nodes is! List || nodes.isEmpty) return glbBytes;

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

  final composed = <int, List<double>>{};
  final visiting = <int>{};
  void walk(int nodeIndex, List<double> parentM, int depth) {
    if (depth > 64 || !visiting.add(nodeIndex)) return;
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
  if (sawSkin || composed.isEmpty) return glbBytes;

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

  final glb = GlbStructure.parse(glbBytes, mutableBin: true);
  final binChunk = glb.binChunk;
  final meshes = glb.json['meshes'];
  if (binChunk == null || meshes is! List) return glbBytes;
  final bin = ByteData.sublistView(binChunk);

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
        refreshMinMax: true,
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
              if (invT == null) return null;
              final x = invT[0] * nx + invT[1] * ny + invT[2] * nz;
              final y = invT[3] * nx + invT[4] * ny + invT[5] * nz;
              final z = invT[6] * nx + invT[7] * ny + invT[8] * nz;
              final l = math.sqrt(x * x + y * y + z * z);
              if (!l.isFinite || l < 1e-9) return null;
              return (x / l, y / l, z / l);
            },
            refreshMinMax: _jsonHasMinMax(glb, normalIndex),
          );
        }
      }
    }

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

List<double> _mat4Identity() =>
    <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

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

  final x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  final xx = qx * x2, xy = qx * y2, xz = qx * z2;
  final yy = qy * y2, yz = qy * z2, zz = qz * z2;
  final wx = qw * x2, wy = qw * y2, wz = qw * z2;
  return <double>[
    (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
    (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
    (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
    tx, ty, tz, 1,
  ];
}

List<double> _transformPoint(List<double> m, double x, double y, double z) {
  return [
    m[0] * x + m[4] * y + m[8] * z + m[12],
    m[1] * x + m[5] * y + m[9] * z + m[13],
    m[2] * x + m[6] * y + m[10] * z + m[14],
  ];
}

List<double>? _inverseTranspose3(List<double> m) {
  final a00 = m[0], a01 = m[4], a02 = m[8];
  final a10 = m[1], a11 = m[5], a12 = m[9];
  final a20 = m[2], a21 = m[6], a22 = m[10];
  final det = a00 * (a11 * a22 - a12 * a21) -
      a01 * (a10 * a22 - a12 * a20) +
      a02 * (a10 * a21 - a11 * a20);
  if (!det.isFinite || det.abs() < 1e-12) return null;
  final b00 = (a11 * a22 - a12 * a21) / det;
  final b01 = (a02 * a21 - a01 * a22) / det;
  final b02 = (a01 * a12 - a02 * a11) / det;
  final b10 = (a12 * a20 - a10 * a22) / det;
  final b11 = (a00 * a22 - a02 * a20) / det;
  final b12 = (a02 * a10 - a00 * a12) / det;
  final b20 = (a10 * a21 - a11 * a20) / det;
  final b21 = (a01 * a20 - a00 * a21) / det;
  final b22 = (a00 * a11 - a01 * a10) / det;
  return <double>[
    b00, b10, b20,
    b01, b11, b21,
    b02, b12, b22,
  ];
}
