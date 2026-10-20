import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/chat_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/widgets/chat_data_card.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/widgets/robot_assistant/robot_assistant_host.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/widgets/robot_assistant/robot_chat_panel.dart';
import 'package:interior_design_recommendation/models/cart_item.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reply = 'Yes — 4 left, free delivery.';

class _ChatCapture {
  int calls = 0;
  Map<String, dynamic>? body;
}

MockClient _client(_ChatCapture capture, {int status = 200}) =>
    MockClient((request) async {
      capture.calls++;
      capture.body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        status == 200
            ? jsonEncode({'reply': _reply})
            : '{"error":{"code":"UPSTREAM"}}',
        status,
        headers: {'content-type': 'application/json'},
      );
    });

Product _product() => Product.fromJson({
      'id': 'sofa-1',
      'name': 'Nordic Sofa',
      'price': 1299,
      'stock': 4,
      'category': 'Sofa',
      'designStyle': 'Scandinavian',
      'description': 'Oatmeal boucle three-seater.',
      'image': '',
    });

class _StaticCart extends CartNotifier {
  _StaticCart(this.items);
  final List<CartItem> items;

  @override
  List<CartItem> build() => items;
}

Future<void> _pumpHost(
  WidgetTester tester,
  _ChatCapture capture, {
  Product? focusProduct,
  int status = 200,
  List<CartItem> cart = const [],
  BudgetPlan? budget,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final product = _product();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatDatasourceProvider.overrideWithValue(
          ChatDatasource(
            client: _client(capture, status: status),
            idTokenProvider: () async => 'tok-123',
          ),
        ),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value([product])),
        currentUserProvider.overrideWithValue(null),
        if (cart.isNotEmpty) cartProvider.overrideWith(() => _StaticCart(cart)),
        if (budget != null)
          budgetPlanProvider.overrideWith((ref) => Stream.value(budget)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: RobotAssistantHost(
                products: focusProduct != null ? [focusProduct] : [product],
                focusProduct: focusProduct,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _robot() => find.byKey(const ValueKey('robot-assistant'));

Future<void> _openChat(WidgetTester tester) async {
  await tester.tap(_robot());
  await tester.pumpAndSettle();
}

String _inputText(WidgetTester tester) =>
    tester
        .widget<TextField>(find.byKey(const ValueKey('robot-chat-input')))
        .controller!
        .text;

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('robot-chat-input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('robot-chat-send')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('drag repositions the robot without opening the chat or '
      'sending', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);

    final start = tester.getCenter(_robot());
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-80, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(-80, 50));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final end = tester.getCenter(_robot());
    expect(end.dx, lessThan(start.dx - 40));
    expect(end.dy, greaterThan(start.dy + 20));
    expect(find.byType(RobotChatPanel), findsNothing);
    expect(capture.calls, 0);
  });

  testWidgets('tap opens the panel with the listing framing', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);

    await _openChat(tester);

    expect(find.byType(RobotChatPanel), findsOneWidget);
    expect(find.text('Shopping assistant'), findsOneWidget);
    expect(find.text('Ask me anything about these products.'), findsOneWidget);
    expect(find.byKey(const ValueKey('robot-chat-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('robot-chat-send')), findsOneWidget);
    expect(capture.calls, 0);
  });

  testWidgets('the robot clamps to the host bounds', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);

    var gesture = await tester.startGesture(tester.getCenter(_robot()));
    await gesture.moveBy(const Offset(-800, -800));
    await tester.pump();
    await gesture.moveBy(const Offset(-800, -800));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final topLeft = tester.getCenter(_robot());
    expect(topLeft.dx, inInclusiveRange(43, 45));
    expect(topLeft.dy, inInclusiveRange(43, 45));

    gesture = await tester.startGesture(topLeft);
    await gesture.moveBy(const Offset(800, 800));
    await tester.pump();
    await gesture.moveBy(const Offset(800, 800));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final bottomRight = tester.getCenter(_robot());
    expect(bottomRight.dx, inInclusiveRange(348, 350));
    expect(bottomRight.dy, inInclusiveRange(807, 809));
  });

  testWidgets('chips fill the input and never auto-send', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);

    await tester.enterText(
        find.byKey(const ValueKey('robot-chat-input')), 'half-typed draft');
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, kFitHomeQuestion));
    await tester.pump();

    expect(_inputText(tester), kFitHomeQuestion);
    expect(capture.calls, 0);
  });

  testWidgets('a question ships the product context and shows the reply',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);

    await _send(tester, 'Is the sofa in stock?');

    expect(find.text('Is the sofa in stock?'), findsOneWidget);
    expect(find.text(_reply), findsOneWidget);
    expect(capture.calls, 1);

    final body = capture.body!;
    expect(body.containsKey('style'), isFalse);
    expect(body.containsKey('room'), isFalse);

    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.last['role'], 'user');
    expect(messages.last['text'], 'Is the sofa in stock?');

    final products = (body['products'] as List).cast<Map<String, dynamic>>();
    expect(products, hasLength(1));
    expect(products.single['id'], 'sofa-1');
    expect(
        products.single['description'], startsWith('Only 4 left. Free delivery.'));
  });

  testWidgets('a failed request lands as a friendly bubble', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture, status: 500);
    await _openChat(tester);

    await _send(tester, 'Is the sofa in stock?');

    expect(
        find.text('The design assistant could not reply. Try again.'),
        findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('500'), findsNothing);
    expect(find.text(_reply), findsNothing);
  });

  testWidgets('detail framing: title, focus banner, and detail chips',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture, focusProduct: _product());
    await _openChat(tester);

    expect(find.text('Ask about this product'), findsOneWidget);
    expect(find.text('Nordic Sofa'), findsOneWidget);
    expect(find.text('RM 1,299'), findsOneWidget);
    expect(find.text('Ask me anything about this product.'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, kFitHomeQuestion), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Is it in stock?'), findsOneWidget);
  });

  testWidgets('closing and reopening the sheet keeps the transcript',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);
    await _send(tester, 'Is the sofa in stock?');
    expect(find.text(_reply), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(RobotChatPanel), findsNothing);

    await _openChat(tester);
    expect(find.text('Is the sofa in stock?'), findsOneWidget);
    expect(find.text(_reply), findsOneWidget);
    expect(capture.calls, 1);
  });

  testWidgets('the buyer saved household design rides along with the request',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_chat_history': jsonEncode([
        {
          'id': 'sess-1',
          'title': 'Living room ideas',
          'messages': <Map<String, dynamic>>[],
          'style': 'Scandinavian',
          'room': 'Living Room',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
      ]),
      'ai_chat_active_session_id': 'sess-1',
    });
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);

    await _send(tester, kFitHomeQuestion);

    expect(capture.calls, 1);
    final body = capture.body!;
    expect(body['style'], 'Scandinavian');
    expect(body['room'], 'Living Room');
  });

  testWidgets('an empty app state sends no state block', (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);

    await _send(tester, 'Is the sofa in stock?');

    expect(capture.calls, 1);
    expect(capture.body!.containsKey('state'), isFalse);
  });

  testWidgets('live cart and budget ride along as verified state',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(
      tester,
      capture,
      cart: [
        CartItem(product: _product(), quantity: 2),
      ],
      budget: BudgetPlan(
        budgetRm: 5000,
        room: 'Kitchen',
        ecoFriendly: true,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await _openChat(tester);

    await _send(tester, 'Is the sofa in stock?');

    expect(capture.calls, 1);
    final state = capture.body!['state'] as Map<String, dynamic>;
    final cart = state['cart'] as Map<String, dynamic>;
    expect(cart['itemCount'], 2);
    final items = (cart['items'] as List).cast<Map<String, dynamic>>();
    expect(items.single['name'], 'Nordic Sofa');
    final budget = state['budget'] as Map<String, dynamic>;
    expect(budget['capRm'], 5000);
    expect(budget['ecoFriendly'], isTrue);
  });

  testWidgets('a pure state question answers instantly with a data card',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture);
    await _openChat(tester);

    await _send(tester, "What's in my cart?");

    expect(capture.calls, 0);
    expect(find.text("Here's what's in your cart right now."), findsOneWidget);
    expect(find.byType(ChatDataCard), findsOneWidget);
  });

  testWidgets('the state card still lands when the proxy is down',
      (tester) async {
    final capture = _ChatCapture();
    await _pumpHost(tester, capture, status: 500);
    await _openChat(tester);

    await _send(tester, 'Can you list every single thing inside my cart today?');

    expect(capture.calls, 1);
    expect(find.text('The design assistant could not reply. Try again.'),
        findsOneWidget);
    expect(find.byType(ChatDataCard), findsOneWidget);
  });
}
