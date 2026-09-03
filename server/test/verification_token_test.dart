import 'dart:convert';

import 'package:interior_design_server/verification_token.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'test-secret';

  group('verification tokens', () {
    test('round-trips uid and email', () {
      final token = createVerificationToken(
          uid: 'abc123', email: 'user@example.com', secret: secret);
      final payload = verifyVerificationToken(token, secret);
      expect(payload, isNotNull);
      expect(payload!['uid'], 'abc123');
      expect(payload['email'], 'user@example.com');
      expect(payload['exp'], isA<int>());
    });

    test('rejects a tampered payload', () {
      final token = createVerificationToken(
          uid: 'abc123', email: 'user@example.com', secret: secret);
      final parts = token.split('.');
      // Flip the uid from abc123 to abc124 inside the payload.
      final forgedPayload = '{"uid":"abc124","email":"user@example.com","exp":9999999999}';
      final forgedB64 = base64UrlEncode(utf8.encode(forgedPayload))
          .replaceAll('=', '');
      expect(verifyVerificationToken('$forgedB64.${parts[1]}', secret),
          isNull);
    });

    test('rejects a tampered signature', () {
      final token = createVerificationToken(
          uid: 'abc123', email: 'user@example.com', secret: secret);
      final parts = token.split('.');
      final sigBytes = base64Url.decode(parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '='));
      sigBytes[0] ^= 0xFF;
      final forgedSig = base64Url.encode(sigBytes).replaceAll('=', '');
      expect(verifyVerificationToken('${parts[0]}.$forgedSig', secret),
          isNull);
    });

    test('rejects a token signed with a different secret', () {
      final token = createVerificationToken(
          uid: 'abc123', email: 'user@example.com', secret: secret);
      expect(verifyVerificationToken(token, 'other-secret'), isNull);
    });

    test('rejects malformed tokens', () {
      expect(verifyVerificationToken('', secret), isNull);
      expect(verifyVerificationToken('onlyone', secret), isNull);
      expect(verifyVerificationToken('a.b.c', secret), isNull);
      expect(verifyVerificationToken('!!!.###', secret), isNull);
    });

    test('rejects expired tokens', () {
      final start = DateTime.utc(2026, 1, 1, 12);
      final token = createVerificationToken(
        uid: 'abc123',
        email: 'user@example.com',
        secret: secret,
        clock: () => start,
      );
      // Verify with a clock 25 hours later (ttl is 24h).
      expect(
        verifyVerificationToken(token, secret,
            clock: () => start.add(const Duration(hours: 25))),
        isNull,
      );
    });

    test('accepts tokens inside their ttl', () {
      final start = DateTime.utc(2026, 1, 1, 12);
      final token = createVerificationToken(
        uid: 'abc123',
        email: 'user@example.com',
        secret: secret,
        clock: () => start,
      );
      expect(
        verifyVerificationToken(token, secret,
            clock: () => start.add(const Duration(hours: 23))),
        isNotNull,
      );
    });
  });
}
