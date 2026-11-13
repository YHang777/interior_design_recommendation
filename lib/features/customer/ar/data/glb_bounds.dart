import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class GlbParseException implements Exception {
  const GlbParseException(this.message);

  final String message;

  @override
  String toString() => 'GlbParseException: $message';
}

class GlbBounds {
  const GlbBounds({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  });

  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;

  double get widthM => maxX - minX;
  double get heightM => maxY - minY;
  double get depthM => maxZ - minZ;

  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get centerZ => (minZ + maxZ) / 2;

  double get maxExtent => math.max(widthM, math.max(heightM, depthM));

  bool get isDegenerate => widthM <= 0 || heightM <= 0 || depthM <= 0;

  static GlbBounds fromGlbBytes(Uint8List bytes) {
    final glb = GlbStructure.parse(bytes);
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    var found = false;

    void merge(double x, double y, double z) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
      found = true;
    }

    for (final primitive in glb.primitives) {
      final accessorJson = glb.rawAccessor(primitive.positionAccessorIndex);
      final minV = accessorJson == null
          ? null
          : GlbStructure.finiteMinMax(accessorJson['min']);
      final maxV = accessorJson == null
          ? null
          : GlbStructure.finiteMinMax(accessorJson['max']);
      if (minV != null && maxV != null) {
        merge(minV[0], minV[1], minV[2]);
        merge(maxV[0], maxV[1], maxV[2]);
        continue;
      }
      final accessor = glb.dataAccessor(primitive, 'POSITION')!;
      final binData = ByteData.sublistView(glb.binChunk!);
      for (var i = 0; i < accessor.count; i++) {
        final at = accessor.elementStart + i * accessor.byteStride;
        merge(
          binData.getFloat32(at, Endian.little),
          binData.getFloat32(at + 4, Endian.little),
          binData.getFloat32(at + 8, Endian.little),
        );
      }
    }

    if (!found) {
      throw const GlbParseException('GLB contains no POSITION geometry — '
          'cannot compute bounds.');
    }
    return GlbBounds(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }

  // Bounds as the renderer sees the model: every mesh's POSITION box pushed
  // through its node's world transform (matrix or TRS, composed down the
  // default scene). Bundled catalog GLBs carry Z-up→Y-up rotations and unit
  // scales (0.01, 5.53 …) on their nodes; fitting a seller box against raw
  // accessor bounds swapped height/depth and blew pieces up to room size or
  // shrank them to millimetres. Raw [fromGlbBytes] stays for callers that
  // rewrite vertex data directly (glb_rescaler).
  static GlbBounds sceneFromGlbBytes(Uint8List bytes) {
    final glb = GlbStructure.parse(bytes);
    final json = glb.json;
    final nodes = json['nodes'];
    final meshes = json['meshes'];
    if (nodes is! List || meshes is! List || nodes.isEmpty) {
      return fromGlbBytes(bytes);
    }
    List<int> roots;
    final scenes = json['scenes'];
    final sceneIdx = json['scene'] is int ? json['scene'] as int : 0;
    if (scenes is List &&
        sceneIdx >= 0 &&
        sceneIdx < scenes.length &&
        scenes[sceneIdx] is Map &&
        (scenes[sceneIdx] as Map)['nodes'] is List) {
      roots = [
        for (final n in (scenes[sceneIdx] as Map)['nodes'] as List)
          if (n is int) n,
      ];
    } else {
      final children = <int>{};
      for (final n in nodes) {
        if (n is Map && n['children'] is List) {
          for (final c in n['children'] as List) {
            if (c is int) children.add(c);
          }
        }
      }
      roots = [
        for (var i = 0; i < nodes.length; i++)
          if (!children.contains(i)) i,
      ];
    }

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    var found = false;

    List<double>? boxOf(int accessorIndex) {
      final a = glb.rawAccessor(accessorIndex);
      if (a == null) return null;
      final lo = GlbStructure.finiteMinMax(a['min']);
      final hi = GlbStructure.finiteMinMax(a['max']);
      if (lo == null || hi == null) return null;
      return [lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]];
    }

    void visit(int idx, List<double> parent, int depth) {
      if (depth > 64 || idx < 0 || idx >= nodes.length) return;
      final node = nodes[idx];
      if (node is! Map) return;
      final world = _mul(parent, _localMatrix(node));
      final meshIdx = node['mesh'];
      if (meshIdx is int && meshIdx >= 0 && meshIdx < meshes.length) {
        final mesh = meshes[meshIdx];
        final prims = mesh is Map ? mesh['primitives'] : null;
        if (prims is List) {
          for (final p in prims) {
            final attrs = p is Map ? p['attributes'] : null;
            final pos = attrs is Map ? attrs['POSITION'] : null;
            if (pos is! int) continue;
            final box = boxOf(pos);
            if (box == null) continue;
            for (var c = 0; c < 8; c++) {
              final x = (c & 1) == 0 ? box[0] : box[3];
              final y = (c & 2) == 0 ? box[1] : box[4];
              final z = (c & 4) == 0 ? box[2] : box[5];
              final wx = world[0] * x + world[4] * y + world[8] * z + world[12];
              final wy = world[1] * x + world[5] * y + world[9] * z + world[13];
              final wz = world[2] * x + world[6] * y + world[10] * z + world[14];
              if (wx < minX) minX = wx;
              if (wy < minY) minY = wy;
              if (wz < minZ) minZ = wz;
              if (wx > maxX) maxX = wx;
              if (wy > maxY) maxY = wy;
              if (wz > maxZ) maxZ = wz;
              found = true;
            }
          }
        }
      }
      final children = node['children'];
      if (children is List) {
        for (final c in children) {
          if (c is int) visit(c, world, depth + 1);
        }
      }
    }

    const identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
    for (final r in roots) {
      visit(r, identity, 0);
    }
    if (!found || !minX.isFinite || !maxX.isFinite) return fromGlbBytes(bytes);
    return GlbBounds(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }

  // Column-major 4×4, glTF convention: matrix wins, else T · R · S.
  static List<double> _localMatrix(Map node) {
    final m = node['matrix'];
    if (m is List && m.length == 16 && m.every((v) => v is num)) {
      return [for (final v in m) (v as num).toDouble()];
    }
    List<double> vec(Object? v, List<double> dflt) =>
        v is List && v.length == dflt.length && v.every((e) => e is num)
            ? [for (final e in v) (e as num).toDouble()]
            : dflt;
    final t = vec(node['translation'], const [0, 0, 0]);
    final q = vec(node['rotation'], const [0, 0, 0, 1]);
    final s = vec(node['scale'], const [1, 1, 1]);
    final x = q[0], y = q[1], z = q[2], w = q[3];
    final r00 = 1 - 2 * (y * y + z * z);
    final r01 = 2 * (x * y - z * w);
    final r02 = 2 * (x * z + y * w);
    final r10 = 2 * (x * y + z * w);
    final r11 = 1 - 2 * (x * x + z * z);
    final r12 = 2 * (y * z - x * w);
    final r20 = 2 * (x * z - y * w);
    final r21 = 2 * (y * z + x * w);
    final r22 = 1 - 2 * (x * x + y * y);
    return [
      r00 * s[0], r10 * s[0], r20 * s[0], 0,
      r01 * s[1], r11 * s[1], r21 * s[1], 0,
      r02 * s[2], r12 * s[2], r22 * s[2], 0,
      t[0], t[1], t[2], 1,
    ];
  }

  static List<double> _mul(List<double> a, List<double> b) {
    final out = List<double>.filled(16, 0);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[k * 4 + row] * b[col * 4 + k];
        }
        out[col * 4 + row] = sum;
      }
    }
    return out;
  }

  @override
  String toString() =>
      'GlbBounds(min=($minX, $minY, $minZ), max=($maxX, $maxY, $maxZ), '
      'size=${widthM.toStringAsFixed(3)} x ${heightM.toStringAsFixed(3)} x '
      '${depthM.toStringAsFixed(3)} m)';
}

class GlbPrimitive {
  GlbPrimitive._(this.meshIndex, this.primitiveIndex, this.attributes);

  final int meshIndex;
  final int primitiveIndex;

  final Map<String, dynamic> attributes;

  int get positionAccessorIndex {
    final idx = attributes['POSITION'];
    return idx is int ? idx : -1;
  }

  String get context => 'Mesh #$meshIndex primitive #$primitiveIndex';
}

class GlbDataAccessor {
  GlbDataAccessor._({
    required this.json,
    required this.count,
    required this.byteStride,
    required this.elementStart,
  });

  final Map<String, dynamic> json;

  final int count;

  final int byteStride;

  final int elementStart;
}

class GlbStructure {
  GlbStructure._({
    required this.json,
    required this.jsonChunkBytes,
    required this.binChunk,
    required this.trailing,
    required this.primitives,
  });

  static const int _magic = 0x46546C67;
  static const int _chunkJson = 0x4E4F534A;
  static const int _chunkBin = 0x004E4942;
  static const int _headerSize = 12;
  static const int _chunkHeaderSize = 8;

  static const int _componentFloat = 5126;
  static const int _floatBytes = 4;
  static const int _vec3Floats = 3;

  final Map<String, dynamic> json;

  final Uint8List jsonChunkBytes;

  final Uint8List? binChunk;

  final Uint8List trailing;

  final List<GlbPrimitive> primitives;

  static GlbStructure parse(Uint8List bytes, {bool mutableBin = false}) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < _headerSize) {
      throw const GlbParseException('File too short to hold a GLB header '
          '(12 bytes) — not a valid .glb.');
    }
    final magic = data.getUint32(0, Endian.little);
    if (magic != _magic) {
      throw GlbParseException('Invalid GLB magic 0x${magic.toRadixString(16)} '
          '— expected "glTF" (0x46546C67). Not a binary glTF 2.0 file.');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != 2) {
      throw GlbParseException('Unsupported GLB version $version — only '
          'glTF 2.0 (version 2) is supported.');
    }
    final declaredLength = data.getUint32(8, Endian.little);
    if (declaredLength > bytes.length) {
      throw GlbParseException('GLB header declares $declaredLength bytes but '
          'only ${bytes.length} were provided — file is truncated.');
    }
    final effectiveLength =
        declaredLength < bytes.length ? declaredLength : bytes.length;

    // ── Collect the JSON chunk and the BIN chunk ──────────────────────────
    Uint8List? jsonChunk;
    Uint8List? binChunk;
    var binEnd = effectiveLength;
    var offset = _headerSize;
    while (offset + _chunkHeaderSize <= effectiveLength) {
      final chunkLength = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + _chunkHeaderSize;
      if (chunkStart + chunkLength > effectiveLength) {
        throw GlbParseException('GLB chunk (type 0x${chunkType.toRadixString(16)}) '
            'declares $chunkLength bytes but exceeds the file length.');
      }
      if (chunkType == _chunkJson && jsonChunk == null) {
        jsonChunk =
            Uint8List.sublistView(bytes, chunkStart, chunkStart + chunkLength);
      } else if (chunkType == _chunkBin && binChunk == null) {
        binChunk =
            Uint8List.sublistView(bytes, chunkStart, chunkStart + chunkLength);
        binEnd = chunkStart + chunkLength;
      }
      offset = chunkStart + chunkLength;
    }
    if (jsonChunk == null) {
      throw const GlbParseException('No JSON chunk found in GLB — malformed '
          'binary glTF file.');
    }

    // ── Parse the JSON chunk ──────────────────────────────────────────────
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(jsonChunk, allowMalformed: true));
    } on FormatException catch (e) {
      throw GlbParseException('GLB JSON chunk is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const GlbParseException('GLB JSON chunk is not a JSON object.');
    }
    final json = decoded;

    final buffers = json['buffers'];
    final bufferViews = json['bufferViews'];
    final accessors = json['accessors'];
    final meshes = json['meshes'];
    if (buffers is! List || bufferViews is! List || accessors is! List ||
        meshes is! List) {
      throw const GlbParseException('GLB JSON is missing one of '
          '"buffers", "bufferViews", "accessors" or "meshes" — not a valid '
          'glTF 2.0 asset.');
    }
    if (buffers.length != 1) {
      throw GlbParseException('Expected a single GLB buffer, found '
          '${buffers.length}.');
    }

    // ── Structurally validate every mesh / primitive / POSITION link ──────
    final primitives = <GlbPrimitive>[];
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      final mesh = meshes[meshIndex];
      if (mesh is! Map<String, dynamic>) {
        throw GlbParseException('Mesh #$meshIndex is not a JSON object.');
      }
      final primitiveList = mesh['primitives'];
      if (primitiveList is! List) {
        throw GlbParseException('Mesh #$meshIndex has no "primitives" list.');
      }
      for (var p = 0; p < primitiveList.length; p++) {
        final primitiveJson = primitiveList[p];
        if (primitiveJson is! Map<String, dynamic>) {
          throw GlbParseException(
              'Mesh #$meshIndex primitive #$p is not a JSON object.');
        }
        final attributes = primitiveJson['attributes'];
        if (attributes is! Map<String, dynamic>) {
          throw GlbParseException(
              'Mesh #$meshIndex primitive #$p has no "attributes".');
        }
        final positionIndex = attributes['POSITION'];
        if (positionIndex is! int ||
            positionIndex < 0 ||
            positionIndex >= accessors.length) {
          throw GlbParseException('Mesh #$meshIndex primitive #$p has no '
              'valid POSITION accessor.');
        }
        if (accessors[positionIndex] is! Map<String, dynamic>) {
          throw GlbParseException('Mesh #$meshIndex primitive #$p: accessor '
              '#$positionIndex is not a JSON object.');
        }
        primitives.add(GlbPrimitive._(meshIndex, p, attributes));
      }
    }

    return GlbStructure._(
      json: json,
      jsonChunkBytes: jsonChunk,
      binChunk: binChunk == null
          ? null
          : (mutableBin ? Uint8List.fromList(binChunk) : binChunk),
      trailing: Uint8List.sublistView(bytes, binEnd, effectiveLength),
      primitives: primitives,
    );
  }

  Map<String, dynamic>? rawAccessor(int index) {
    final accessors = json['accessors'];
    if (accessors is! List || index < 0 || index >= accessors.length) {
      return null;
    }
    final a = accessors[index];
    return a is Map<String, dynamic> ? a : null;
  }

  GlbDataAccessor? dataAccessor(
    GlbPrimitive primitive,
    String semantic, {
    bool strict = true,
  }) {
    final accessors = json['accessors'];
    final bufferViews = json['bufferViews'];
    if (accessors is! List || bufferViews is! List) {
      if (strict) {
        throw const GlbParseException('GLB JSON is missing "accessors" or '
            '"bufferViews".');
      }
      return null;
    }
    void fail(String message) {
      if (strict) throw GlbParseException(message);
    }

    final index = primitive.attributes[semantic];
    if (index is! int || index < 0 || index >= accessors.length) {
      fail('${primitive.context}: attribute "$semantic" has no valid '
          'accessor index.');
      return null;
    }
    final accessor = accessors[index];
    if (accessor is! Map<String, dynamic>) {
      fail('${primitive.context}: accessor #$index for "$semantic" is not a '
          'JSON object.');
      return null;
    }
    if (accessor.containsKey('sparse')) {
      fail('${primitive.context}: accessor #$index for "$semantic" uses a '
          'sparse accessor, which cannot be read from the BIN chunk. '
          'Re-export without sparse encoding.');
      return null;
    }
    final type = accessor['type'];
    if (type != 'VEC3') {
      fail('${primitive.context}: accessor #$index for "$semantic" has type '
          '"$type"; expected "VEC3".');
      return null;
    }
    final componentType = accessor['componentType'];
    if (componentType != _componentFloat) {
      fail('${primitive.context}: accessor #$index for "$semantic" has '
          'componentType $componentType; expected 5126 (float).');
      return null;
    }
    final count = accessor['count'];
    if (count is! int || count <= 0) {
      fail('${primitive.context}: accessor #$index for "$semantic" has an '
          'invalid count: $count.');
      return null;
    }
    final bufferViewIndex = accessor['bufferView'];
    if (bufferViewIndex is! int ||
        bufferViewIndex < 0 ||
        bufferViewIndex >= bufferViews.length) {
      fail('${primitive.context}: accessor #$index for "$semantic" '
          'references no valid bufferView.');
      return null;
    }
    final bufferView = bufferViews[bufferViewIndex];
    if (bufferView is! Map<String, dynamic>) {
      fail('${primitive.context}: bufferView #$bufferViewIndex is not a JSON '
          'object.');
      return null;
    }
    final bufferIndex = bufferView['buffer'];
    if (bufferIndex is int && bufferIndex != 0) {
      fail('${primitive.context}: accessor #$index for "$semantic" references '
          'buffer $bufferIndex but GLB files carry a single buffer (0).');
      return null;
    }
    final bufferStart = (bufferView['byteOffset'] as num?)?.toInt() ?? 0;
    final accessorOffset = (accessor['byteOffset'] as num?)?.toInt() ?? 0;
    final byteStride = (bufferView['byteStride'] as num?)?.toInt() ??
        _floatBytes * _vec3Floats;
    if (byteStride < _floatBytes * _vec3Floats) {
      fail('${primitive.context}: accessor #$index for "$semantic" sits on a '
          'bufferView with an impossibly small stride ($byteStride < 12).');
      return null;
    }
    final bin = binChunk;
    if (bin == null) {
      fail('${primitive.context}: accessor #$index for "$semantic" requires '
          'the BIN chunk, but the GLB has none.');
      return null;
    }
    final start = bufferStart + accessorOffset;
    final lastByte =
        start + (count - 1) * byteStride + _floatBytes * _vec3Floats;
    if (start < 0 || lastByte > bin.length) {
      fail('${primitive.context}: accessor #$index for "$semantic" vertex '
          'data lies outside the BIN chunk.');
      return null;
    }
    return GlbDataAccessor._(
      json: accessor,
      count: count,
      byteStride: byteStride,
      elementStart: start,
    );
  }

  static List<double>? finiteMinMax(Object? list) {
    if (list is! List || list.length < 3) return null;
    final out = <double>[];
    for (var i = 0; i < 3; i++) {
      final v = list[i];
      if (v is! num || !v.toDouble().isFinite) return null;
      out.add(v.toDouble());
    }
    return out;
  }
}
