import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Thrown when a byte sequence cannot be parsed as a glTF 2.0 GLB.
class GlbParseException implements Exception {
  const GlbParseException(this.message);

  final String message;

  @override
  String toString() => 'GlbParseException: $message';
}

/// Axis-aligned bounding box of the POSITION geometry of a parsed GLB,
/// computed in the file's own coordinate system / units (we author all
/// generated models in meters, so the extents are real-world meters).
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

  /// Largest of the three extents (the AR plugin's scale-to-unit-cube value).
  double get maxExtent => math.max(widthM, math.max(heightM, depthM));

  bool get isDegenerate => widthM <= 0 || heightM <= 0 || depthM <= 0;

  /// Parses a GLB (binary glTF 2.0) file from raw bytes and returns the
  /// bounding box covering **every** mesh primitive's POSITION data.
  ///
  /// Prefers each POSITION accessor's `min`/`max` (which the glTF spec
  /// requires on POSITION accessors). When those arrays are missing or
  /// malformed it falls back to scanning the raw vertex floats inside the
  /// BIN chunk. All parsing / validation is delegated to
  /// [GlbStructure.parse] — the ONE shared GLB reader (the rescaler
  /// consumes the same structure; there is no second parser to drift).
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
      // glTF: POSITION accessors must carry min/max — prefer them.
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
      // Fallback: scan the raw float32s. dataAccessor is the single accessor
      // validation (VEC3 float, count, stride >= 12, data inside BIN) — it
      // throws on violations in strict mode, so the non-null assertion holds.
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

  @override
  String toString() =>
      'GlbBounds(min=($minX, $minY, $minZ), max=($maxX, $maxY, $maxZ), '
      'size=${widthM.toStringAsFixed(3)} x ${heightM.toStringAsFixed(3)} x '
      '${depthM.toStringAsFixed(3)} m)';
}

/// One mesh primitive with its (structurally validated) attribute map.
class GlbPrimitive {
  GlbPrimitive._(this.meshIndex, this.primitiveIndex, this.attributes);

  final int meshIndex;
  final int primitiveIndex;

  /// The primitive's `attributes` map (semantic → accessor index).
  final Map<String, dynamic> attributes;

  /// POSITION accessor index — parse-time validated to be a valid in-range
  /// int for every primitive.
  int get positionAccessorIndex {
    final idx = attributes['POSITION'];
    return idx is int ? idx : -1;
  }

  String get context => 'Mesh #$meshIndex primitive #$primitiveIndex';
}

/// Fully resolved + validated descriptor of one attribute's data stream
/// (returned by [GlbStructure.dataAccessor] — the single accessor
/// validation implementation).
class GlbDataAccessor {
  GlbDataAccessor._({
    required this.json,
    required this.count,
    required this.byteStride,
    required this.elementStart,
  });

  /// The raw accessor JSON (the rescaler rewrites `min`/`max` on it).
  final Map<String, dynamic> json;

  /// Number of elements (validated > 0, VEC3 float).
  final int count;

  /// Byte offset between consecutive elements (validated >= 12).
  final int byteStride;

  /// Absolute offset of element 0 inside the BIN chunk.
  final int elementStart;
}

/// Shared low-level GLB reader.
///
/// This is the ONLY place that walks the GLB container and validates
/// accessor/bufferView chains. [GlbBounds.fromGlbBytes] and the rescaler
/// (glb_rescaler.dart) both consume this structure — they used to carry two
/// drifted copies of the same parser.
///
/// [parse] validates:
///  * the 12-byte header (magic / version / declared length),
///  * the chunk layout (JSON chunk required; BIN chunk optional),
///  * the JSON document's top-level lists and the single-buffer rule,
///  * every mesh / primitive / attributes map and a valid POSITION accessor
///    index per primitive.
/// Accessor-level validation (VEC3 float, count, sparse rejection, bufferView
/// resolution, the stride >= 12 rejection, data-inside-BIN) happens lazily in
/// [dataAccessor] — the one function that actually reads the stream.
class GlbStructure {
  GlbStructure._({
    required this.json,
    required this.jsonChunkBytes,
    required this.binChunk,
    required this.trailing,
    required this.primitives,
  });

  static const int _magic = 0x46546C67; // 'glTF'
  static const int _chunkJson = 0x4E4F534A; // 'JSON'
  static const int _chunkBin = 0x004E4942; // 'BIN\0'
  static const int _headerSize = 12;
  static const int _chunkHeaderSize = 8;

  static const int _componentFloat = 5126; // GL_FLOAT
  static const int _floatBytes = 4;
  static const int _vec3Floats = 3;

  /// Decoded JSON chunk (object form — consumers may mutate it, e.g. the
  /// rescaler rewrites POSITION min/max arrays on it).
  final Map<String, dynamic> json;

  /// Raw (undecoded) JSON chunk bytes, for diagnostics.
  final Uint8List jsonChunkBytes;

  /// BIN chunk contents. A *copy* when [parse] was called with
  /// `mutableBin: true` (consumers patch floats in place), otherwise a view
  /// of the source bytes. Null when the GLB carries no BIN chunk.
  final Uint8List? binChunk;

  /// Anything after the BIN chunk (usually empty; preserved so rewriting
  /// consumers can round-trip the file byte-for-byte).
  final Uint8List trailing;

  /// Every primitive of every mesh, in file order.
  final List<GlbPrimitive> primitives;

  /// Parses a binary glTF 2.0 file. With [mutableBin] the BIN chunk is
  /// copied so callers may patch vertex floats without touching [bytes].
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
    var binEnd = effectiveLength; // file end when there is no BIN chunk
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

  /// Raw accessor JSON for [index]; null when out of range / not an object.
  /// The parsed POSITION indices were validated in [parse]; for other
  /// semantics (NORMAL, COLOR_0, …) callers must handle null.
  Map<String, dynamic>? rawAccessor(int index) {
    final accessors = json['accessors'];
    if (accessors is! List || index < 0 || index >= accessors.length) {
      return null;
    }
    final a = accessors[index];
    return a is Map<String, dynamic> ? a : null;
  }

  /// Resolves + fully validates the data stream of attribute [semantic] on
  /// [primitive] — the ONE implementation of every data-level accessor
  /// check, shared by the bounds fallback scanner and the rescaler:
  ///
  ///  * accessor exists, is an object, not sparse;
  ///  * payload is `type` VEC3, `componentType` 5126 (float), `count` > 0;
  ///  * bufferView in range, an object, buffer 0;
  ///  * byteStride >= 12 (rejects streams packed tighter than one VEC3 float
  ///    — physically impossible for real data; this rejection previously
  ///    lived ONLY in the rescaler);
  ///  * element range inside the BIN chunk.
  ///
  /// Throws [GlbParseException] on any violation when [strict] (used for
  /// POSITION — every consumer needs valid positions). When [strict] is
  /// false it returns null instead so the caller can skip the primitive —
  /// used for NORMAL accessors where a malformed stream is best left alone
  /// (never corrupts a rescale, at worst the normals stay stale).
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
    // Tightly packed when the bufferView does not define a stride.
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

  /// [list] as 3 finite doubles, or null when absent / malformed /
  /// non-finite (used for the spec-required POSITION `min`/`max` arrays).
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
