import 'dart:convert';
import 'dart:io';

import 'firebase_admin_client.dart';
import 'verification_mailer.dart';
import 'verification_token.dart';

export 'firebase_admin_client.dart';
export 'verification_mailer.dart';
export 'verification_token.dart';

/// Bundles the email-verification collaborators (constructed once at boot).
class VerificationService {
  VerificationService({
    required this.tokenSecret,
    required this.mailer,
    required this.admin,
  });

  final String tokenSecret;
  final VerificationMailer mailer;
  final FirebaseAdminClient admin;

  /// Enough config to SEND verification emails (HMAC secret + Brevo).
  bool get isConfigured =>
      tokenSecret.trim().isNotEmpty && mailer.isConfigured;

  /// Whether the Firebase admin half (service-account file) is present.
  bool get adminConfigured => admin.isConfigured;
}

/// POST /verify-email/send  {email, uid} → {sent: true}
///
/// NOTE: intentionally unauthenticated (demo-grade — it is effectively an
/// open relay against the Brevo quota). The verification token itself is
/// unforgeable without the server secret, so the confirm step is safe.
Future<void> handleVerifySend(
    HttpRequest req, VerificationService service) async {
  if (!service.isConfigured) {
    return _json(req, {'error': 'Email verification is not configured.'},
        status: HttpStatus.serviceUnavailable);
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
  } catch (_) {
    return _json(req, {'error': 'Invalid JSON body.'},
        status: HttpStatus.badRequest);
  }
  final email = body['email'];
  final uid = body['uid'];
  if (email is! String || email.isEmpty || uid is! String || uid.isEmpty) {
    return _json(req, {'error': 'email and uid are required.'},
        status: HttpStatus.badRequest);
  }

  final token = createVerificationToken(
      uid: uid, email: email, secret: service.tokenSecret);
  try {
    await service.mailer.sendVerificationEmail(email: email, token: token);
  } on VerificationEmailException catch (e) {
    stderr.writeln('[verify] send failed: $e');
    return _json(
        req,
        {'error': 'Could not send the verification email. Please try again.'},
        status: HttpStatus.badGateway);
  }
  await _json(req, {'sent': true});
}

/// GET /verify-email/confirm?token=… → styled HTML page ("our website").
///
/// The token is stateless: a valid link is idempotent and can be retried;
/// an invalid/expired one never reaches Firebase. Never interpolate server
/// exception text into the HTML — only into stderr.
Future<void> handleVerifyConfirm(
    HttpRequest req, VerificationService service) async {
  final token = req.uri.queryParameters['token'];
  final payload = token == null
      ? null
      : verifyVerificationToken(token, service.tokenSecret);
  if (payload == null) {
    return _renderPage(
      req,
      success: false,
      title: 'Verification failed',
      message: 'This link is invalid or has expired. Please resend the '
          'verification email from the app and try again.',
    );
  }

  if (!service.adminConfigured) {
    stderr.writeln('[verify] confirm refused — service account not configured');
    return _renderPage(
      req,
      success: false,
      title: 'Verification unavailable',
      message: 'Verification is temporarily unavailable. Please try again '
          'in a few minutes.',
    );
  }

  try {
    await service.admin.setEmailVerified(payload['uid'] as String);
  } catch (e) {
    stderr.writeln('[verify] confirm failed for ${payload['uid']}: $e');
    return _renderPage(
      req,
      success: false,
      title: 'Verification unavailable',
      message: 'We couldn\'t verify your email right now. Please try this '
          'link again in a few minutes, or resend the verification email '
          'from the app.',
    );
  }
  await _renderPage(
    req,
    success: true,
    title: 'Email Verified!',
    message: '${payload['email']} is now verified.',
    note: 'Return to the Interior Design app, tap "I\'ve Verified", and '
        'log in.',
  );
}

// ── HTML page (inline CSS — this page IS "our website") ──────────────────

Future<void> _renderPage(
  HttpRequest req, {
  required bool success,
  required String title,
  required String message,
  String? note,
}) async {
  final resp = req.response;
  resp.headers.contentType = ContentType.html;
  resp.statusCode = HttpStatus.ok;
  final icon = success ? '✔' : '✖';
  final iconClass = success ? 'ok' : 'bad';
  resp.write('''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — Interior Design</title>
<style>
  body{font-family:Segoe UI,Roboto,sans-serif;background:#f7f5f2;display:flex;
    align-items:center;justify-content:center;min-height:100vh;margin:0}
  .card{background:#fff;border-radius:16px;padding:40px;max-width:420px;
    text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08)}
  .icon{width:64px;height:64px;border-radius:50%;display:inline-flex;
    align-items:center;justify-content:center;font-size:32px;margin-bottom:16px}
  .ok{background:#e7f6ec;color:#1f9d55}.bad{background:#fdeaea;color:#d64545}
  h1{font-size:22px;margin:0 0 8px;color:#222}
  p{color:#555;font-size:15px;line-height:1.5}
  .note{background:#f0f4ff;border-radius:8px;padding:12px;font-size:13px;color:#334}
</style>
</head>
<body>
<div class="card">
  <div class="icon $iconClass">$icon</div>
  <h1>$title</h1>
  <p>$message</p>
${note == null ? '' : '  <p class="note">$note</p>'}
</div>
</body>
</html>''');
  await resp.close();
}

Future<void> _json(HttpRequest req, dynamic data, {int status = HttpStatus.ok}) async {
  final resp = req.response;
  resp.headers.contentType = ContentType.json;
  resp.statusCode = status;
  resp.write(jsonEncode(data));
  await resp.close();
}
