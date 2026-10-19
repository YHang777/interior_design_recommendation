import 'dart:async';
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
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/chat_suggestion_card.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/services/chat_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _aiReply = 'Try a sage green sofa with oak accents.';

class _ChatCapture {
  int calls = 0;
  Map<String, dynamic>? body;
}

MockClient _client(
  _ChatCapture capture, {
  List<Map<String, dynamic>> suggestions = const [],
}) =>
    MockClient((request) async {
      capture.calls++;
      capture.body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'reply': _aiReply, 'suggestions': suggestions}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

class _RecordingCart extends CartNotifier {
  @override
  List<CartItem> build() => [];

  @override
  void addItem(Product product, {int qty = 1}) {
    state = [...state, CartItem(product: product, quantity: qty)];
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _ChatCapture capture, {
  List<Product> products = const [],
  Stream<List<Product>>? productStream,
  List<Map<String, dynamic>> replySuggestions = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatDatasourceProvider.overrideWithValue(
          ChatDatasource(
            client: _client(capture, suggestions: replySuggestions),
            idTokenProvider: () async => 'tok-123',
          ),
        ),
        marketplaceProductsProvider
            .overrideWith((ref) => productStream ?? Stream.value(products)),
        cartProvider.overrideWith(() => _RecordingCart()),
      ],
      child: const MaterialApp(home: AiRecommendationScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Product _chatProduct() => Product.fromJson({
      'id': 'sofa-1',
      'name': 'Nordic Sofa',
      'price': 1299,
      'stock': 4,
      'category': 'Sofa',
      'designStyle': 'Scandinavian',
      'description': 'Oatmeal boucle three-seater.',
      'image': '',
    });

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

    expect(_chip('Modern'), findsOneWidget);
    expect(_chip('Living Room'), findsOneWidget);
    expect(capture.calls, 0);
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

    await tester.tap(_chip('Minimalist'));
    await tester.pump();
    expect(_inputText(tester), 'Minimalist Living Room');

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

    final saved = await _savedMessages();
    expect(saved, hasLength(2));
    expect(saved.any((m) => m['text'] == '...'), isFalse);
    expect(saved.last['role'], 'model');
    expect(saved.last['text'], _aiReply);
  });

  testWidgets('catalogue payload carries ids and the photo verdict',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture, products: [
      Product.fromJson({
        'id': 'wall-1',
        'name': 'Floral Wallpaper',
        'price': 30,
        'stock': 5,
        'category': 'Wallpaper',
        'description': 'Premium vinyl, waterproof.',
        'designStyle': 'Floral',
        'image': 'https://cdn.example/wall.jpg',
        'vision': {
          'status': 'ok',
          'labels': ['living room', 'sofa'],
          'visualCategory': 'Living room',
          'visualStyle': 'Modern',
          'summary': 'A living room with a grey sofa.',
          'mismatch': {
            'flagged': true,
            'reason': 'Photo shows a room, not wallpaper.',
          },
        },
      }),
    ]);

    await _send(tester, 'Wallpaper for my bedroom?');

    final body = capture.body!;
    final products = (body['products'] as List).cast<Map<String, dynamic>>();
    expect(products, hasLength(1));
    final p = products.single;
    expect(p['id'], 'wall-1');
    expect(p['name'], 'Floral Wallpaper');
    expect(p['description'],
        'In stock. Free delivery. Premium vinyl, waterproof.');
    expect(p['designStyle'], 'Floral');
    expect(p['photoLabels'], ['living room', 'sofa']);
    expect(p['photoSummary'], 'A living room with a grey sofa.');
    expect(p['photoMismatch'], true);
  });

  testWidgets('suggestion card renders and Add hands the live product to the cart',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      products: [_chatProduct()],
      replySuggestions: [
        {'productId': 'sofa-1', 'reason': 'Matches your grey floor.'},
      ],
    );

    await _send(tester, 'Which sofa fits my room?');

    expect(find.byType(ChatSuggestionCard), findsOneWidget);
    expect(find.text('Nordic Sofa'), findsOneWidget);
    expect(find.text('RM 1,299'), findsOneWidget);
    expect(find.text('Matches your grey floor.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(AiRecommendationScreen)));
    final cart = container.read(cartProvider);
    expect(cart, hasLength(1));
    expect(cart.single.product.id, 'sofa-1');
    expect(find.text('Nordic Sofa added to cart'), findsOneWidget);
  });

  testWidgets(
      'a card whose listing vanished says so and keeps the cart empty',
      (tester) async {
    final capture = _ChatCapture();
    final catalogue = StreamController<List<Product>>();
    addTearDown(catalogue.close);
    catalogue.add([_chatProduct()]);
    await _pumpScreen(
      tester,
      capture,
      productStream: catalogue.stream,
      replySuggestions: [
        {'productId': 'sofa-1', 'reason': 'Fits your space.'},
      ],
    );
    await _send(tester, 'Any ideas for my lounge?');
    expect(find.byType(ChatSuggestionCard), findsOneWidget);

    catalogue.add(const []);
    await tester.pumpAndSettle();
    expect(find.byType(ChatSuggestionCard), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('That item is no longer available.'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(AiRecommendationScreen)));
    expect(container.read(cartProvider), isEmpty);
  });

  testWidgets('a reply without suggestions renders no cards', (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture, products: [_chatProduct()]);

    await _send(tester, 'Hello there');

    expect(find.text(_aiReply), findsOneWidget);
    expect(find.byType(ChatSuggestionCard), findsNothing);
  });

  testWidgets('history sheet lists, reopens and deletes saved chats',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    final message = 'What is the best sofa color for a modern living room?';
    final truncatedTitle = '${message.substring(0, 40)}…';
    await _send(tester, message);
    expect(find.text(message), findsOneWidget);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text(truncatedTitle), findsOneWidget);
    expect(find.text('2 messages · Just now'), findsOneWidget);

    await tester.tap(find.text(truncatedTitle));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.text(message), findsWidgets);

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to the design assistant'), findsOneWidget);
    expect(find.text(message), findsNothing);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text(truncatedTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete chat?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No saved chats'), findsOneWidget);

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
    final saved = await _savedMessages();
    expect(saved.last['text'],
        'The design assistant could not reply. Try again.');
  });
}
