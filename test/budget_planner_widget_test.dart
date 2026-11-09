import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_estimates.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_providers.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_repository.dart';
import 'package:interior_design_recommendation/features/customer/budget/presentation/screens/budget_planner_screen.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

AppUser _user() => AppUser(
      uid: 'u1',
      email: 'aina@example.com',
      name: 'Aina',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Product _p({
  required String category,
  required int price,
  bool isActive = true,
  bool isEcoFriendly = false,
}) {
  return Product(
    id: 'p-$category-$price',
    name: '$category $price',
    price: price,
    stock: 10,
    image: '',
    description: '',
    designStyle: 'Modern',
    category: category,
    supplier: const Supplier(
      id: 's1',
      name: 'Seller',
      phone: '',
      address: '',
      email: '',
    ),
    isActive: isActive,
    isEcoFriendly: isEcoFriendly,
  );
}

final List<Product> _seedCatalogue = [
  _p(category: 'Paint', price: 85),
  _p(category: 'Wall Covering', price: 95),
  _p(category: 'Furniture', price: 900),
  _p(category: 'Furniture', price: 1200),
  _p(category: 'Lighting', price: 150),
  _p(category: 'Decor', price: 250),
];

class _FakeBudgetRepository implements BudgetRepository {
  _FakeBudgetRepository({BudgetPlan? initial}) : _latest = initial;

  BudgetPlan? _latest;
  final _out = StreamController<BudgetPlan?>.broadcast();

  String? watchedUid;

  final saves = <BudgetPlan>[];

  @override
  Stream<BudgetPlan?> watchBudget(String uid) async* {
    watchedUid = uid;
    yield _latest;
    yield* _out.stream;
  }

  @override
  Future<void> saveBudget(String uid, BudgetPlan plan) async {
    saves.add(plan);
    push(plan);
  }

  void push(BudgetPlan? plan) {
    _latest = plan;
    if (!_out.isClosed) _out.add(plan);
  }

  void dispose() {
    if (!_out.isClosed) _out.close();
  }
}

RoomDesign _design({String id = 'design-1', String name = 'Bedroom Reno'}) =>
    RoomDesign(
      id: id,
      name: name,
      roomType: 'bedroom',
      widthCm: 400,
      heightCm: 500,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      userId: 'u1',
    );

Future<void> _pumpPlanner(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<RoomDesign> designs = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user()),
        // The real designs provider polls Supabase with Stream.periodic —
        // pending timers would fail every test here.
        savedDesignsProvider
            .overrideWith((ref) => Stream.value(designs)),
        ...overrides,
      ],
      child: const MaterialApp(home: BudgetPlannerScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

int _fieldBudget(WidgetTester tester) {
  final field = tester.widget<TextFormField>(find.byType(TextFormField));
  return int.tryParse(
        field.controller!.text.replaceAll(RegExp('[^0-9]'), ''),
      ) ??
      0;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets(
      'renders real catalogue estimates (lowest price per category) — not '
      'dashes, not fakes', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    expect(find.text('RM 85'), findsOneWidget);
    expect(find.text('RM 900'), findsOneWidget);
    expect(find.text('RM 150'), findsOneWidget);
    expect(find.text('RM 250'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);

    expect(find.text('RM 1,385'), findsNWidgets(3));
    expect(find.text('Over Budget'), findsOneWidget);
    expect(
      find.text('Total covers categories with price data only.'),
      findsOneWidget,
    );

    expect(_fieldBudget(tester), 0);
    expect(find.text('RM 0'), findsOneWidget);
    expect(find.text('Plan your total budget'), findsOneWidget);
    expect(find.text('Whole home (total budget)'), findsOneWidget);
  });

  testWidgets('typing a budget saves it through the real provider chain '
      'and recomputes remaining', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    await _pumpPlanner(tester, overrides: [
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    expect(fake.watchedUid, 'u1');

    await tester.enterText(find.byType(TextFormField), '5,000');
    await tester.pump();

    expect(fake.saves, hasLength(1));
    expect(fake.saves.single.budgetRm, 5000);
    expect(fake.saves.single.room, defaultBudgetRoom);
    expect(fake.saves.single.designId, '');
    expect(fake.saves.single.ecoFriendly, isFalse);

    expect(find.text('RM 5,000'), findsOneWidget);
    expect(find.text('RM 3,615'), findsOneWidget);
    expect(find.text('Remaining'), findsOneWidget);
  });

  testWidgets('a stored design-scoped plan prefills budget, design and '
      'heading on return', (tester) async {
    final fake = _FakeBudgetRepository(
      initial: BudgetPlan(
        budgetRm: 7000,
        room: 'Bedroom Reno',
        ecoFriendly: false,
        updatedAt: DateTime.utc(2026, 9, 28),
        designId: 'design-1',
      ),
    );
    addTearDown(fake.dispose);

    await _pumpPlanner(
      tester,
      overrides: [
        budgetRepositoryProvider.overrideWithValue(fake),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(_seedCatalogue)),
      ],
      designs: [_design()],
    );

    expect(find.text('7000'), findsOneWidget);
    expect(_fieldBudget(tester), 7000);
    expect(find.text('Bedroom Reno'), findsOneWidget);
    expect(find.text('Budget for Bedroom Reno'), findsOneWidget);
    expect(find.text('RM 7,000'), findsOneWidget);
    expect(find.text('RM 5,615'), findsOneWidget);
    expect(fake.watchedUid, 'u1');
    expect(fake.saves, isEmpty);
  });

  testWidgets('a late snapshot never clobbers what the user typed',
      (tester) async {
    final fake = _FakeBudgetRepository(
      initial: BudgetPlan(
        budgetRm: 7000,
        room: 'Bedroom',
        ecoFriendly: false,
        updatedAt: DateTime.utc(2026, 9, 28),
      ),
    );
    addTearDown(fake.dispose);

    await _pumpPlanner(tester, overrides: [
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);
    expect(find.text('7000'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '1234');
    await tester.pump();
    expect(fake.saves.single.budgetRm, 1234);

    fake.push(BudgetPlan(
      budgetRm: 9999,
      room: 'Kitchen',
      ecoFriendly: false,
      updatedAt: DateTime.utc(2026, 9, 28, 12),
    ));
    await tester.pump();

    expect(_fieldBudget(tester), 1234);
    expect(find.text('RM 1,234'), findsOneWidget);
    expect(find.text('RM 9,999'), findsNothing);
  });

  testWidgets('design selector persists the chosen design and updates the '
      'heading', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    await _pumpPlanner(
      tester,
      overrides: [
        budgetRepositoryProvider.overrideWithValue(fake),
        marketplaceProductsProvider
            .overrideWith((ref) => Stream.value(_seedCatalogue)),
      ],
      designs: [_design(id: 'design-7', name: 'Kitchen Refresh')],
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen Refresh').last);
    await tester.pumpAndSettle();

    expect(find.text('Budget for Kitchen Refresh'), findsOneWidget);
    expect(fake.saves, isNotEmpty);
    expect(fake.saves.last.designId, 'design-7');
    expect(fake.saves.last.room, 'Kitchen Refresh');

    // Back to the whole-home total.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole home (total budget)').last);
    await tester.pumpAndSettle();

    expect(find.text('Plan your total budget'), findsOneWidget);
    expect(fake.saves.last.designId, '');
    expect(fake.saves.last.room, defaultBudgetRoom);
  });

  testWidgets('eco toggle recomputes estimates from eco listings only '
      'and persists the preference', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    await _pumpPlanner(tester, overrides: [
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider.overrideWith((ref) => Stream.value([
        _p(category: 'Paint', price: 85),
        _p(category: 'Furniture', price: 900),
        _p(category: 'Furniture', price: 1200, isEcoFriendly: true),
      ])),
    ]);

    expect(find.text('RM 900'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    expect(find.text('RM 1,200'), findsNWidgets(4));
    expect(find.text('RM 900'), findsNothing);
    expect(
      find.text('Estimating from eco-friendly listings only'),
      findsOneWidget,
    );
    expect(fake.saves, isNotEmpty);
    expect(fake.saves.last.ecoFriendly, isTrue);
  });

  testWidgets('the export action bar hands a real PDF to the OS share '
      'sheet — no clipboard copy', (tester) async {
    final log = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const printingChannel = MethodChannel('net.nfet.printing');
    messenger.setMockMethodCallHandler(printingChannel, (call) async {
      log.add(call);
      return 1;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(printingChannel, null));

    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider
          .overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    expect(find.text('Share Report'), findsOneWidget);
    expect(find.text('Print Report'), findsOneWidget);
    expect(find.text('Copy Report'), findsNothing);

    await tester.tap(find.text('Share Report'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final shares = log.where((c) => c.method == 'sharePdf');
    expect(shares, hasLength(1));
    final args = shares.single.arguments! as Map;
    expect(args['name'], matches(RegExp(r'^budget-report-.+\.pdf$')));
    final doc = args['doc'] as List<int>;
    expect(String.fromCharCodes(doc.take(5)), '%PDF-');

    expect(find.text('Report PDF ready to share'), findsOneWidget);
  });

  // ── Failure states the screen used to swallow ──────────────────────────────

  testWidgets('DEFECT: a failed budget stream shows a visible error with '
      'retry, not silent empty defaults', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith(
          (ref) => Stream<BudgetPlan?>.error(Exception('permission denied'))),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    expect(find.text('Could not load your saved budget'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    expect(find.text('RM 85'), findsOneWidget);
  });

  testWidgets('DEFECT: an empty catalogue shows a loud, helpful banner '
      'instead of only faint dashes', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(const <Product>[])),
    ]);

    expect(
      find.text('Estimates need products in these categories'),
      findsOneWidget,
    );
    expect(find.textContaining('no active products'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(budgetLineLabels.length));
    expect(find.text('RM 0'), findsNWidgets(4));
  });

  testWidgets('DEFECT: a failed catalogue stream is announced, not '
      'silently rendered as “no data”', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider.overrideWith(
          (ref) => Stream<List<Product>>.error(Exception('offline'))),
    ]);

    expect(find.text('Could not load product prices'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('RM 0'), findsNWidgets(4));
  });

  // ── Material comparison (supplier, range, swap sheet, custom badge) ──────

  testWidgets('breakdown rows show supplier, price range and the '
      'lowest-price footnote', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    expect(find.text('Seller · RM 85'), findsOneWidget);
    expect(find.text('RM 85 – RM 95 · 2 listings'), findsOneWidget);
    expect(find.text('RM 150 · 1 listing'), findsOneWidget);
    expect(find.text('above lowest'), findsNothing);
    expect(
      find.text(
          'Lowest price across 6 active listings · tap a row to compare '
          'materials'),
      findsOneWidget,
    );
  });

  testWidgets('picking a pricier material updates the total, badges the row '
      'and the choice survives a reload', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);
    final overrides = <Override>[
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ];

    await _pumpPlanner(tester, overrides: overrides);
    expect(find.text('above lowest'), findsNothing);

    await tester.ensureVisible(find.text('Furniture'));
    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Furniture material'), findsOneWidget);
    expect(find.text('Seller'), findsWidgets);
    expect(find.text('Out of stock'), findsNothing);

    await tester.tap(find.text('Furniture 1200'));
    await tester.pumpAndSettle();

    expect(find.text('Furniture 1200'), findsOneWidget);
    expect(find.text('above lowest'), findsOneWidget);
    expect(find.text('RM 1,685'), findsNWidgets(3));
    expect(fake.saves, isNotEmpty);
    expect(fake.saves.last.choices['Furniture'], 'p-Furniture-1200');

    await _pumpPlanner(tester, overrides: overrides);

    expect(find.text('Furniture 1200'), findsOneWidget);
    expect(find.text('above lowest'), findsOneWidget);
    expect(find.text('RM 1,685'), findsNWidgets(3));
    expect(find.text('RM 1,385'), findsNothing);
  });
}
