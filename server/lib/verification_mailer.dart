import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Raised when Brevo rejects the send or the request fails — the message is
/// safe to log but is NOT shown to end users (the handlers surface a generic
/// failure).
class VerificationEmailException implements Exception {
  const VerificationEmailException(this.message);

  final String message;

  @override
  String toString() => 'VerificationEmailException: $message';
}

/// Sends verification emails through the Brevo v3 transactional API
/// (https://api.brevo.com/v3/smtp/email). Free tier: 300 emails/day; the
/// sender address must be verified in the Brevo console.
class VerificationMailer {
  VerificationMailer({
    required String apiKey,
    required String senderEmail,
    String senderName = 'Interior Design App',
    required String publicBaseUrl,
    http.Client? client,
  })  : _apiKey = apiKey,
        _senderEmail = senderEmail,
        _senderName = senderName,
        _publicBaseUrl = publicBaseUrl,
        _client = client ?? http.Client();

  final String _apiKey;
  final String _senderEmail;
  final String _senderName;
  final String _publicBaseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  bool get isConfigured =>
      _apiKey.trim().isNotEmpty && _publicBaseUrl.trim().isNotEmpty;

  Future<void> sendVerificationEmail({
    required String email,
    required String token,
  }) async {
    final link = '$_publicBaseUrl/verify-email/confirm'
        '?token=${Uri.encodeQueryComponent(token)}';
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse('https://api.brevo.com/v3/smtp/email'),
            headers: {
              'api-key': _apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'sender': {'name': _senderName, 'email': _senderEmail},
              'to': [
                {'email': email}
              ],
              'subject': 'Verify your email — Interior Design App',
              'htmlContent': _emailHtml(link),
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const VerificationEmailException('Brevo request timed out');
    } on http.ClientException catch (e) {
      throw VerificationEmailException('Brevo network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final snippet =
          resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
      throw VerificationEmailException(
          'Brevo HTTP ${resp.statusCode}: $snippet');
    }
  }

  String _emailHtml(String link) => '''
<div style="font-family:Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:32px 24px">
  <h2 style="margin:0 0 12px">Welcome to the Interior Design App!</h2>
  <p style="color:#444;line-height:1.6">Thanks for creating an account. Click the
    button below to verify your email address.</p>
  <p style="margin:28px 0">
    <a href="$link" style="background:#2d6cdf;color:#fff;padding:12px 28px;
      border-radius:8px;text-decoration:none;font-weight:600">Verify my email</a>
  </p>
  <p style="color:#777;font-size:13px">Or open this link in your browser:<br>
    <a href="$link">$link</a><br><br>
    This link expires in 24 hours. If you didn't create an account, you can
    ignore this email.</p>
</div>''';
}
