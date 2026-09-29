import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../domain/repositories/auth_repository.dart';

/// Sends verification-email requests to the app's middleware server
/// (`POST {verificationApiUrl}/verify-email/send` with `{email, uid}`).
///
/// The middleware emails a confirmation link via Brevo; opening the link
/// marks the Firebase Auth user `emailVerified` (see server/). This
/// datasource deliberately carries NO Firebase session — the post-register
/// flow needs it to work AFTER the user has been signed out, and the verify
/// screen's Resend path runs signed out too.
class VerificationEmailDatasource {
  VerificationEmailDatasource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Future<void> sendVerificationEmail({
    required String email,
    required String uid,
  }) async {
    final base = AppConfig.verificationApiUrl.trim();
    if (base.isEmpty) {
      throw const AuthException(
        'Email verification is not configured in this build.',
        code: 'verification-not-configured',
      );
    }
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('$base/verify-email/send'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'uid': uid}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthException(
        'The verification server took too long. Please try again.',
        code: 'verification-email-send-failed',
      );
    } on http.ClientException catch (e) {
      debugPrint('[verify] send failed: $e');
      throw const AuthException(
        'Could not reach the verification server. Check your connection.',
        code: 'verification-email-send-failed',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // The middleware's body is a server diagnostic, not a sentence for the
      // person waiting on the email — log it and show our own short line.
      debugPrint('[verify] send rejected HTTP ${resp.statusCode}: ${resp.body}');
      throw const AuthException(
        'Could not send the verification email. Please try again.',
        code: 'verification-email-send-failed',
      );
    }
  }
}
