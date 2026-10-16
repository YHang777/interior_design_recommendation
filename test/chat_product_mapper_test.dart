// Shared Product → chat-proxy mapping: the compact facts line (stock,
// dims, delivery, seller, eco, sale) travels first inside description so
// it survives the 200-char clip, hard clips keep a long listing from 400ing
// the request, vision fields only ship on a verified verdict, and the
// catalogue/suggestion helpers stay on live active products.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_product_mapper.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/models/product.dart';

Product _product({
  String id = 'p1',
  String name = 'Nordic Sofa',
  int price = 1299,
  int stock = 10,
  String description = 'Oatmeal boucle three-seater.',
  String designStyle = 'Scandinavian',
  bool isActive = true,
  bool isEcoFriendly = false,
  int? originalPrice,
  bool shippingEnabled = false,
  int shippingFee = 0,
  bool shippingLongDistanceNotice = false,
  ProductDimensions? dimensions,
  ProductVision? vision,
  Supplier supplier = const Supplier(
      id: 's1', name: 'Seller', phone: '', address: '', email: ''),
}) =>
    Product(
      id: id,
      name: name,
      price: price,
      stock: stock,
      image: '',
      description: description,
      designStyle: designStyle,
      category: 'Furniture',
      supplier: supplier,
      isActive: isActive,
      isEcoFriendly: isEcoFriendly,
      originalPrice: originalPrice,
      shippingEnabled: shippingEnabled,
      shippingFee: shippingFee,
      shippingLongDistanceNotice: shippingLongDistanceNotice,
      dimensions: dimensions,
      vision: vision,
    );

void main() {
  group('productFactsLine', () {
    test('answers stock from the quick-question chips', () {
      expect(productFactsLine(_product()), contains('In stock'));
      expect(productFactsLine(_product(stock: 3)), contains('Only 3 left'));
      expect(productFactsLine(_product(stock: 0)), contains('Out of stock'));
    });

    test('free vs paid delivery, with the long-distance note', () {
      expect(productFactsLine(_product()), contains('Free delivery'));
      expect(
        productFactsLine(
            _product(shippingEnabled: true, shippingFee: 10)),
        contains('Delivery RM 10'),
      );
      expect(
        productFactsLine(_product(
            shippingEnabled: true,
            shippingFee: 10,
            shippingLongDistanceNotice: true)),
        contains('Deliveries over 30 km incur extra charges.'),
      );
      // A stored fee behind a disabled switch never leaks.
      expect(
        productFactsLine(_product(shippingEnabled: false, shippingFee: 10)),
        contains('Free delivery'),
      );
    });

    test('seller verification, eco, and the sale discount', () {
      expect(
        productFactsLine(_product(
            supplier: const Supplier(
                id: 's1',
                name: 'Seller',
                phone: '',
                address: '',
                email: '',
                verificationStatus: 'verified'))),
        contains('Verified seller'),
      );
      expect(productFactsLine(_product()), isNot(contains('Verified seller')));
      expect(productFactsLine(_product(isEcoFriendly: true)),
          contains('Eco-friendly'));
      expect(
        productFactsLine(_product(price: 1600, originalPrice: 2000)),
        contains('20% off'),
      );
      expect(productFactsLine(_product()), isNot(contains('off')));
    });

    test('dimensions only when complete, in the proxy label', () {
      expect(
        productFactsLine(_product(
            dimensions:
                const ProductDimensions(widthM: 1.0, heightM: 1.5, depthM: 0.6))),
        contains('Dimensions W 1.0 × H 1.5 × D 0.6 m'),
      );
      expect(productFactsLine(_product(
              dimensions: const ProductDimensions(
                  widthM: 1.0, heightM: 0, depthM: 0.6))),
          isNot(contains('Dimensions')));
      expect(productFactsLine(_product()), isNot(contains('Dimensions')));
    });
  });

  group('productToChatProduct', () {
    test('carries identity fields and clips designStyle at 120', () {
      final mapped =
          productToChatProduct(_product(designStyle: 'x' * 150));
      expect(mapped.id, 'p1');
      expect(mapped.name, 'Nordic Sofa');
      expect(mapped.price, 1299);
      expect(mapped.category, 'Furniture');
      expect(mapped.designStyle, hasLength(kChatStyleClip));
    });

    test('facts lead the description and the total clips at 200', () {
      final mapped = productToChatProduct(_product(description: 'd' * 500));
      expect(mapped.description, hasLength(kChatDescriptionClip));
      expect(
          mapped.description, startsWith('In stock. Free delivery. '));
      // A fact-dense product still leads with its facts.
      final dense = productToChatProduct(_product(
        stock: 2,
        shippingEnabled: true,
        shippingFee: 15,
        isEcoFriendly: true,
        dimensions:
            const ProductDimensions(widthM: 1.0, heightM: 1.5, depthM: 0.6),
        description: 'd' * 500,
      ));
      expect(dense.description, startsWith('Only 2 left.'));
      expect(dense.description, contains('Delivery RM 15'));
      expect(dense.description, hasLength(kChatDescriptionClip));
    });

    test('seller copy follows the facts when the description is short', () {
      final mapped = productToChatProduct(_product());
      expect(mapped.description,
          'In stock. Free delivery. Oatmeal boucle three-seater.');
    });

    test('vision fields only ship when the verdict is ok', () {
      final failed = productToChatProduct(_product(
        vision: const ProductVision(
            status: 'failed', labels: ['sofa'], summary: 'A living room.'),
      ));
      expect(failed.photoLabels, isEmpty);
      expect(failed.photoSummary, isNull);
      expect(failed.photoMismatch, false);

      final ok = productToChatProduct(_product(
        vision: const ProductVision(
          status: 'ok',
          labels: [
            'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
          ],
          summary: 'A living room.',
          mismatchFlagged: true,
        ),
      ));
      expect(ok.photoLabels, hasLength(kChatLabelLimit));
      expect(ok.photoSummary, 'A living room.');
      expect(ok.photoMismatch, true);
    });
  });

  group('productsToChatContext', () {
    test('drops inactive listings and caps at 12', () {
      final products = [
        for (var i = 0; i < 15; i++) _product(id: 'p$i'),
        _product(id: 'dead', isActive: false),
      ];
      final ctx = productsToChatContext(products);
      expect(ctx, hasLength(kChatProductLimit));
      expect(ctx.map((p) => p.id), isNot(contains('dead')));
      expect(ctx.map((p) => p.id), containsAll(['p0', 'p11']));
    });
  });

  group('hydrateChatSuggestions', () {
    test('keeps known ids and drops unknown ones', () {
      final live = [
        _product(id: 'a', name: 'Chair A'),
        _product(id: 'b', name: 'Chair B'),
      ];
      final out = hydrateChatSuggestions(const [
        ChatSuggestionRef(productId: 'a', reason: 'Suits your space.'),
        ChatSuggestionRef(productId: 'ghost', reason: 'Gone.'),
      ], live);
      expect(out, hasLength(1));
      expect(out.single.productId, 'a');
      expect(out.single.name, 'Chair A');
      expect(out.single.price, 1299);
      expect(out.single.image, '');
      expect(out.single.reason, 'Suits your space.');
    });

    test('empty refs short-circuit to an empty list', () {
      expect(
          hydrateChatSuggestions(const [], [_product()]), isEmpty);
    });
  });
}
