import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/chat_data_card.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/chat_quick_select_sheet.dart';
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
  _RecordingCart([this.seed = const []]);
  final List<CartItem> seed;

  @override
  List<CartItem> build() => seed;

  @override
  void addItem(Product product, {int qty = 1}) {
    state = [...state, CartItem(product: product, quantity: qty)];
  }
}

AppUser _user() => AppUser(
      uid: 'u1',
      email: 'aina@example.com',
      name: 'Aina',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  _ChatCapture capture, {
  List<Product> products = const [],
  Stream<List<Product>>? productStream,
  List<Map<String, dynamic>> replySuggestions = const [],
  List<CartItem> cart = const [],
  BudgetPlan? budget,
  bool fail = false,
  bool signedIn = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final client = fail
      ? MockClient((request) async {
          capture.calls++;
          capture.body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"error":{"code":"UPSTREAM_ERROR"}}', 502);
        })
      : _client(capture, suggestions: replySuggestions);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatDatasourceProvider.overrideWithValue(
          ChatDatasource(
            client: client,
            idTokenProvider: () async => 'tok-123',
          ),
        ),
        marketplaceProductsProvider
            .overrideWith((ref) => productStream ?? Stream.value(products)),
        cartProvider.overrideWith(() => _RecordingCart(cart)),
        currentUserProvider.overrideWithValue(signedIn ? _user() : null),
        budgetPlanProvider.overrideWith((ref) => Stream.value(budget)),
        savedDesignsProvider.overrideWith((ref) => Stream.value(const [])),
        customerOrdersProvider.overrideWith((ref) => Stream.value(const [])),
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

Future<void> _openQuickSelect(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-quick-select')));
  await tester.pumpAndSettle();
}

Future<void> _closeQuickSelect(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close));
  await tester.pumpAndSettle();
}

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

    // Quick options hide behind the sheet, not inline chip rows.
    expect(find.byKey(const ValueKey('ai-quick-select')), findsOneWidget);
    expect(_chip('Modern'), findsNothing);
    expect(_chip('Living Room'), findsNothing);

    await _openQuickSelect(tester);
    expect(_chip('Modern'), findsOneWidget);
    expect(_chip('Living Room'), findsOneWidget);
    expect(capture.calls, 0);
  });

  testWidgets('chips fill the input with the composed phrase, never auto-send',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);
    await _openQuickSelect(tester);

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

  testWidgets('a suggested question fills the input and closes the sheet',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);
    await _openQuickSelect(tester);

    final prompt = find.descendant(
      of: find.byType(ChatQuickSelectSheet),
      matching: find.text('Suggest a style for my living room'),
    );
    await tester.scrollUntilVisible(
      prompt,
      40,
      scrollable: find.descendant(
        of: find.byType(ChatQuickSelectSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(prompt);
    await tester.pumpAndSettle();

    expect(_chip('Modern'), findsNothing);
    expect(_inputText(tester), 'Suggest a style for my living room');
    expect(capture.calls, 0);
  });

  testWidgets('sending ships the transcript and chip context to the proxy',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    await _openQuickSelect(tester);
    await tester.tap(_chip('Modern'));
    await tester.pump();
    await tester.tap(_chip('Living Room'));
    await tester.pump();
    await _closeQuickSelect(tester);
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
        'In stock. Self-collection at seller. Premium vinyl, waterproof.');
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

  testWidgets('Place queues a room-plan placement for the scanner to pick up',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      products: [_chatProduct()],
      replySuggestions: [
        {'productId': 'sofa-1', 'reason': 'Fits your space.'},
      ],
    );

    await _send(tester, 'Which sofa fits my room?');

    await tester.tap(find.widgetWithText(TextButton, 'Place'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(AiRecommendationScreen)));
    final pending = container.read(pendingChatPlacementsProvider);
    expect(pending, hasLength(1));
    expect(pending.single.name, 'Nordic Sofa');
    expect(pending.single.iconName, 'sofa');
    expect(pending.single.width, 180);
    expect(pending.single.height, 90);
    expect(find.text('Nordic Sofa added to your room plan'), findsOneWidget);

    // Draining hands the placement over exactly once.
    final drained =
        container.read(pendingChatPlacementsProvider.notifier).drain();
    expect(drained, hasLength(1));
    expect(container.read(pendingChatPlacementsProvider), isEmpty);
  });

  test('chatPlacementForProduct maps catalogue dims and falls back to catalog',
      () {
    final withDims = Product.fromJson({
      'id': 'sofa-2',
      'name': 'Deep Sofa',
      'price': 999,
      'stock': 1,
      'category': 'Sofa',
      'description': '',
      'image': '',
      'dimensions': {'widthM': 2.0, 'heightM': 0.5, 'depthM': 1.0},
    });
    final mapped = chatPlacementForProduct(withDims);
    expect(mapped.iconName, 'sofa');
    expect(mapped.width, 200);
    expect(mapped.height, 50);
    expect(mapped.name, 'Deep Sofa');
    expect(mapped.id, contains('sofa-2'));

    final noDims = Product.fromJson({
      'id': 'lamp-9',
      'name': 'Arc Lamp',
      'price': 120,
      'stock': 2,
      'category': 'Lighting',
      'description': '',
      'image': '',
    });
    final fallback = chatPlacementForProduct(noDims);
    expect(fallback.iconName, 'floor_lamp');
    expect(fallback.width, 25);
    expect(fallback.height, 25);
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
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture, fail: true);

    await _send(tester, 'Hello?');

    expect(find.text('The design assistant could not reply. Try again.'),
        findsOneWidget);
    final saved = await _savedMessages();
    expect(saved.last['text'],
        'The design assistant could not reply. Try again.');
    expect(capture.calls, 1);
  });

  testWidgets('cart and budget travel with the request as verified state',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      products: [_chatProduct()],
      cart: [CartItem(product: _chatProduct(), quantity: 2)],
      budget: BudgetPlan(
        budgetRm: 5000,
        room: 'Kitchen',
        ecoFriendly: false,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await _send(tester, 'Which sofa fits my room?');

    expect(capture.calls, 1);
    final state = capture.body!['state'] as Map<String, dynamic>;
    expect((state['cart'] as Map<String, dynamic>)['itemCount'], 2);
    expect((state['budget'] as Map<String, dynamic>)['capRm'], 5000);
  });

  testWidgets('an empty app state omits the state key', (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture);

    await _send(tester, 'Hello there');

    expect(capture.calls, 1);
    expect(capture.body!.containsKey('state'), isFalse);
  });

  testWidgets('pure state questions answer locally with a data card',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      cart: [CartItem(product: _chatProduct(), quantity: 1)],
      products: [_chatProduct()],
    );

    await _send(tester, "What's in my cart?");

    expect(capture.calls, 0);
    expect(find.text("Here's what's in your cart right now."), findsOneWidget);
    expect(find.byType(ChatDataCard), findsOneWidget);
  });

  testWidgets('a failed state question still shows the exact card',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(tester, capture, fail: true);

    await _send(tester, 'Can you list every single thing inside my cart today?');

    expect(capture.calls, 1);
    expect(find.text('The design assistant could not reply. Try again.'),
        findsOneWidget);
    expect(find.byType(ChatDataCard), findsOneWidget);
  });

  testWidgets('overflow menu saves and unsaves the suggestion',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      products: [_chatProduct()],
      signedIn: true,
      replySuggestions: [
        {'productId': 'sofa-1', 'reason': 'Matches your grey floor.'},
      ],
    );

    await _send(tester, 'Which sofa fits my room?');
    expect(find.byType(ChatSuggestionCard), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to wishlist'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(AiRecommendationScreen)));
    expect(container.read(wishlistProvider), contains('sofa-1'));
    expect(find.text('Nordic Sofa saved to your wishlist'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from wishlist'));
    await tester.pumpAndSettle();
    expect(container.read(wishlistProvider), isEmpty);
  });

  testWidgets('overflow menu edits the cart line', (tester) async {
    final capture = _ChatCapture();
    await _pumpScreen(
      tester,
      capture,
      products: [_chatProduct()],
      cart: [CartItem(product: _chatProduct(), quantity: 1)],
      signedIn: true,
      replySuggestions: [
        {'productId': 'sofa-1', 'reason': 'Fits your space.'},
      ],
    );

    await _send(tester, 'Which sofa fits my room?');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Increase quantity'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(AiRecommendationScreen)));
    expect(container.read(cartProvider).single.quantity, 2);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from cart'));
    await tester.pumpAndSettle();
    expect(container.read(cartProvider), isEmpty);
    expect(find.text('Nordic Sofa removed from cart'), findsOneWidget);
  });
}
