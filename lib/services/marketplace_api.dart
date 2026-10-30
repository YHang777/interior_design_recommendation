import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../core/utils/user_errors.dart';

class CheckoutIntent {
  const CheckoutIntent({
    required this.orderId,
    required this.orderNumber,
    required this.clientSecret,
    required this.publishableKey,
    required this.total,
  });

  final String orderId;
  final String orderNumber;
  final String clientSecret;
  final String publishableKey;
  final int total;
}

class CheckoutItem {
  const CheckoutItem({
    required this.productId,
    required this.quantity,
  });

  final String productId;
  final int quantity;
}

class PaymentVerification {
  const PaymentVerification({
    required this.paid,
    required this.paymentMethod,
  });

  final bool paid;
  final String paymentMethod;
}

class PaymentApiException implements Exception, UserFacingException {
  PaymentApiException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => message;
}

class MarketplaceApi {
  MarketplaceApi({
    http.Client? client,
    Future<String?> Function()? idToken,
  })  : _client = client ?? http.Client(),
        _idToken = idToken ?? _defaultIdToken;

  final http.Client _client;
  final Future<String?> Function() _idToken;

  static const Duration _timeout = Duration(seconds: 30);

  static Future<String?> _defaultIdToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Uri _uri(String path) {
    final base = AppConfig.marketplaceApiUrl.trim();
    // Checkout lives under /api on the unified host (same as /api/ai, /api/tripo).
    return Uri.parse(
        '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/api$path');
  }

  /// Pings the API so a sleeping host (e.g. Render cold start) wakes while
  /// the user fills in the checkout form, not while they wait on Pay now.
  Future<void> warmUp() async {
    try {
      await _client
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw PaymentApiException('Please sign in again before paying.');
    }
    http.Response resp;
    try {
      resp = await _client
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw PaymentApiException(
          'The payment service took too long. Please try again.');
    } on http.ClientException {
      throw PaymentApiException(
          'Could not reach the payment service. Check your connection.');
    }
    return _decode(resp, path);
  }

  Map<String, dynamic> _decode(http.Response resp, String path) {
    Map<String, dynamic> data = const {};
    if (resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[marketplace-api] $path → HTTP ${resp.statusCode}: ${resp.body}');
      final message = data['error']?.toString();
      throw PaymentApiException(
          message ?? 'Payment service error. Please try again.');
    }
    return data;
  }

  Future<CheckoutIntent> createCheckoutIntent({
    required List<CheckoutItem> items,
    required String customerName,
    required String customerPhone,
    required String membershipTier,
  }) async {
    if (kIsWeb) {
      throw PaymentApiException(
          'Checkout is available in the mobile app.');
    }
    final data = await _post('/checkout/intents', {
      'items': [
        for (final i in items)
          {'productId': i.productId, 'quantity': i.quantity},
      ],
      'customerName': customerName,
      'customerPhone': customerPhone,
      'membershipTier': membershipTier,
    });
    return CheckoutIntent(
      orderId: data['orderId']?.toString() ?? '',
      orderNumber: data['orderNumber']?.toString() ?? '',
      clientSecret: data['clientSecret']?.toString() ?? '',
      publishableKey: data['publishableKey']?.toString() ?? '',
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PaymentVerification> verifyPayment(String orderId) async {
    final data = await _post('/checkout/orders/$orderId/verify', const {});
    return PaymentVerification(
      paid: data['paid'] == true,
      paymentMethod: data['paymentMethod']?.toString() ?? '',
    );
  }

  Future<void> abandonCheckout(String orderId) async {
    try {
      await _post('/checkout/orders/$orderId/abandon', const {});
    } catch (e) {
      debugPrint('[marketplace-api] abandon $orderId failed: $e');
    }
  }

  Future<void> cancelOrder(String orderId) async {
    await _post('/checkout/orders/$orderId/cancel', const {});
  }
}
