// Buyer-facing "supplier verified" badge tests.
//
// This is a TRUST signal: the badge may only ever appear for a supplier an
// admin actually approved. These tests pin both halves of that contract —
// it renders for 'verified', and for every other status it renders nothing
// at all (no greyed-out "Unverified" variant exists on the buyer side).
// Pure widget tests: no Firebase, no network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/shared/widgets/product_card.dart';
import 'package:interior_design_recommendation/shared/widgets/verified_badge.dart';

const _longSellerName =
    'The Extraordinarily Fine Handcrafted Furniture Emporium Sdn Bhd';

Supplier _supplier(String status, {String name = 'Nordic Home'}) => Supplier(
      id: 's1',
      name: name,
      phone: '',
      address: '',
      email: '',
      verificationStatus: status,
    );

Product _product(Supplier supplier) => Product(
      id: 'p1',
      name: 'Oak Armchair',
      price: 450,
      stock: 5,
      image: '',
      description: '',
      designStyle: 'Modern',
      category: 'Furniture',
      supplier: supplier,
    );

/// A typical Android phone width — the badge must stay legible and never
/// overflow a product card laid out at 360dp.
Future<void> _usePhoneWidth(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('VerifiedBadge', () {
    testWidgets('renders the pill for a verified supplier', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: VerifiedBadge(verificationStatus: 'verified'),
        ),
      ));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders NOTHING for none/pending/rejected', (tester) async {
      for (final status in ['none', 'pending', 'rejected']) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: VerifiedBadge(verificationStatus: status),
          ),
        ));

        expect(find.text('Verified'), findsNothing,
            reason: '"$status" must never show a verified badge');
        expect(find.byIcon(Icons.verified), findsNothing,
            reason: '"$status" must never show the verified icon');
        expect(find.text('Unverified'), findsNothing,
            reason: 'the buyer side has no "Unverified" variant at all');
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('VerifiedSellerLine', () {
    testWidgets('shows seller name + badge when verified', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VerifiedSellerLine(supplier: _supplier('verified')),
        ),
      ));

      expect(find.text('Nordic Home'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders NOTHING for non-verified statuses', (tester) async {
      for (final status in ['none', 'pending', 'rejected']) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: VerifiedSellerLine(supplier: _supplier(status)),
          ),
        ));

        expect(find.text('Verified'), findsNothing);
        expect(find.byIcon(Icons.verified), findsNothing);
        // No "Unverified" label either — absence of the badge is the signal.
        expect(find.text('Unverified'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('ProductCard grid cell', () {
    testWidgets('verified seller badge fits without overflow', (tester) async {
      await _usePhoneWidth(tester);

      // Same cell size the marketplace grid uses (2-up, aspect 0.68).
      const cell = Size(158, 232);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cell.width,
              height: cell.height,
              child: ProductCard(
                product: _product(_supplier('verified', name: _longSellerName)),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the badge row must fit a 360dp-wide card grid');
    });

    testWidgets('still fits on a narrow 320dp phone', (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 2-up grid cell at 320dp: (320 − 32 padding − 12 gap) / 2, aspect 0.68.
      const cell = Size(138, 203);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: cell.width,
              height: cell.height,
              child: ProductCard(
                product: _product(_supplier('verified', name: _longSellerName)),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('Verified'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the badge must not push the card into overflow on the '
              'narrowest phones');
    });

    testWidgets('unverified card shows no badge at all', (tester) async {
      await _usePhoneWidth(tester);

      for (final status in ['none', 'pending', 'rejected']) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 158,
                height: 232,
                child: ProductCard(product: _product(_supplier(status))),
              ),
            ),
          ),
        ));

        expect(find.text('Verified'), findsNothing,
            reason: '"$status" card must not claim verification');
        expect(find.byIcon(Icons.verified), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('compact card (related rail) also fits', (tester) async {
      await _usePhoneWidth(tester);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              height: 230,
              child: ProductCard(
                compact: true,
                product: _product(_supplier('verified', name: _longSellerName)),
              ),
            ),
          ),
        ),
      ));

      expect(find.text('Verified'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
