import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Stateless HMAC-SHA256 verification token.
///
/// Format: `base64url(payloadJson) + '.' + base64url(hmacSha256(secret, payloadB64))`
/// where payloadJson is `{"uid": ..., "email": ..., "exp": <epochSeconds>}`.
///
/// No server-side storage is involved — the token is unforgeable without
/// [secret] and self-expiring via `exp`, so a still-valid link can always be
/// retried (idempotent) and an old one can never be replayed past its TTL.
const Duration defaultTokenTtl = Duration(hours: 24);

String createVerificationToken({
  required String uid,
  required String email,
  required String secret,
  DateTime Function()? clock,
  Duration ttl = defaultTokenTtl,
}) {
  final now = (clock ?? DateTime.now)().toUtc();
  final payload = jsonEncode({
    'uid': uid,
    'email': email,
    'exp': now.add(ttl).millisecondsSinceEpoch ~/ 1000,
  });
  final payloadB64 = _b64url(utf8.encode(payload));
  final sigB64 = _b64url(_sign(payloadB64, secret));
  return '$payloadB64.$sigB64';
}

/// Decodes and validates [token]. Returns `{uid, email, exp}` or null when
/// the token is malformed, tampered with, or expired.
Map<String, dynamic>? verifyVerificationToken(
  String token,
  String secret, {
  DateTime Function()? clock,
}) {
  final parts = token.split('.');
  if (parts.length != 2) return null;
  final payloadB64 = parts[0];
  final sig = parts[1];
  if (payloadB64.isEmpty || sig.isEmpty) return null;

  // Recompute-and-compare (no early return on length/byte mismatch).
  final expected = _sign(payloadB64, secret);
  Uint8List actual;
  try {
    actual = base64Url.decode(_padB64(sig));
  } catch (_) {
    return null;
  }
  if (actual.length != expected.length) return null;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  if (diff != 0) return null;

  Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(_padB64(payloadB64))));
    if (decoded is! Map<String, dynamic>) return null;
    payload = decoded;
  } catch (_) {
    return null;
  }
  final uid = payload['uid'];
  final email = payload['email'];
  final exp = payload['exp'];
  if (uid is! String || uid.isEmpty) return null;
  if (email is! String || email.isEmpty) return null;
  if (exp is! int) return null;
  final now = (clock ?? DateTime.now)().toUtc();
  if (exp <= now.millisecondsSinceEpoch ~/ 1000) return null;
  return payload;
}

List<int> _sign(String payloadB64, String secret) {
  return Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payloadB64)).bytes;
}

String _b64url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// base64Url.decode is lenient about padding in recent SDKs; re-padding keeps
/// it unambiguous across versions.
String _padB64(String s) {
  final rem = s.length % 4;
  return rem == 0 ? s : s + ('=' * (4 - rem));
}
