import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../core/utils/user_errors.dart';
import '../features/customer/ar/data/glb_generator.dart'
    show FloorFinishType, WallFinishType;
import '../features/customer/ar/data/room_finishes.dart';

class MaterialScanException implements Exception, UserFacingException {
  const MaterialScanException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'MaterialScanException: $message';
}

/// A matched floor/wall finish, snapped onto the app's own catalog colors.
class RoomMaterialScan {
  const RoomMaterialScan({
    this.floorType,
    this.floorColorArgb,
    this.wallType,
    this.wallColorArgb,
  });

  final FloorFinishType? floorType;
  final int? floorColorArgb;
  final WallFinishType? wallType;
  final int? wallColorArgb;

  bool get isEmpty => floorType == null && wallType == null;
}

/// Maps the server verdict onto catalog finishes: material name → enum, and
/// the model's hex → the nearest palette color for that type (so scans land
/// on swatches the finish UI can show, never free-floating customs).
RoomMaterialScan? parseMaterialScanJson(Map<String, dynamic> body) {
  if (body['status'] != 'ok') return null;

  FloorFinishType? floorType;
  int? floorColor;
  final floorRaw = body['floor'];
  if (floorRaw is Map) {
    final name = floorRaw['material']?.toString();
    floorType =
        name == null ? null : FloorFinishType.values.asNameMap()[name];
    if (floorType != null) {
      floorColor = RoomFinishCatalog.nearestColorForFloor(
        floorType,
        argbFromHex(floorRaw['hex']?.toString() ?? ''),
      ).argb;
    }
  }

  WallFinishType? wallType;
  int? wallColor;
  final wallRaw = body['wall'];
  if (wallRaw is Map) {
    final name = wallRaw['material']?.toString();
    wallType = name == null ? null : WallFinishType.values.asNameMap()[name];
    if (wallType != null) {
      wallColor = RoomFinishCatalog.nearestColorForWall(
        wallType,
        argbFromHex(wallRaw['hex']?.toString() ?? ''),
      ).argb;
    }
  }

  if (floorType == null && wallType == null) return null;
  return RoomMaterialScan(
    floorType: floorType,
    floorColorArgb: floorColor,
    wallType: wallType,
    wallColorArgb: wallColor,
  );
}

int? argbFromHex(String raw) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  if (rgb == null) return null;
  return 0xFF000000 | rgb;
}

class MaterialScanService {
  MaterialScanService({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  static const Duration _timeout = Duration(seconds: 35);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Returns null when the model recognized nothing; throws
  /// [MaterialScanException] when the call itself failed — the scan flow
  /// never crashes on this, the caller just tells the user in one line.
  Future<RoomMaterialScan?> analyzeFrame(
    Uint8List jpegBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final base = AppConfig.chatApiUrl.trim();
    if (base.isEmpty) {
      throw const MaterialScanException('Room material scan is not set up yet.');
    }
    if (jpegBytes.isEmpty) return null;
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const MaterialScanException('Please sign in to scan materials.');
    }

    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$base/api/ai/analyze-room-material'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'imageBase64': base64Encode(jpegBytes),
              'mimeType': mimeType,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const MaterialScanException(
          'Reading the room materials is taking too long.');
    } on http.ClientException catch (e) {
      debugPrint('[material-scan] request failed: $e');
      throw const MaterialScanException(
          'Could not read room materials right now. Check your connection.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[material-scan] rejected HTTP ${resp.statusCode}: ${resp.body}');
      throw MaterialScanException(_messageForStatus(resp.statusCode));
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['status'] == 'failed') {
          throw MaterialScanException(
            decoded['message']?.toString() ??
                'We could not read the floor and wall in this frame.',
          );
        }
        return parseMaterialScanJson(decoded);
      }
    } on FormatException catch (e) {
      debugPrint('[material-scan] unparseable body: $e');
    }
    throw const MaterialScanException(
        'We could not read the room materials right now.');
  }

  String _messageForStatus(int status) {
    if (status == 401) return 'Please sign in to scan materials.';
    if (status == 503) return 'Room material scan is not set up yet.';
    return 'We could not read the room materials right now.';
  }
}
