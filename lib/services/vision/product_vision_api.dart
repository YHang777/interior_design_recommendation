import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../core/utils/user_errors.dart';
import '../../models/product.dart';

/// A photo-analysis failure already phrased for the seller waiting on a
/// save: short, plain, free of SDK/HTTP jargon (house rule — same spirit
/// as `ChatException`).
class ProductVisionException implements Exception, UserFacingException {
  const ProductVisionException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'ProductVisionException: $message';
}

/// Client for `POST {chatApiUrl}/api/ai/analyze-product` — the backend's
/// upload-time photo analysis.
///
/// Same key rule as `ChatDatasource`: the Gemini key exists ONLY in the
/// backend's environment, never in the app. This client sends a product id
/// and receives the verdict the server wrote to `products/{id}.vision`.
class ProductVisionApi {
  ProductVisionApi({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  // The analysis waits on a photo download plus one vision call — a little
  // more headroom than chat's 30s since the seller is not staring at a
  // typing bubble.
  static const Duration _timeout = Duration(seconds: 35);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Returns the stored verdict (`status: 'ok' | 'failed'`). A `failed`
  /// vision is a normal result, not an error — only transport/auth problems
  /// throw, and they are already phrased for a human.
  Future<ProductVision> analyze({required String productId}) async {
    final base = AppConfig.chatApiUrl.trim();
    if (base.isEmpty) {
      throw const ProductVisionException('Photo analysis is not set up yet.');
    }
    // Fail fast without a token: an unauthenticated call would only earn
    // a 401 from the proxy.
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ProductVisionException('Please sign in to check photos.');
    }

    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$base/api/ai/analyze-product'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'productId': productId}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ProductVisionException('Checking this photo is taking too long.');
    } on http.ClientException catch (e) {
      debugPrint('[vision] request failed: $e');
      throw const ProductVisionException(
          'Could not check photos right now. Check your connection.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Server diagnostics stay in the log; the seller gets our sentence.
      debugPrint('[vision] rejected HTTP ${resp.statusCode}: ${resp.body}');
      throw ProductVisionException(_messageForStatus(resp.statusCode));
    }

    try {
      final decoded = jsonDecode(resp.body);
      final vision = decoded is Map ? decoded['vision'] : null;
      if (vision is Map<String, dynamic>) {
        return ProductVision.fromJson(vision);
      }
    } on FormatException catch (e) {
      debugPrint('[vision] unparseable body: $e');
    }
    throw const ProductVisionException('We could not check this photo right now.');
  }

  String _messageForStatus(int status) {
    if (status == 401) return 'Please sign in to check photos.';
    if (status == 403) return 'You can only check your own products.';
    if (status == 404) return 'That product could not be found.';
    if (status == 503) return 'Photo analysis is not set up yet.';
    return 'We could not check this photo right now.';
  }
}
