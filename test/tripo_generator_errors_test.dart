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

    test('falls back to the status mapping for a Tripo body', () {
      const body = '{"code":1200,"message":"insufficient credit"}';
      expect(
        Tripo3DGenerator.describeHttpFailure(402, body),
        '3D generation is out of credit. Top up the Tripo account and tap Retry.',
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
