import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        currentUserProvider.overrideWithValue(null),
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
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text('No saved chats'), findsOneWidget);
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
