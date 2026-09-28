import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/core/constants/app_colors.dart';
import 'package:interior_design_recommendation/core/theme/app_theme.dart';
import 'package:interior_design_recommendation/shared/widgets/page_heading.dart';

/// The supplier "Products" heading's gradient **Add product** chip used to
/// blow up with `BoxConstraints forces an infinite width` (plus follow-on
/// `RenderBox was not laid out` errors).
///
/// Why: the theme sets `ElevatedButton` `minimumSize: Size(double.infinity, 52)`
/// (full-width form CTAs), and `PageHeading`'s actions sit in a
/// `Row(mainAxisSize: min)` — a flex passes **unbounded** main-axis width to
/// non-flexible children, so the button computed an infinite min-width.
/// `Expanded`/`Flexible` cannot help: that Row is itself a non-flex child of
/// the heading's outer Row, so it has no finite width to share. The button
/// must therefore size itself to its content (`minimumSize: Size.zero`).
///
/// This test pins the working subtree from
/// `product_management_screen.dart` (`_content()` PageHeading actions).
void main() {
  // `ElevatedButton.icon` builds with a private runtimeType, so
  // `find.byType(ElevatedButton)` matches nothing — use a subtype predicate.
  Finder addProductButton() =>
      find.byWidgetPredicate((w) => w is ElevatedButton);

  Future<void> pumpHeading(WidgetTester tester, Size surface) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              PageHeading(
                title: 'Products',
                actions: [
                  // Keep in sync with product_management_screen.dart `_content()`.
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.accent, AppColors.gradientGreen],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add product',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add product chip lays out with a finite width', (tester) async {
    // A typical Android phone, not the 800x600 test default.
    await pumpHeading(tester, const Size(390, 844));

    // The infinite-width assertion (and any consequent "was not laid out").
    expect(tester.takeException(), isNull,
        reason: 'laying out the heading action threw — infinite width?');

    expect(find.text('Add product'), findsOneWidget);
    final button = addProductButton();
    expect(button, findsOneWidget);

    final rect = tester.getRect(button);
    debugPrint('[add-product] w=${rect.width.toStringAsFixed(1)} '
        'h=${rect.height.toStringAsFixed(1)} '
        'right=${rect.right.toStringAsFixed(1)} '
        'surface=${tester.view.physicalSize}');

    // 1. Finite — the actual bug was width = infinity.
    expect(rect.width.isFinite, isTrue, reason: 'button width is infinite');
    expect(rect.width.isNaN, isFalse);

    // 2. A compact trailing chip that hugs its content, not a stretched
    //    full-width CTA and not the theme's 52px minimum height.
    expect(rect.width, lessThan(390.0),
        reason: 'chip should hug its label, not span the screen');
    expect(rect.height, lessThan(52.0),
        reason: 'chip should use its own 8px vertical padding, not the '
            'theme 52px full-width CTA minimum');

    // 3. Still a real tappable control, icon + label intact.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.getSize(button).width, greaterThan(80.0),
        reason: 'chip collapsed too far — label/icons lost their padding');
  });

  testWidgets('chip stays finite at a narrow width (responsive)',
      (tester) async {
    await pumpHeading(tester, const Size(320, 640));

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(addProductButton());
    expect(rect.width.isFinite, isTrue);
    // 320 surface − 16 left padding: the chip must fit the padded line.
    expect(rect.right, lessThanOrEqualTo(320.0 - 16.0 + 0.5),
        reason: 'chip overflows the right edge on a 320dp screen');
  });
}
