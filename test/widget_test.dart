import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/app.dart';

void main() {
  testWidgets('Interior Design App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InteriorDesignApp(),
      ),
    );

    // Verify that the app loads and shows the login screen
    expect(find.byType(MaterialApp), findsOneWidget);
    // The login screen should render with email/password fields
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back!'), findsOneWidget);
  });
}
