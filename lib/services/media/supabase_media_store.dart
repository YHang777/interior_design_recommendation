import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'media_store.dart';

/// Supabase Storage-backed [MediaStore] for GLB models in the hybrid setup
/// (see [HybridMediaStore]): the free plan's 50 MB per-file cap fits large
/// textured Tripo output, where Cloudinary's 10 MB cap could reject it.
///
/// Uses the Supabase Storage REST API over plain [http] — no SDK needed:
///  - upload: POST `{url}/storage/v1/object/{bucket}/{path}` with the raw
///    GLB bytes, `Authorization: Bearer {anon key}` and `x-upsert: true`
///    (regenerating a product overwrites the previous blob);
///  - public URL: `{url}/storage/v1/object/public/{bucket}/{path}` — served
///    to the AR viewer and stored in `product.ar3d.url`;
///  - delete: DELETE by the path parsed out of the public URL (works when
///    the bucket's storage policy grants anon DELETE — unlike Cloudinary's
///    signed-only destroy).
///
/// The anon key is public BY DESIGN (like a Firebase API key) — access is
/// governed by the bucket's storage policies. A demo bucket with public
/// read and anon write is the intended setup; see the repo README steps.
class SupabaseMediaStore implements MediaStore {
  SupabaseMediaStore({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 120);

  String get _baseUrl => AppConfig.supabaseUrl;
  String get _anonKey => AppConfig.supabaseAnonKey;
  String get _bucket => AppConfig.supabaseModelsBucket;

  @override
  bool get isConfigured =>
      _baseUrl.trim().isNotEmpty &&
      _anonKey.trim().isNotEmpty &&
      _bucket.trim().isNotEmpty;

  void _requireConfigured() {
    if (!isConfigured) {
      throw const MediaStoreException(
          'Supabase is not configured — set SUPABASE_URL and '
          'SUPABASE_ANON_KEY (or LocalConfig overrides).');
    }
  }

  @override
  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  }) {
    throw const MediaStoreException(
        'SupabaseMediaStore handles 3D models only — product photos go '
        'through CloudinaryMediaStore (see HybridMediaStore).');
  }

  @override
  Future<String> uploadModelBytes(Uint8List bytes, String remotePath) async {
    _requireConfigured();
    final path = '$remotePath.glb';
    final url = Uri.parse('$_baseUrl/storage/v1/object/$_bucket/$path');
    http.Response resp;
    try {
      resp = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $_anonKey',
              'Content-Type': 'model/gltf-binary',
              // Regenerating a product must overwrite the previous blob.
              'x-upsert': 'true',
            },
            body: bytes,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const MediaStoreException('Supabase upload timed out');
    } on http.ClientException catch (e) {
      throw MediaStoreException('Supabase network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MediaStoreException(
          'Supabase rejected the upload (HTTP ${resp.statusCode}): '
          '${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
    }
    return '$_baseUrl/storage/v1/object/public/$_bucket/$path';
  }

  @override
  Future<void> deleteByUrl(String url) async {
    if (!isConfigured) {
      debugPrint('[media] Supabase delete skipped (not configured): $url');
      return;
    }
    final marker = '/storage/v1/object/public/$_bucket/';
    final idx = url.indexOf(marker);
    if (idx < 0) {
      // Not one of our public URLs — nothing to delete here (best effort).
      debugPrint('[media] Supabase delete skipped (foreign URL): $url');
      return;
    }
    final path = url.substring(idx + marker.length);
    try {
      final resp = await _client
          .delete(
            Uri.parse('$_baseUrl/storage/v1/object/$_bucket/$path'),
            headers: {'Authorization': 'Bearer $_anonKey'},
          )
          .timeout(_timeout);
      debugPrint('[media] Supabase delete $path: HTTP ${resp.statusCode}');
    } catch (e) {
      // Best effort — the doc delete is authoritative.
      debugPrint('[media] Supabase delete failed for $path: $e');
    }
  }
}
