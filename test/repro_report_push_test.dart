import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

    router.push('/design-editor');
    router.push('/design-editor');
    await tester.pumpAndSettle();
  });

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

    router.push('/design');

    Object? error;
    void drain() {
      error ??= tester.takeException();
      while (tester.takeException() != null) { }
    }

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      drain();
    }

    expect(error, isA<AssertionError>(),
        reason: 'an unguarded shell-through push under an overlay must '
            'reproduce the navigator keyReservation crash');
    expect('$error', contains('keyReservation'));

    await tester.pumpWidget(const SizedBox());
    drain();
  });
}
