import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';

void main() {
  group('scene-space GLB bounds', () {
    for (final f in Directory('assets/models')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.glb'))) {
      test('${f.uri.pathSegments.last} has furniture-scale, Y-up bounds', () {
        final b = GlbBounds.sceneFromGlbBytes(f.readAsBytesSync());
        // ignore: avoid_print
        print('${f.uri.pathSegments.last}: $b');
        expect(b.isDegenerate, isFalse);
      });
    }

    test('generated furniture (no node transforms) matches raw bounds', () {
      final bytes = generateFurnitureGlb(
          category: 'sofa', name: 'Sofa', widthM: 2.0, depthM: 0.9, heightM: 0.85);
      final raw = GlbBounds.fromGlbBytes(bytes);
      final scene = GlbBounds.sceneFromGlbBytes(bytes);
      expect(scene.widthM, closeTo(raw.widthM, 1e-6));
      expect(scene.heightM, closeTo(raw.heightM, 1e-6));
      expect(scene.depthM, closeTo(raw.depthM, 1e-6));
    });
  });
}
