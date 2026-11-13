import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/catalog_model_resolver.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/furniture_model_library.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/furniture_catalog.dart';

// Every catalogue piece must resolve to a model that loads, stands upright
// and roughly matches its catalogue proportions (the planner stretches each
// axis to the seller box, so a lying-down or wildly mis-proportioned mesh
// would render distorted), and every piece needs its photo tile.
void main() {
  final bundled = [
    for (final c in roomCatalog)
      if (!kGeneratedCatalogIcons.contains(c.iconName) &&
          ArFurnitureLibrary.hasModelFor(c.iconName))
        c,
  ];

  test('every catalogue piece has a real model or is explicitly generated',
      () {
    for (final c in roomCatalog) {
      expect(
          kGeneratedCatalogIcons.contains(c.iconName) ||
              ArFurnitureLibrary.hasModelFor(c.iconName),
          isTrue,
          reason: '${c.name} has no bundled model and is not generated — it '
              'would fall back to a folding table');
    }
  });

  for (final c in bundled) {
    final file = ArFurnitureLibrary.forIconName(c.iconName).modelFile;
    test('${c.name} → $file loads upright at catalogue proportions', () {
      final f = File('assets/models/$file');
      expect(f.existsSync(), isTrue, reason: 'missing assets/models/$file');
      final b = GlbBounds.sceneFromGlbBytes(f.readAsBytesSync());
      expect(b.isDegenerate, isFalse);

      // Height relative to the footprint's long side: a Z-up mesh lying on
      // its back, or a model of the wrong kind, lands far outside 2×.
      final natTall = b.heightM / math.max(b.widthM, b.depthM);
      final catTall = c.heightCm / math.max(c.defaultWidth, c.defaultHeight);
      final ratio = natTall / catTall;
      expect(ratio, inInclusiveRange(0.5, 2.0),
          reason: '${c.name}: model is ${b.widthM.toStringAsFixed(2)}×'
              '${b.heightM.toStringAsFixed(2)}×${b.depthM.toStringAsFixed(2)} m '
              '(W×H×D) but the catalogue says ${c.defaultWidth}×${c.heightCm}×'
              '${c.defaultHeight} cm');

      // Footprint aspect, either way round (the bridge turns models whose
      // long side runs across the seller box).
      double aspect(double a, double b) => math.max(a, b) / math.min(a, b);
      final fr = aspect(b.widthM, b.depthM) /
          aspect(c.defaultWidth, c.defaultHeight);
      expect(fr, inInclusiveRange(0.5, 2.0),
          reason: '${c.name}: footprint aspect is off by ${fr.toStringAsFixed(2)}×');
    });
  }

  test('every catalogue piece has its photo tile', () {
    for (final c in roomCatalog) {
      final img = c.imageAsset;
      if (img == null) continue;
      expect(File(img).existsSync(), isTrue, reason: '${c.name}: missing $img');
    }
  });

  test('every downloaded (ph_/kh_) model is credited', () {
    final credits = File('assets/models/CREDITS.md').readAsStringSync();
    for (final f in Directory('assets/models').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!(name.startsWith('ph_') || name.startsWith('kh_')) ||
          !name.endsWith('.glb')) {
        continue;
      }
      expect(credits.contains(name), isTrue, reason: '$name is not in CREDITS.md');
    }
  });
}
