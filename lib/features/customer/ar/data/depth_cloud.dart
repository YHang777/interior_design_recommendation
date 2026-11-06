// Flat xyz-triplet merging for the AR point-cloud bridge. Sources arrive in
// a fixed order (feature points first, depth second) so the result must stay
// deterministic rather than sorted.
List<double> mergeClouds(List<List<double>> sources, {int maxPoints = 400}) {
  final merged = <double>[];
  for (final source in sources) {
    // A ragged tail is a malformed triplet — drop it rather than shift xyz.
    final end = source.length - (source.length % 3);
    for (var i = 0; i < end; i += 3) {
      final x = source[i];
      final y = source[i + 1];
      final z = source[i + 2];
      if (x.isFinite && y.isFinite && z.isFinite) {
        merged.add(x);
        merged.add(y);
        merged.add(z);
      }
    }
  }
  if (merged.isEmpty) return const [];
  if (maxPoints <= 0) return const [];
  final count = merged.length ~/ 3;
  if (count <= maxPoints) return merged;
  // Keep index 0, stride, 2·stride… — same even-downsample as the native
  // side, and ceiling division so the result never exceeds maxPoints.
  final stride = (count + maxPoints - 1) ~/ maxPoints;
  final out = <double>[];
  var i = 0;
  while (i < merged.length) {
    out.add(merged[i]);
    out.add(merged[i + 1]);
    out.add(merged[i + 2]);
    i += stride * 3;
  }
  return out;
}
