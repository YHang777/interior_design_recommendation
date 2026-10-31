import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../../config/app_config.dart';
import '../../../../../models/room_design.dart';

class SupabaseRoomDesignDatasource {
  SupabaseRoomDesignDatasource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);
  static const Duration pollInterval = Duration(seconds: 5);
  static const String _table = 'room_designs';

  String get _baseUrl => AppConfig.supabaseUrl;
  String get _anonKey => AppConfig.supabaseAnonKey;

  bool get isConfigured =>
      _baseUrl.trim().isNotEmpty && _anonKey.trim().isNotEmpty;

  Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) async {
    final body = {
      'id': designId,
      ..._toRow(data),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _post(body);
  }

  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) async {
    final body = {
      ..._toRow(data),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _patch(designId, body);
  }

  // PostgREST rejects unknown columns, so the model's camelCase toJson
  // keys must be mapped to the table's snake_case columns. Walls live
  // inside the furniture JSONB ({items, walls}) — the table has no walls
  // column and anon cannot migrate the schema.
  Map<String, dynamic> _toRow(Map<String, dynamic> data) {
    return {
      if (data.containsKey('name')) 'name': data['name'],
      if (data.containsKey('roomType')) 'room_type': data['roomType'],
      if (data.containsKey('widthCm')) 'width_cm': data['widthCm'],
      if (data.containsKey('heightCm')) 'height_cm': data['heightCm'],
      if (data.containsKey('furniture') || data.containsKey('walls'))
        'furniture': {
          'items': data['furniture'] ?? [],
          'walls': data['walls'] ?? [],
        },
      if (data.containsKey('detectedItems'))
        'detected_items': data['detectedItems'],
      if (data.containsKey('imagePath')) 'image_path': data['imagePath'],
      if (data.containsKey('userId')) 'user_id': data['userId'],
    };
  }

  Future<void> deleteDesign(String designId) async {
    await _delete(designId);
  }

  Future<List<RoomDesign>> getDesigns(String userId) async {
    final url = Uri.parse(
        '$_baseUrl/rest/v1/$_table?user_id=eq.$userId&order=updated_at.desc');
    final resp = await _client
        .get(url, headers: _headers)
        .timeout(_timeout);
    _checkError(resp);
    final List json = jsonDecode(resp.body);
    return json.map((e) {
      final map = _fromRow(e);
      return RoomDesign.fromJson(map);
    }).toList();
  }

  Stream<List<RoomDesign>> watchDesigns(String userId) async* {
    yield await getDesigns(userId);
    await for (final _
        in Stream.periodic(pollInterval).asyncExpand((_) async* {
      yield await getDesigns(userId);
    })) {
      yield await getDesigns(userId);
    }
  }

  Future<RoomDesign?> getDesign(String designId) async {
    final url = Uri.parse('$_baseUrl/rest/v1/$_table?id=eq.$designId&limit=1');
    final resp = await _client
        .get(url, headers: _headers)
        .timeout(_timeout);
    _checkError(resp);
    final List json = jsonDecode(resp.body);
    if (json.isEmpty) return null;
    return RoomDesign.fromJson(_fromRow(json.first));
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  // TimeoutException / http.ClientException / SocketException are left
  // to propagate — userMessage() maps each to a plain sentence at the
  // call site (wrapping them here would flatten every failure into the
  // generic fallback).
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final url = Uri.parse('$_baseUrl/rest/v1/$_table');
    final resp = await _client
        .post(url, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _checkError(resp);
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> _patch(
      String id, Map<String, dynamic> body) async {
    final url =
        Uri.parse('$_baseUrl/rest/v1/$_table?id=eq.$id');
    final resp = await _client
        .patch(url, headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _checkError(resp);
    return jsonDecode(resp.body);
  }

  Future<void> _delete(String id) async {
    final url =
        Uri.parse('$_baseUrl/rest/v1/$_table?id=eq.$id');
    final resp = await _client
        .delete(url, headers: _headers)
        .timeout(_timeout);
    _checkError(resp);
  }

  void _checkError(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = resp.body.length > 300
          ? resp.body.substring(0, 300)
          : resp.body;
      throw Exception(
          'Supabase error (HTTP ${resp.statusCode}): $body');
    }
  }

  Map<String, dynamic> _fromRow(Map<String, dynamic> row) {
    return {
      'id': row['id']?.toString() ?? '',
      'name': row['name']?.toString() ?? 'Untitled Design',
      'roomType': row['room_type']?.toString() ?? 'living_room',
      'widthCm': row['width_cm'],
      'heightCm': row['height_cm'],
      'furniture': row['furniture'],
      'walls': row['walls'],
      'detectedItems': row['detected_items'],
      'imagePath': row['image_path'],
      'createdAt': row['created_at']?.toString(),
      'updatedAt': row['updated_at']?.toString(),
      'userId': row['user_id']?.toString() ?? '',
    };
  }
}
