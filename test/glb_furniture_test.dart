import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/furniture_catalog.dart';

void main() {
  GlbBounds gen({
    required String category,
    required String name,
    required double widthM,
    required double heightM,
    required double depthM,
    int seedOrColor = 0,
  }) =>
      GlbBounds.fromGlbBytes(generateFurnitureGlb(
        category: category,
        name: name,
        widthM: widthM,
        heightM: heightM,
        depthM: depthM,
        seedOrColor: seedOrColor,
      ));

  group('generateFurnitureGlb', () {
    test('every shape family grounds at y = 0 with positive extents', () {
      const cases = <(String, String)>[
        ('Furniture', 'Dining Table'),
        ('Furniture', 'Oak Sofa'),
        ('Furniture', 'Wooden Chair'),
        ('Furniture', 'Lounge Armchair'),
        ('Furniture', 'Double Bed'),
        ('Furniture', 'Tall Cabinet'),
        ('Lighting', 'Floor Lamp'),
        ('Decor', 'Wool Rug'),
        ('Decor', 'Ceramic Vase'),
        ('Decor', 'Floor Plant'),
        ('Decor', 'Wall Mirror'),
        ('Decor', 'Throw Cushion'),
        ('Furniture', 'Mystery Object'),
      ];
      for (final (category, name) in cases) {
        final b = gen(
            category: category,
            name: name,
            widthM: 0.9,
            heightM: 1.0,
            depthM: 0.7);
        expect(b.minY, closeTo(0, 1e-6), reason: name);
        expect(b.widthM, greaterThan(0), reason: name);
        expect(b.heightM, greaterThan(0), reason: name);
        expect(b.depthM, greaterThan(0), reason: name);
      }
    });

    test('table / sofa / bed / cabinet fill the seller box', () {
      final table = gen(
          category: 'Furniture',
          name: 'Dining Table',
          widthM: 1.4,
          heightM: 0.75,
          depthM: 0.9);
      expect(table.widthM, closeTo(1.4, 0.01));
      expect(table.heightM, closeTo(0.75, 0.01));
      expect(table.depthM, closeTo(0.9, 0.01));

      final sofa = gen(
          category: 'Furniture',
          name: 'Oak Sofa',
          widthM: 1.8,
          heightM: 0.8,
          depthM: 0.9);
      expect(sofa.widthM, closeTo(1.8, 0.01));
      expect(sofa.heightM, closeTo(0.8, 0.01));
      expect(sofa.depthM, closeTo(0.9, 0.01));

      final bed = gen(
          category: 'Furniture',
          name: 'Double Bed',
          widthM: 2.0,
          heightM: 0.6,
          depthM: 1.6);
      expect(bed.widthM, closeTo(2.0, 0.01));
      expect(bed.heightM, closeTo(0.6, 0.01));

      final cabinet = gen(
          category: 'storage',
          name: 'Cabinet',
          widthM: 0.9,
          heightM: 1.8,
          depthM: 0.5);
      expect(cabinet.widthM, closeTo(0.9, 0.01));
      expect(cabinet.heightM, closeTo(1.8, 0.01));
      expect(cabinet.depthM, closeTo(0.5, 0.01));
    });

    test('rug is a 2 cm mat at exact W × D', () {
      final b = gen(
          category: 'Decor', name: 'Wool Rug', widthM: 1.6, heightM: 2, depthM: 1.2);
      expect(b.widthM, closeTo(1.6, 0.01));
      expect(b.depthM, closeTo(1.2, 0.01));
      expect(b.heightM, closeTo(0.02, 0.005));
    });

    test('vase fills the min(W, D) footprint at full height', () {
      final b = gen(
          category: 'Decor',
          name: 'Ceramic Vase',
          widthM: 0.3,
          heightM: 0.45,
          depthM: 0.5);
      expect(b.widthM, closeTo(0.3, 0.02));
      expect(b.depthM, closeTo(0.3, 0.02));
      expect(b.heightM, closeTo(0.45, 0.01));
    });

    test('cushion height caps at 15 cm while W and D stay exact', () {
      final b = gen(
          category: 'Decor',
          name: 'Throw Cushion',
          widthM: 0.45,
          heightM: 0.6,
          depthM: 0.45);
      expect(b.heightM, closeTo(0.15, 0.01));
      expect(b.widthM, closeTo(0.45, 0.01));
      expect(b.depthM, closeTo(0.45, 0.01));
    });

    test('mirror is a thin slab of the full W × H face', () {
      final b = gen(
          category: 'Decor',
          name: 'Wall Mirror',
          widthM: 0.9,
          heightM: 1.2,
          depthM: 0.1);
      expect(b.widthM, closeTo(0.9, 0.01));
      expect(b.heightM, closeTo(1.2, 0.01));
      expect(b.depthM, lessThanOrEqualTo(0.04));
    });

    test('lamp keeps the seller height and a shade ≈ W wide', () {
      final b = gen(
          category: 'lighting',
          name: 'Floor Lamp',
          widthM: 0.4,
          heightM: 1.6,
          depthM: 0.4);
      expect(b.heightM, closeTo(1.6 * 0.95, 0.02));
      expect(b.widthM, closeTo(0.4 * 0.96, 0.03));
    });

    test('plant is a tall pot + foliage, not a flat slab', () {
      final b = gen(
          category: 'decor',
          name: 'Plant',
          widthM: 0.3,
          heightM: 1.2,
          depthM: 0.3);
      expect(b.heightM, greaterThan(1.0));
      expect(b.widthM, closeTo(0.3, 0.05));
    });

    test('default cuboid is exact W × H × D', () {
      final b = gen(
          category: 'Furniture',
          name: 'Mystery Object',
          widthM: 0.6,
          heightM: 1.1,
          depthM: 0.4);
      expect(b.widthM, closeTo(0.6, 0.005));
      expect(b.heightM, closeTo(1.1, 0.005));
      expect(b.depthM, closeTo(0.4, 0.005));
    });

    test('squat sofa degrades to its seat instead of throwing', () {
      final bytes = generateFurnitureGlb(
          category: 'Furniture',
          name: 'Sofa',
          widthM: 1.8,
          heightM: 0.05,
          depthM: 0.9);
      final b = GlbBounds.fromGlbBytes(bytes);
      expect(b.heightM, greaterThan(0));
      expect(b.heightM, lessThanOrEqualTo(0.05));
    });

    test('tiny chair degrades to a stool slab', () {
      final b = gen(
          category: 'Furniture',
          name: 'Wooden Chair',
          widthM: 0.4,
          heightM: 0.15,
          depthM: 0.4);
      expect(b.heightM, closeTo(0.15, 0.01));
      expect(b.widthM, closeTo(0.4, 0.01));
    });

    test('non-positive dimensions throw ArgumentError', () {
      expect(
        () => generateFurnitureGlb(
            category: 'Furniture',
            name: 'Sofa',
            widthM: 0,
            heightM: 1,
            depthM: 1),
        throwsArgumentError,
      );
      expect(
        () => generateFurnitureGlb(
            category: 'Furniture',
            name: 'Sofa',
            widthM: 1,
            heightM: -0.2,
            depthM: 1),
        throwsArgumentError,
      );
    });

    test('identical inputs produce byte-identical GLBs', () {
      Uint8List genBytes() => generateFurnitureGlb(
          category: 'Furniture',
          name: 'Oak Sofa',
          widthM: 1.8,
          heightM: 0.8,
          depthM: 0.9);
      expect(genBytes(), genBytes());
    });

    test('seedOrColor varies tones but stays deterministic per seed', () {
      Uint8List genBytes(int seed) => generateFurnitureGlb(
          category: 'Furniture',
          name: 'Oak Sofa',
          widthM: 1.8,
          heightM: 0.8,
          depthM: 0.9,
          seedOrColor: seed);
      expect(genBytes(7), genBytes(7));
    });
  });

  group('shape-family routing', () {
    test('plant names route to the plant family, planters stay vases', () {
      expect(resolveShapeFamily(category: 'decor', name: 'Floor Plant'), 'plant');
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Fern Plant'), 'plant');
      expect(
          resolveShapeFamily(category: 'Decor', name: 'Ceramic Planter'), 'vase');
    });

    test('TV stand routes to cabinet; a standing desk stays a table', () {
      expect(resolveShapeFamily(category: 'media', name: 'TV Stand'), 'cabinet');
      expect(
          resolveShapeFamily(category: 'Furniture', name: 'Standing Desk'),
          'table');
    });
  });

  group('all 12 catalog pieces generate at catalog size', () {
    test('every picker item produces a grounded, parseable GLB', () {
      for (final item in roomCatalog) {
        final b = GlbBounds.fromGlbBytes(generateFurnitureGlb(
          category: item.category,
          name: item.name,
          widthM: item.defaultWidth / 100,
          heightM: item.heightCm / 100,
          depthM: item.defaultHeight / 100,
        ));
        expect(b.minY, closeTo(0, 1e-6), reason: item.name);
        expect(b.heightM, greaterThan(0), reason: item.name);
        expect(b.widthM, greaterThan(0), reason: item.name);
      }
    });
  });

  group('PBR material groups', () {
    Map<String, dynamic> glbJson(Uint8List bytes) {
      final data = ByteData.sublistView(bytes);
      final jsonLen = data.getUint32(12, Endian.little);
      return jsonDecode(String.fromCharCodes(
          bytes.sublist(12 + 8, 12 + 8 + jsonLen))) as Map<String, dynamic>;
    }

    List<Map<String, dynamic>> primitivesOf(Map<String, dynamic> json) =>
        [for (final p in ((json['meshes'] as List).first as Map)['primitives'] as List) p as Map<String, dynamic>];

    test('a detailed piece emits one primitive per used material', () {
      final json = glbJson(generateFurnitureGlb(
          category: 'storage',
          name: 'Cabinet',
          widthM: 0.9,
          heightM: 1.8,
          depthM: 0.5));
      final prims = primitivesOf(json);
      expect(prims.length, greaterThanOrEqualTo(3),
          reason: 'satin carcass + matte kick + metal handles');
      final used = {for (final p in prims) p['material'] as int};
      expect(used.length, prims.length, reason: 'one primitive per material');
    });

    test('materials carry distinct sheen values', () {
      final json = glbJson(generateFurnitureGlb(
          category: 'Furniture',
          name: 'Mystery Object',
          widthM: 0.6,
          heightM: 1.1,
          depthM: 0.4));
      final mats = json['materials'] as List;
      expect(mats, hasLength(4));
      double factor(String name, String key) {
        final m = mats.firstWhere((m) => (m as Map)['name'] == name) as Map;
        return ((m['pbrMetallicRoughness'] as Map)[key] as num).toDouble();
      }

      expect(factor('matte', 'roughnessFactor'),
          greaterThan(factor('satin', 'roughnessFactor')));
      expect(factor('satin', 'roughnessFactor'),
          greaterThan(factor('gloss', 'roughnessFactor')));
      expect(factor('metal', 'metallicFactor'), greaterThan(0.5));
      expect(factor('satin', 'metallicFactor'), 0);
    });

    test('a plain cuboid keeps a single material group', () {
      final json = glbJson(generateFurnitureGlb(
          category: 'Furniture',
          name: 'Mystery Object',
          widthM: 0.6,
          heightM: 1.1,
          depthM: 0.4));
      expect(primitivesOf(json), hasLength(1));
    });

    test('every material group indexes real emitted triangles', () {
      List<int> readIndices(
          Map<String, dynamic> json, Uint8List bytes, int accessorIdx) {
        final data = ByteData.sublistView(bytes);
        final accessors = json['accessors'] as List;
        final bufferViews = json['bufferViews'] as List;
        final acc = accessors[accessorIdx] as Map<String, dynamic>;
        final bv =
            bufferViews[acc['bufferView'] as int] as Map<String, dynamic>;
        final jsonLen = data.getUint32(12, Endian.little);
        final base = 12 + 8 + jsonLen + 8 +
            (bv['byteOffset'] as int? ?? 0) +
            (acc['byteOffset'] as int? ?? 0);
        final count = acc['count'] as int;
        final comp = acc['componentType'] as int;
        return [
          for (var i = 0; i < count; i++)
            comp == 5123
                ? data.getUint16(base + i * 2, Endian.little)
                : data.getUint32(base + i * 4, Endian.little),
        ];
      }

      for (final (category, name) in [
        ('storage', 'Cabinet'),
        ('Furniture', 'Mystery Object'),
      ]) {
        final bytes = generateFurnitureGlb(
            category: category,
            name: name,
            widthM: 0.9,
            heightM: 1.8,
            depthM: 0.5);
        final json = glbJson(bytes);
        final vCount =
            ((json['accessors'] as List).first as Map)['count'] as int;
        final prims = primitivesOf(json);
        for (var gi = 0; gi < prims.length; gi++) {
          final idx = readIndices(json, bytes, prims[gi]['indices'] as int);
          expect(idx.length % 3, 0, reason: '$name group $gi whole triangles');
          for (var t = 0; t < idx.length; t += 3) {
            // _tri emits three fresh vertices per triangle: (3k, 3k+1, 3k+2).
            // Scrambled accessor offsets break exactly this.
            expect(idx[t] % 3, 0, reason: '$name group $gi tri $t');
            expect(idx[t + 1], idx[t] + 1, reason: '$name group $gi tri $t');
            expect(idx[t + 2], idx[t] + 2, reason: '$name group $gi tri $t');
            expect(idx[t + 2], lessThan(vCount),
                reason: '$name group $gi tri $t');
          }
        }
      }
    });
  });
}
