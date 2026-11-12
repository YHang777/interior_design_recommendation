import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/model_generation/tripo_generator.dart';

void main() {
  group('describeHttpFailure', () {
    test('prefers the proxy sentence over a status guess', () {
      const body =
          '{"error":{"code":"NOT_CONFIGURED","message":"3D generation is not set up yet. Try again later."}}';
      expect(
        Tripo3DGenerator.describeHttpFailure(503, body),
        '3D generation is not set up yet. Try again later.',
      );
    });

    test('passes through an expired-sign-in sentence', () {
      const body =
          '{"error":{"code":"UNAUTHENTICATED","message":"Please sign in to generate 3D models."}}';
      expect(
        Tripo3DGenerator.describeHttpFailure(401, body),
        'Please sign in to generate 3D models.',
      );
    });

    test('maps 402 to the out-of-credit sentence even without a hint', () {
      const body = '{"code":1200,"message":"quota"}';
      expect(
        Tripo3DGenerator.describeHttpFailure(402, body),
        '3D generation is out of credit. Top up the Tripo account and tap Retry.',
      );
    });

    test('reads the real reason out of a Tripo 403 (code 2010)', () {
      const body =
          '{"code":2010,"status":"error","message":"You don\'t have enough credit to create this task","suggestion":"Please purchase more credit","request_id":"20a56bd7"}';
      expect(
        Tripo3DGenerator.describeHttpFailure(403, body),
        '3D generation is out of credit. Top up the Tripo account and tap Retry.',
        reason: 'a 403 must not read as "not authorized" when the account '
            'is simply empty — sellers retried five times into that wall',
      );
    });

    test('a dead-key 403 still reads as not authorized', () {
      const body = '{"code":4011,"status":"error","message":"invalid api key"}';
      expect(
        Tripo3DGenerator.describeHttpFailure(403, body),
        '3D generation is not authorized right now. Try again later.',
      );
    });

    test('a 403 with an unknown Tripo reason keeps the status sentence', () {
      const body = '{"code":2099,"status":"error","message":"content rejected"}';
      expect(
        Tripo3DGenerator.describeHttpFailure(403, body),
        '3D generation is not authorized right now. Try again later.',
      );
    });

    test('maps 401/403 to a short unauthorized sentence', () {
      for (final status in [401, 403]) {
        expect(
          Tripo3DGenerator.describeHttpFailure(status, ''),
          '3D generation is not authorized right now. Try again later.',
        );
      }
    });

    test('maps 429 to a busy sentence', () {
      expect(
        Tripo3DGenerator.describeHttpFailure(429, ''),
        'Tripo is busy right now. Wait a moment and tap Retry.',
      );
    });

    test('maps 5xx to an unavailable sentence', () {
      expect(
        Tripo3DGenerator.describeHttpFailure(500, ''),
        '3D generation is unavailable right now. Try again later.',
      );
    });

    test('never leaks a raw body into the seller-facing sentence', () {
      const body =
          '{"code":999,"message":"boom","detail":"stack trace at line 42"}';
      final message = Tripo3DGenerator.describeHttpFailure(418, body);
      expect(message, isNot(contains('stack')));
      expect(message, isNot(contains('boom')));
      expect(message, isNot(contains('999')));
      expect(message, '3D generation request failed. Try again.');
    });

    test('ignores a malformed proxy envelope', () {
      expect(
        Tripo3DGenerator.describeHttpFailure(502, 'not json at all'),
        '3D generation is unavailable right now. Try again later.',
      );
      expect(
        Tripo3DGenerator.describeHttpFailure(502, '{"error":"oops"}'),
        '3D generation is unavailable right now. Try again later.',
      );
    });
  });

  group('isTransientHttpStatus', () {
    test('retries on 5xx / 429 / 408', () {
      for (final status in [500, 502, 503, 504, 429, 408]) {
        expect(Tripo3DGenerator.isTransientHttpStatus(status), isTrue,
            reason: 'HTTP $status should be retryable');
      }
    });

    test('does not retry on other 4xx', () {
      for (final status in [400, 401, 402, 403, 404]) {
        expect(Tripo3DGenerator.isTransientHttpStatus(status), isFalse,
            reason: 'HTTP $status should be terminal');
      }
    });

    test('a proxy 503 is retryable — the seller must not lose the task id',
        () {
      expect(Tripo3DGenerator.isTransientHttpStatus(503), isTrue);
    });
  });
}
