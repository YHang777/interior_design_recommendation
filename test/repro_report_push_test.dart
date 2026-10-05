import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Mirrors app_router.dart: full-screen routes use a custom pageBuilder
// returning a keyless CustomTransitionPage; the shell is an indexedStack
// StatefulShellRoute whose branch routes use `builder`.
Page<T> _page<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 200),
  );
}

void main() {
  testWidgets('push /design-editor on top of /design/report', (tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/design/report',
          pageBuilder: (_, __) => _page(const Text('report')),
        ),
        GoRoute(
          path: '/design-editor',
          pageBuilder: (_, __) => _page(const Text('editor')),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const Text('profile'),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/design',
                builder: (_, __) => const Text('scanner'),
              ),
            ]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/design/report');
    await tester.pumpAndSettle();
    expect(find.text('report'), findsOneWidget);

    // The failing action: "Create a design" on the empty report screen.
    router.push('/design-editor');
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
  });

  testWidgets('double-push the same location (rapid double-tap)',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/design/report',
          pageBuilder: (_, __) => _page(const Text('report')),
        ),
        GoRoute(
          path: '/design-editor',
          pageBuilder: (_, __) => _page(const Text('editor')),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const Text('profile'),
              ),
            ]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/design/report');
    await tester.pump(const Duration(milliseconds: 50));

    // Two quick pushes of the same location before the first lands.
    router.push('/design-editor');
    router.push('/design-editor');
    await tester.pumpAndSettle();
  });

  // Mechanism check: pushing a location that matches THROUGH the shell
  // (like /design) while an imperative overlay (the report screen) sits
  // on top makes RouteMatchList._createNewMatchUntilIncompatible append
  // a SECOND ShellRouteMatch copy — both pages carry
  // ValueKey(route.hashCode) → `!keyReservation.contains(key)`.
  //
  // This test uses a plain GoRouter on purpose: it documents why the
  // app's GuardedGoRouter reroutes this combination to `go()` instead
  // (see design_report_real_router_test.dart for the guarded behavior).
  testWidgets('push a shell-through route on top of an imperative overlay',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/design/report',
          pageBuilder: (_, __) => _page(const Text('report')),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const Text('profile'),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/design',
                builder: (_, __) => const Text('scanner'),
              ),
            ]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/design/report');
    await tester.pumpAndSettle();
    expect(find.text('report'), findsOneWidget);

    // The historical bad action: pushNamed(homeownerScan) from the report.
    router.push('/design');

    // The corrupt navigator throws more than once: the duplicate-key
    // assertion itself, then collateral asserts while the broken subtree
    // is torn down (`_dependents.isEmpty`). Pump and drain so the first
    // recorded exception — the one being documented — is the one asserted
    // on below.
    Object? error;
    void drain() {
      error ??= tester.takeException();
      while (tester.takeException() != null) {/* discard collateral */}
    }

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      drain();
    }

    // The duplicate-key assertion fires exactly as it did on device.
    expect(error, isA<AssertionError>(),
        reason: 'an unguarded shell-through push under an overlay must '
            'reproduce the navigator keyReservation crash');
    expect('$error', contains('keyReservation'));

    // Unmount the corrupt tree NOW, inside the test body. The harness's
    // own cleanup (runApp(postTestMessage) at the end of _runTestBody)
    // would deactivate it later and record `_dependents.isEmpty` with no
    // remaining chance to takeException — failing the test. Replacing the
    // root here keeps that collateral assert drainable.
    await tester.pumpWidget(const SizedBox());
    drain();
  });
}
