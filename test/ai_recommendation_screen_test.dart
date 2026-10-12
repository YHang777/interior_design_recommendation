// AI design chat screen: no forced style/room gate, chips fill the input,
// the transcript + chip context ship to the proxy, and saved chats can be
// listed, reopened and deleted from the history sheet.
//
// Pumped at phone width (393×852, same as design_report_nav_test) so any
// Row/RenderFlex overflow fails the run. The datasource talks to the real
// ChatDatasource over a MockClient — the app's chatApiUrl points at the
// deployed backend, so with a mocked http.Client no network is touched.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _aiReply = 'Try a sage green sofa with oak accents.';

class _ChatCapture {
  int calls = 0;
  Map<String, dynamic>? body;
}

MockClient _client(_ChatCapture capture) => MockClient((request) async {
      capture.calls++;
      capture.body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'reply': _aiReply}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

Future<void> _pumpScreen(WidgetTester tester, _ChatCapture capture) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatDatasourceProvider.overrideWithValue(
          ChatDatasource(
            client: _client(capture),
            idTokenProvider: () async => 'tok-123',
          ),
        ),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: AiRecommendationScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

String _inputText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

Future<List<Map<String, dynamic>>> _savedMessages() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(ChatHistoryStore.prefsKey);
  expect(raw, isNotNull);
  final sessions = jsonDecode(raw!) as List;
  final session = sessions.first as Map<String, dynamic>;
  return (session['messages'] as List).cast<Map<String, dynamic>>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('input is available immediately — no style/room gate',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.text('Design Style'), findsNothing);
    expect(find.text('Room Type'), findsNothing);
    expect(find.text('Welcome to the design assistant'), findsOneWidget);

    // Quick shortcuts sit above the input.
    expect(_chip('Modern'), findsOneWidget);
    expect(_chip('Living Room'), findsOneWidget);
    expect(capture.calls, 0); // nothing auto-sent
  });

  testWidgets('chips fill the input with the composed phrase, never auto-send',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    await tester.tap(_chip('Modern'));
    await tester.pump();
    expect(_inputText(tester), 'Modern');

    await tester.tap(_chip('Living Room'));
    await tester.pump();
    expect(_inputText(tester), 'Modern Living Room');

    // Swapping the style keeps the room slot.
    await tester.tap(_chip('Minimalist'));
    await tester.pump();
    expect(_inputText(tester), 'Minimalist Living Room');

    // Tapping the selected chip clears its slot.
    await tester.tap(_chip('Minimalist'));
    await tester.pump();
    expect(_inputText(tester), 'Living Room');

    expect(capture.calls, 0);
  });

  testWidgets('sending ships the transcript and chip context to the proxy',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    await tester.tap(_chip('Modern'));
    await tester.pump();
    await tester.tap(_chip('Living Room'));
    await tester.pump();
    await _send(tester, 'Best sofa for this room?');

    // User bubble in, AI reply in.
    expect(find.text('Best sofa for this room?'), findsOneWidget);
    expect(find.text(_aiReply), findsOneWidget);
    expect(capture.calls, 1);

    final body = capture.body!;
    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.last['role'], 'user');
    expect(messages.last['text'], 'Best sofa for this room?');
    expect(body['style'], 'Modern');
    expect(body['room'], 'Living Room');
    expect(body['products'], isEmpty);

    // The typing placeholder is render-only — never persisted.
    final saved = await _savedMessages();
    expect(saved, hasLength(2));
    expect(saved.any((m) => m['text'] == '...'), isFalse);
    expect(saved.last['role'], 'model');
    expect(saved.last['text'], _aiReply);
  });

  testWidgets('history sheet lists, reopens and deletes saved chats',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    final message = 'What is the best sofa color for a modern living room?';
    final truncatedTitle = '${message.substring(0, 40)}…';
    await _send(tester, message);
    expect(find.text(message), findsOneWidget); // the user bubble

    // Open the history sheet — the row title is the truncated first message.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text(truncatedTitle), findsOneWidget);
    expect(find.text('2 messages · Just now'), findsOneWidget);

    // Tap the row: sheet closes, that chat is open again.
    await tester.tap(find.text(truncatedTitle));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.text(message), findsWidgets); // bubbles back on screen

    // New chat: composer fresh, welcome back, history untouched.
    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to the design assistant'), findsOneWidget);
    expect(find.text(message), findsNothing);

    // Delete flow: open sheet → delete → confirm → gone.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text(truncatedTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete chat?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No saved chats'), findsOneWidget);

    // Store agrees.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(ChatHistoryStore.prefsKey) ?? '[]';
    expect(jsonDecode(raw) as List, isEmpty);
  });

  testWidgets('a failed reply lands as a friendly error bubble',
      (tester) async {
    final failing = MockClient((request) async {
      return http.Response('{"error":{"code":"UPSTREAM_ERROR"}}', 502);
    });
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatDatasourceProvider.overrideWithValue(
            ChatDatasource(
              client: failing,
              idTokenProvider: () async => 'tok-123',
            ),
          ),
          marketplaceProductsProvider
              .overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: AiRecommendationScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _send(tester, 'Hello?');

    expect(find.text('The design assistant could not reply. Try again.'),
        findsOneWidget);
    // The error is persisted as the model's turn, so reopening keeps it.
    final saved = await _savedMessages();
    expect(saved.last['text'],
        'The design assistant could not reply. Try again.');
  });
}
