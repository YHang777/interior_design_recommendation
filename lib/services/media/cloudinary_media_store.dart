import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../config/app_config.dart';
import 'media_store.dart';

/// Cloudinary-backed [MediaStore] using UNSIGNED uploads (no API secret on
/// the client — the account's upload preset allows uploads; see README setup).
///
/// Handles product PHOTOS in the hybrid setup (see [HybridMediaStore]): the
/// free plan's 25 GB quota is generous for images, whose per-file 10 MB cap
/// never bites. GLB models go through [SupabaseMediaStore] instead.
///
/// - images land as `image/upload` under [remotePath] as the public_id
///   (folders come free: `/` in the id is a folder separator);
/// - public urls are returned from `secure_url` — required both for the
///   marketplace image rendering and because Tripo fetches the product photo
///   server-side (the url must be publicly readable);
/// - [deleteByUrl] is a no-op: Cloudinary `destroy` requires a signed
///   request, which a client app must not build. Orphans are reclaimable
///   from the Cloudinary console.
class CloudinaryMediaStore implements MediaStore {
  CloudinaryMediaStore({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? _defaultClient;

  final HttpClient Function() _clientFactory;
  static HttpClient _defaultClient() => HttpClient();

  static const String _uploadBase = 'https://api.cloudinary.com/v1_1';

  String get _cloudName => AppConfig.cloudinaryCloudName;
  String get _uploadPreset => AppConfig.cloudinaryUploadPreset;

  @override
  bool get isConfigured =>
      _cloudName.trim().isNotEmpty && _uploadPreset.trim().isNotEmpty;

  void _requireConfigured() {
    if (!isConfigured) {
      throw const MediaStoreException(
          'Cloudinary is not configured — set CLOUDINARY_CLOUD_NAME and '
          'CLOUDINARY_UPLOAD_PRESET (or LocalConfig overrides).');
    }
  }

  @override
  Future<String> uploadImageFile(
    File file,
    String remotePath, {
    void Function(double progress)? onProgress,
  }) async {
    _requireConfigured();
    final total = await file.length();
    return _uploadMultipart(
      resourceType: 'image',
      filename: _filenameFor(remotePath, 'jpg'),
      contentType: 'image/jpeg',
      publicId: remotePath,
      stream: file.openRead(),
      totalBytes: total,
      onProgress: onProgress,
    );
  }

  @override
  Future<String> uploadModelBytes(Uint8List bytes, String remotePath) {
    throw const MediaStoreException(
        'CloudinaryMediaStore handles product photos only — GLB models go '
        'through SupabaseMediaStore (see HybridMediaStore).');
  }

  @override
  Future<void> deleteByUrl(String url) async {
    // Cloudinary `destroy` requires a signed request; unsigned client-side
    // deletion is not possible. Orphaned assets stay in the account and can
    // be removed from the Cloudinary console.
    debugPrint('[media] delete requested (no-op on Cloudinary): $url');
  }

  // ── internals ──────────────────────────────────────────────────────────

  /// Cloudinary rejects multipart bodies where the file part is not the
  /// FIRST field, so `file` is always written before the plain fields.
  Future<String> _uploadMultipart({
    required String resourceType,
    required String filename,
    required String contentType,
    required String publicId,
    required Stream<List<int>> stream,
    required int totalBytes,
    void Function(double progress)? onProgress,
  }) async {
    final boundary = '----clm${DateTime.now().microsecondsSinceEpoch}';
    final url = Uri.parse('$_uploadBase/$_cloudName/$resourceType/upload');
    final client = _clientFactory();
    try {
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );

      var sent = 0;
      final sink = request;
      // file part (must come first)
      sink.add(utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; '
          'filename="$filename"\r\n'
          'Content-Type: $contentType\r\n\r\n'));
      await sink.addStream(stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, out) {
            sent += chunk.length;
            onProgress?.call(totalBytes == 0 ? 0 : sent / totalBytes);
            out.add(chunk);
          },
        ),
      ));
      // plain fields
      sink.add(utf8.encode(
          '\r\n--$boundary\r\n'
          'Content-Disposition: form-data; name="upload_preset"\r\n\r\n'
          '$_uploadPreset\r\n'
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="public_id"\r\n\r\n'
          '$publicId\r\n'
          '--$boundary--\r\n'));
      await sink.flush();

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MediaStoreException(_describeError(
            resourceType, response.statusCode, body));
      }
      final decoded = jsonDecode(body);
      final secureUrl =
          decoded is Map<String, dynamic> ? decoded['secure_url'] : null;
      if (secureUrl is! String || !secureUrl.startsWith('http')) {
        throw MediaStoreException(
            'Cloudinary accepted the upload but returned no secure_url');
      }
      return secureUrl;
    } on MediaStoreException {
      rethrow;
    } catch (e) {
      throw MediaStoreException('Cloudinary upload failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  String _filenameFor(String remotePath, String fallbackExt) {
    final segments = remotePath.split('/');
    final last = segments.isEmpty ? '' : segments.last;
    if (last.contains('.')) return last;
    return '$last.$fallbackExt';
  }

  String _describeError(String resourceType, int status, String body) {
    String message = 'Cloudinary rejected the upload (HTTP $status)';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          message += ': ${error['message']}';
        }
      }
    } catch (_) {
      // Non-JSON error body — keep the bare status message.
    }
    if (resourceType == 'raw') {
      message += ' — note: Cloudinary\'s free plan rejects uploads over '
          '10 MB (large textured models may exceed this).';
    }
    return message;
  }
}
