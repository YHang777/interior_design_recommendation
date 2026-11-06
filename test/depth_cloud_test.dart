import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/depth_cloud.dart';

List<double> _triplets(int count, {int offset = 0}) {
  final out = <double>[];
  for (var i = 0; i < count; i++) {
    final v = (i + offset).toDouble();
    out
      ..add(v)
      ..add(v)
      ..add(v);
  }
  return out;
}

void main() {
  group('mergeClouds', () {
    test('returns empty for an empty sources list', () {
      expect(mergeClouds(const []), isEmpty);
    });

    test('returns empty when every source is empty', () {
      expect(mergeClouds(const [[], []]), isEmpty);
    });

    test('returns empty when nothing is finite', () {
      expect(
        mergeClouds(const [
          [double.nan, double.infinity, 1.0],
        ]),
        isEmpty,
      );
    });

    test('passes a small cloud through unchanged', () {
      const source = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
      expect(mergeClouds([source]), source);
    });

    test('drops whole triplets that contain a non-finite component', () {
      final merged = mergeClouds([
        [1.0, 2.0, 3.0, double.nan, 5.0, 6.0, 7.0, 8.0, double.infinity],
      ]);
      expect(merged, [1.0, 2.0, 3.0]);
    });

    test('drops a ragged tail without shifting the kept triplets', () {
      final merged = mergeClouds([
        [1.0, 2.0, 3.0, 4.0, 5.0],
      ]);
      expect(merged, [1.0, 2.0, 3.0]);
    });

    test('caps the result at maxPoints', () {
      final merged = mergeClouds([_triplets(1000)], maxPoints: 400);
      expect(merged.length ~/ 3, lessThanOrEqualTo(400));
      expect(merged.length % 3, 0);
      // Even stride: index 0 then every stride-th point.
      expect(merged.sublist(0, 3), [0.0, 0.0, 0.0]);
      expect(merged.sublist(3, 6), [3.0, 3.0, 3.0]);
    });

    test('honours a custom maxPoints', () {
      final merged = mergeClouds([_triplets(10)], maxPoints: 4);
      expect(merged.length ~/ 3, lessThanOrEqualTo(4));
      expect(merged.sublist(0, 3), [0.0, 0.0, 0.0]);
      expect(merged.sublist(3, 6), [3.0, 3.0, 3.0]);
      expect(merged.sublist(6, 9), [6.0, 6.0, 6.0]);
      expect(merged.sublist(9, 12), [9.0, 9.0, 9.0]);
    });

    test('keeps a cloud already at maxPoints intact', () {
      final source = _triplets(400);
      expect(mergeClouds([source]), source);
    });

    test('concatenates sources in order, feature points then depth', () {
      const feature = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
      const depth = [7.0, 8.0, 9.0];
      expect(mergeClouds([feature, depth]),
          [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]);
    });

    test('is deterministic across repeated calls', () {
      final sources = [_triplets(300), _triplets(120, offset: 500)];
      expect(mergeClouds(sources), mergeClouds(sources));
      expect(mergeClouds(sources), mergeClouds([...sources]));
    });

    test('caps after concatenating, not per source', () {
      final merged = mergeClouds(
        [_triplets(300), _triplets(300, offset: 1000)],
        maxPoints: 400,
      );
      expect(merged.length ~/ 3, lessThanOrEqualTo(400));
      expect(merged.sublist(0, 3), [0.0, 0.0, 0.0]);
      // Both sources survive the cap, so the stride spans the concatenation.
      expect(merged, contains(298.0));
      expect(merged, contains(1000.0));
    });

    test('zero maxPoints yields empty', () {
      expect(mergeClouds([_triplets(10)], maxPoints: 0), isEmpty);
    });
  });
}
