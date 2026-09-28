import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/shared/widgets/floating_nav_bar.dart';

/// The user's complaint: *"there is no much spacing for the first and last
/// tab and makes the highlight feels out of the box which looks weird."*
///
/// The selected indicator is up to 64dp wide while a 6-tab slot is only
/// ~51dp, so on the first/last tab it extended past the pill's 28px rounded
/// ends and read as clipped / sitting outside the box. The fix insets the
/// destinations; this test pins the resulting clearance so it cannot
/// silently regress.
void main() {
  const destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.grid_view), label: 'Plan'),
    NavigationDestination(icon: Icon(Icons.chair_outlined), label: 'AR'),
    NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
    NavigationDestination(icon: Icon(Icons.favorite_outline), label: 'Saved'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
  ];

  Widget harness({double width = 360, int selected = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 200,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingNavBar(
                    selectedIndex: selected,
                    onDestinationSelected: (_) {},
                    destinations: destinations,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The selected indicator is at most 64dp wide and centred on its slot.
  double indicatorHalfWidth(WidgetTester tester, int index) {
    final slot = tester.getRect(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.byType(NavigationDestination).at(index),
      ),
    );
    // Flutter caps the indicator at 64dp; it cannot be wider than its slot.
    return (slot.width < 64 ? slot.width : 64) / 2;
  }

  /// The *visible* rounded pill, not the outer [Container] box — Container
  /// with a `margin` is a Padding>DecoratedBox, and `getRect` on it includes
  /// that 16px margin. Measuring the margin box overstates clearance by 16dp
  /// at each end, so use the DecoratedBox that actually carries the 28px
  /// radius the user sees.
  Rect pillRect(WidgetTester tester) => tester.getRect(
        find
            .descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );

  for (final selected in [0, 5]) {
    testWidgets(
        'selected tab $selected: highlight clears the rounded pill ends '
        '(360dp phone)', (tester) async {
      await tester.pumpWidget(harness(selected: selected));

      final pill = pillRect(tester);
      final slot = tester.getRect(
        find
            .descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(NavigationDestination).at(selected),
            )
            .first,
      );

      final half = indicatorHalfWidth(tester, selected);
      final indicatorLeft = slot.center.dx - half;
      final indicatorRight = slot.center.dx + half;

      // Report the real numbers — the clearance is the whole point of the
      // fix and a bare boolean would hide a near-miss.
      debugPrint('[nav] pill=$pill slot=$slot '
          'indicator=${indicatorLeft.toStringAsFixed(1)}→'
          '${indicatorRight.toStringAsFixed(1)} '
          'clearL=${(indicatorLeft - pill.left).toStringAsFixed(1)} '
          'clearR=${(pill.right - indicatorRight).toStringAsFixed(1)}');

      // The highlight must sit INSIDE the pill with visible clearance on
      // the rounded end it faces. A negative value is the "out of the box"
      // look the user reported.
      expect(indicatorLeft, greaterThanOrEqualTo(pill.left),
          reason: 'highlight overruns the pill\'s left rounded end');
      expect(indicatorRight, lessThanOrEqualTo(pill.right),
          reason: 'highlight overruns the pill\'s right rounded end');

      // And it must not be flush against the end either — the user asked
      // for "some spacing", not merely non-clipping. The inset is 10dp;
      // 8dp is the floor so a future tweak cannot quietly eat the gap.
      if (selected == 0) {
        expect(indicatorLeft - pill.left, greaterThanOrEqualTo(8.0),
            reason: 'first tab highlight is flush against the pill edge');
      } else {
        expect(pill.right - indicatorRight, greaterThanOrEqualTo(8.0),
            reason: 'last tab highlight is flush against the pill edge');
      }
    });
  }

  testWidgets('all six destinations fit at 360dp with icon-only unselected '
      'labels', (tester) async {
    await tester.pumpWidget(harness(width: 360, selected: 2));

    expect(find.byType(NavigationDestination), findsNWidgets(6));
    expect(tester.takeException(), isNull);

    // No horizontal overflow of the pill's contents.
    final pill = pillRect(tester);
    for (var i = 0; i < 6; i++) {
      final slot = tester.getRect(find
          .descendant(
            of: find.byType(FloatingNavBar),
            matching: find.byType(NavigationDestination).at(i),
          )
          .first);
      expect(slot.left, greaterThanOrEqualTo(pill.left),
          reason: 'destination $i overflows the pill on the left');
      expect(slot.right, lessThanOrEqualTo(pill.right),
          reason: 'destination $i overflows the pill on the right');
    }
  });

  testWidgets('highlight clearance holds on a wide tablet width',
      (tester) async {
    await tester.pumpWidget(harness(width: 800, selected: 0));

    final pill = pillRect(tester);
    final slot = tester.getRect(find
        .descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byType(NavigationDestination).at(0),
        )
        .first);
    final half = indicatorHalfWidth(tester, 0);

    expect(slot.center.dx - half, greaterThanOrEqualTo(pill.left));
    expect(tester.takeException(), isNull);
  });
}
