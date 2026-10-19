import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/design_report_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';

Page<T> _page<T>(Widget child) => CustomTransitionPage<T>(
      child: child,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 200),
    );

List<Override> _overrides() => [
      savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(const [])),
    ];

Future<void> _pumpPhone(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
}

void main() {
  testWidgets('Reports → Create a design → planner renders cleanly',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/design/report',
      routes: [
        GoRoute(
          path: '/design/report',
          pageBuilder: (_, __) => _page(const DesignReportScreen()),
        ),
        GoRoute(
          path: '/design-editor',
          pageBuilder: (_, __) => _page(const RoomScannerScreen()),
        ),
      ],
    );

    await _pumpPhone(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('Create a design'), findsOneWidget);

    await tester.tap(find.text('Create a design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RoomScannerScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('direct push (dashboard path) renders cleanly',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/design-editor',
      routes: [
        GoRoute(
          path: '/design-editor',
          pageBuilder: (_, __) => _page(const RoomScannerScreen()),
        ),
      ],
    );

    await _pumpPhone(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoomScannerScreen), findsOneWidget);
  });

  testWidgets(
      'pushed planner has a Material — no yellow fallback underlines',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/design/report',
      routes: [
        GoRoute(
          path: '/design/report',
          pageBuilder: (_, __) => _page(const DesignReportScreen()),
        ),
        GoRoute(
          path: '/design-editor',
          pageBuilder: (_, __) => _page(const RoomScannerScreen()),
        ),
      ],
    );

    await _pumpPhone(
      tester,
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Create a design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoomScannerScreen), findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(RoomScannerScreen),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: 'RoomScannerScreen must provide its own Material when '
          'pushed full-screen (/design-editor)',
    );

    final textElements = tester.elementList(
      find.descendant(
        of: find.byType(RoomScannerScreen),
        matching: find.byType(Text),
      ),
    );
    expect(textElements, isNotEmpty, reason: 'planner should render text');
    for (final el in textElements) {
      final ambient = DefaultTextStyle.of(el);
      final label = (el.widget as Text).data ?? '<rich text>';
      expect(
        ambient.style.decorationColor,
        isNot(const Color(0xFFFFFF00)),
        reason: 'Text "$label" inherits the yellow missing-Material '
            'fallback style',
      );
      expect(
        ambient.style.decoration,
        isNot(TextDecoration.underline),
        reason: 'Text "$label" is underlined by the missing-Material '
            'fallback style',
      );
    }
  });
}
