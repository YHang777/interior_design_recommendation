// History sheet overflow regression: on short windows the empty state
// ("No saved chats") used to blow past the sheet's height cap —
// showModalBottomSheet without isScrollControlled caps at 9/16 of the
// screen and Expanded force-filled that cap against EmptyState's fixed
// ~263px stack. The main suite pumps at 393×852, which always fits, so
// these cases pin the surface down to window sizes that actually broke.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stored session so the non-empty branch can render too.
void _seedSession({required String title}) {
  SharedPreferences.setMockInitialValues({
    ChatHistoryStore.prefsKey: jsonEncode([
      {
        'id': 's1',
        'title': title,
        'messages': [
          {
            'role': 'user',
            'text': 'Need a sofa',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
    ]),
  });
}

Future<void> _pumpScreen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatDatasourceProvider.overrideWithValue(
          ChatDatasource(
            client: null,
            idTokenProvider: () async => 'tok-123',
          ),
        ),
        marketplaceProductsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: AiRecommendationScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final size in const [Size(393, 500), Size(320, 480)]) {
    testWidgets('empty history state fits a ${size.width}×${size.height} window',
        (tester) async {
      await _pumpScreen(tester, size);
      expect(tester.takeException(), isNull); // the screen itself fits

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text('No saved chats'), findsOneWidget);
      // A RenderFlex overflow surfaces as a test exception — the
      // regression this file exists to catch.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved-chat rows still render in a short window', (tester) async {
    _seedSession(title: 'Sofa help');
    await _pumpScreen(tester, const Size(393, 500));

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('Sofa help'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
