// Photo-verification model: the verdict round-trips, legacy products without
// it still parse, `Product.toJson()` never emits the server-owned `vision`
// key, and `preserveStoredVision` re-attaches the stored map around a
// seller's full-document write (the erasure bug that would otherwise hit
// every product edit).

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/product.dart';

ProductVision _verdict() => const ProductVision(
      status: 'ok',
      labels: ['wallpaper roll', 'floral print'],
      visualCategory: 'Wallpaper',
      visualStyle: 'Floral',
      summary: 'A roll of floral wallpaper.',
      mismatchFlagged: true,
      mismatchReason: 'Photo shows a living room, not wallpaper.',
      model: 'gemini-3.1-flash-lite',
    );

void main() {
  group('ProductVision', () {
    test('json round-trip keeps every field', () {
      final parsed = ProductVision.fromJson(_verdict().toJson());
      expect(parsed.status, 'ok');
      expect(parsed.labels, ['wallpaper roll', 'floral print']);
      expect(parsed.visualCategory, 'Wallpaper');
      expect(parsed.visualStyle, 'Floral');
      expect(parsed.summary, 'A roll of floral wallpaper.');
      expect(parsed.mismatchFlagged, isTrue);
      expect(parsed.mismatchReason, 'Photo shows a living room, not wallpaper.');
      expect(parsed.model, 'gemini-3.1-flash-lite');
    });

    test('fromJson coerces garbage mismatch into a clean negative', () {
      final parsed = ProductVision.fromJson({
        'status': 'ok',
        'labels': ['sofa', 42, null, '  '],
        'summary': 'ok',
        'mismatch': {'flagged': 'yes'},
      });
      expect(parsed.labels, ['sofa']); // non-strings and blanks dropped
      expect(parsed.mismatchFlagged, isFalse);
      expect(parsed.mismatchReason, '');
    });
  });

  group('Product.vision', () {
    Product product({Map<String, dynamic> extra = const {}}) =>
        Product.fromJson({
          'id': 'p1',
          'name': 'Wallpaper',
          'price': 50,
          'stock': 3,
          'image': 'https://cdn/x.jpg',
          ...extra,
        });

    test('parses a stored vision map', () {
      final p = product(extra: {'vision': _verdict().toJson()});
      expect(p.vision, isNotNull);
      expect(p.vision!.mismatchFlagged, isTrue);
      expect(p.vision!.visualCategory, 'Wallpaper');
    });

    test('legacy product without vision parses as null', () {
      expect(product().vision, isNull);
      expect(product(extra: {'vision': 'not-a-map'}).vision, isNull);
    });

    test('toJson NEVER emits the server-owned vision key', () {
      final p = product(extra: {'vision': _verdict().toJson()});
      expect(p.toJson().containsKey('vision'), isFalse);
      // Round-trip loss is expected and correct: vision lives in Firestore,
      // re-attached on write by preserveStoredVision.
      expect(Product.fromJson(p.toJson()).vision, isNull);
    });
  });

  group('preserveStoredVision', () {
    final write = {'id': 'p1', 'name': 'Edited name'};
    final stored = {'id': 'p1', 'name': 'Old name'};

    test('re-attaches the stored vision map to a seller write', () {
      final vision = _verdict().toJson();
      final out = preserveStoredVision(write, {...stored, 'vision': vision});
      expect(out['vision'], vision);
      expect(out['name'], 'Edited name'); // the seller's edit still wins
    });

    test('leaves the write untouched for legacy/unanalyzed products', () {
      expect(preserveStoredVision(write, stored), same(write));
      expect(preserveStoredVision(write, null), same(write));
      // A stored `vision: null` means nothing to preserve.
      expect(preserveStoredVision(write, {...stored, 'vision': null}), same(write));
    });
  });
}
