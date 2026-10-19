import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/shared/widgets/confirm_dialog.dart';

void main() {
  Future<void> openDialog(WidgetTester tester,
      {bool destructive = true, String confirmLabel = 'Logout'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showConfirmDialog(
                context,
                title: 'Logout?',
                message: 'You will be signed out.',
                confirmLabel: confirmLabel,
                destructive: destructive,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('two side-by-side buttons, long, centred, with a gap',
      (tester) async {
    await openDialog(tester);

    final cancelFinder = find.widgetWithText(OutlinedButton, 'Cancel');
    final confirmFinder = find.widgetWithText(ElevatedButton, 'Logout');
    expect(cancelFinder, findsOneWidget);
    expect(confirmFinder, findsOneWidget);

    final cancelRect = tester.getRect(cancelFinder);
    final confirmRect = tester.getRect(confirmFinder);
    final rowRect = tester.getRect(find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Row))
        .first);

    final gap = confirmRect.left - cancelRect.right;
    final eachShouldBe = (rowRect.width - gap) / 2;

    debugPrint('[dialog] surface=${tester.view.physicalSize} '
        'rowW=${rowRect.width.toStringAsFixed(1)} '
        'cancel=${cancelRect.width.toStringAsFixed(1)} '
        'confirm=${confirmRect.width.toStringAsFixed(1)} '
        'gap=${gap.toStringAsFixed(1)} '
        'leftMargin=${(cancelRect.left - rowRect.left).toStringAsFixed(1)} '
        'rightMargin=${(rowRect.right - confirmRect.right).toStringAsFixed(1)}');

    expect(cancelRect.center.dy, closeTo(confirmRect.center.dy, 1.0),
        reason: 'the two buttons are stacked vertically instead of '
            'sitting side by side');
    expect(cancelRect.center.dx, lessThan(confirmRect.center.dx),
        reason: 'Cancel should be on the left');

    expect(cancelRect.width, closeTo(eachShouldBe, 1.0),
        reason: 'Cancel is not a long button');
    expect(confirmRect.width, closeTo(eachShouldBe, 1.0),
        reason: 'Logout is not a long button');

    expect(gap, greaterThanOrEqualTo(12.0),
        reason: 'the buttons still have no spacing between them');

    final leftMargin = cancelRect.left - rowRect.left;
    final rightMargin = rowRect.right - confirmRect.right;
    expect(leftMargin, closeTo(rightMargin, 2.0),
        reason: 'the button pair is not centred');

    expect(cancelRect.width + gap + confirmRect.width,
        closeTo(rowRect.width, 2.0),
        reason: 'the buttons do not fill the available action row');
  });

  testWidgets('labels are centred inside their buttons', (tester) async {
    await openDialog(tester);

    for (final (label, buttonFinder) in [
      ('Cancel', find.widgetWithText(OutlinedButton, 'Cancel')),
      ('Logout', find.widgetWithText(ElevatedButton, 'Logout')),
    ]) {
      final textRect = tester.getRect(find.text(label).hitTestable());
      final buttonRect = tester.getRect(buttonFinder);
      expect(textRect.center.dx, closeTo(buttonRect.center.dx, 2.0),
          reason: '"$label" is not centred inside its button');
    }
  });

  testWidgets('destructive confirm is styled for the action', (tester) async {
    await openDialog(tester, destructive: true);
    final button =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Logout'));
    expect(button.onPressed, isNotNull);
    expect(button.style?.backgroundColor?.resolve({}), isNotNull);
  });

  testWidgets('custom confirm label renders and still lays out long',
      (tester) async {
    await openDialog(tester,
        destructive: true, confirmLabel: 'Delete account');
    expect(find.text('Delete account'), findsOneWidget);
    final confirmRect =
        tester.getRect(find.widgetWithText(ElevatedButton, 'Delete account'));
    final rowRect = tester.getRect(find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Row))
        .first);
    expect(confirmRect.width, greaterThan(rowRect.width * 0.40),
        reason: 'long label must still get a long button');
  });

  testWidgets('no layout exception and Cancel dismisses the dialog',
      (tester) async {
    await openDialog(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'Cancel must dismiss the dialog');
  });
}
