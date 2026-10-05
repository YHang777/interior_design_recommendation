// Reproduces the reported device issue: opening the Room Planner from
// Profile → Reports → "Create a design" (report route underneath) showed
// yellow-striped text, while the normal push looked fine.
//
// In widget tests any RenderFlex overflow or build exception surfaces as a
// test failure — which is exactly what the device's redacted logcat hid.
// Both entry paths are pumped at phone width (not the default 800×600),
// because Row overflows only care about narrow constraints.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/design_report_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';

/// Mirrors app_router's `_buildPage`: same CustomTransitionPage + fade.
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

    // Stream resolves → the empty state the user tapped.
    await tester.pump();
    await tester.pump();
    expect(find.text('Create a design'), findsOneWidget);

    await tester.tap(find.text('Create a design'));
    await tester.pump(); // start the push
    await tester.pump(const Duration(milliseconds: 400)); // finish 200ms fade

    expect(find.byType(RoomScannerScreen), findsOneWidget);

    // Let init settle. Any overflow/exception reported along the way fails
    // this test — including the yellow RenderFlex stripes seen on device.
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
}
