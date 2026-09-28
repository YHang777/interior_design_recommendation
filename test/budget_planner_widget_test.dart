// Widget harness for the BudgetPlannerScreen — proves the end-to-end flow
// (live estimates → typing saves → prefill guards → interactivity → real
// clipboard export) and encodes the failure modes the screen used to
// swallow silently:
//
//   * a failed budgetPlanProvider stream showed no error state at all,
//   * an empty / non-matching catalogue showed only faint dashes instead
//     of a loud, actionable banner,
//   * a failed catalogue stream was indistinguishable from "no data".
//
// All providers are overridden with real-shaped data; the repository is an
// in-memory fake that records saves and replays snapshots like Firestore
// would, so the real budgetPlanProvider wiring (uid → watchBudget) is
// exercised too.

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
import 'package:interior_design_recommendation/features/customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'package:interior_design_recommendation/models/product.dart';

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

/// Same categories as `assets/data/products.json` (Paint, Wall Covering,
/// Furniture, Lighting, Decor — and no Flooring, like the seed).
///
/// Expected medians: Wall Paint median(85, 95) = 90, Flooring — (no
/// listings), Furniture median(900, 1200) = 1050, Lighting 150,
/// Accessories (Decor) 250 → total 1540.
final List<Product> _seedCatalogue = [
  _p(category: 'Paint', price: 85),
  _p(category: 'Wall Covering', price: 95),
  _p(category: 'Furniture', price: 900),
  _p(category: 'Furniture', price: 1200),
  _p(category: 'Lighting', price: 150),
  _p(category: 'Decor', price: 250),
];

/// In-memory stand-in for BudgetRepository: replays the latest plan to the
/// first listener (like a Firestore snapshot) and pushes every save back
/// through the same stream, so round trips exercise the real
/// [budgetPlanProvider] wiring.
class _FakeBudgetRepository implements BudgetRepository {
  _FakeBudgetRepository({BudgetPlan? initial}) : _latest = initial;

  BudgetPlan? _latest;
  final _out = StreamController<BudgetPlan?>();

  /// Uid observed by watchBudget — proves the auth → repository wiring.
  String? watchedUid;

  /// Every save the screen made, in order.
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

  /// Simulates a snapshot arriving from elsewhere (e.g. another device).
  void push(BudgetPlan? plan) {
    _latest = plan;
    if (!_out.isClosed) _out.add(plan);
  }

  void dispose() {
    if (!_out.isClosed) _out.close();
  }
}

Future<void> _pumpPlanner(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  // Tall surface so every section is on-screen (no scroll needed to tap).
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user()),
        ...overrides,
      ],
      child: const MaterialApp(home: BudgetPlannerScreen()),
    ),
  );
  // Let the async streams deliver their first snapshots.
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
      'renders real catalogue estimates (median per category) — not '
      'dashes, not fakes', (tester) async {
    await _pumpPlanner(tester, overrides: [
      budgetPlanProvider.overrideWith((ref) => Stream<BudgetPlan?>.value(null)),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    // Every line the seed catalogue can price.
    expect(find.text('RM 90'), findsOneWidget); // Wall Paint median(85, 95)
    expect(find.text('RM 1,050'), findsOneWidget); // Furniture median(900,1200)
    expect(find.text('RM 150'), findsOneWidget); // Lighting
    expect(find.text('RM 250'), findsOneWidget); // Accessories (Decor)
    // Flooring has no listings in the seed → honest dash, never a 0-quote.
    expect(find.text('—'), findsOneWidget);

    // Total of priced lines = 90 + 1050 + 150 + 250 = 1540. It appears
    // three times, all legitimately: the Total Cost card, the breakdown
    // total, and the remaining amount of the (still empty) RM 0 budget
    // (0 − 1540 → "Over Budget RM 1,540").
    expect(find.text('RM 1,540'), findsNWidgets(3));
    expect(find.text('Over Budget'), findsOneWidget);
    expect(
      find.text('Total covers categories with price data only.'),
      findsOneWidget,
    );

    // Budget starts empty — no fabricated default like the old '5000'.
    expect(_fieldBudget(tester), 0);
    expect(find.text('RM 0'), findsOneWidget); // Total Budget card
    expect(find.text('Plan your Kitchen renovation'), findsOneWidget);
  });

  testWidgets('typing a budget saves it through the real provider chain '
      'and recomputes remaining', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    // budgetPlanProvider is NOT overridden: the real provider must wire
    // currentUserProvider → fake.watchBudget.
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
    expect(fake.saves.single.ecoFriendly, isFalse);

    expect(find.text('RM 5,000'), findsOneWidget); // Total Budget card
    expect(find.text('RM 3,460'), findsOneWidget); // 5000 − 1540
    expect(find.text('Remaining'), findsOneWidget);
  });

  testWidgets('a stored plan prefills budget, room and heading on return',
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

    expect(find.text('7000'), findsOneWidget); // the field itself
    expect(_fieldBudget(tester), 7000);
    expect(find.text('Bedroom'), findsOneWidget); // dropdown value
    expect(find.text('Plan your Bedroom renovation'), findsOneWidget);
    expect(find.text('RM 7,000'), findsOneWidget); // Total Budget card
    expect(find.text('RM 5,460'), findsOneWidget); // 7000 − 1540
    expect(fake.watchedUid, 'u1');
    // Reading must never write: no save is fired by loading a plan.
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

    // User replaces the stored value…
    await tester.enterText(find.byType(TextFormField), '1234');
    await tester.pump();
    expect(fake.saves.single.budgetRm, 1234);

    // …and only then does another snapshot (another device: 9999) land.
    fake.push(BudgetPlan(
      budgetRm: 9999,
      room: 'Kitchen',
      ecoFriendly: false,
      updatedAt: DateTime.utc(2026, 9, 28, 12),
    ));
    await tester.pump();

    // The in-progress edit wins; the screen does not jump back to 9999.
    expect(_fieldBudget(tester), 1234);
    expect(find.text('RM 1,234'), findsOneWidget);
    expect(find.text('RM 9,999'), findsNothing);
  });

  testWidgets('room dropdown change persists and updates the heading',
      (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    await _pumpPlanner(tester, overrides: [
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living Room').last);
    await tester.pumpAndSettle();

    expect(find.text('Plan your Living Room renovation'), findsOneWidget);
    expect(fake.saves, isNotEmpty);
    expect(fake.saves.last.room, 'Living Room');
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

    // Eco off: median over both furniture listings = 1050.
    expect(find.text('RM 1,050'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    // Eco on: only the eco listing prices → 1200; 1050 must be gone.
    // 'RM 1,200' ×4: Furniture line, breakdown total, Total Cost card and
    // Over Budget remainder (budget still 0) — no stale 1050 anywhere.
    expect(find.text('RM 1,200'), findsNWidgets(4));
    expect(find.text('RM 1,050'), findsNothing);
    expect(
      find.text('Estimating from eco-friendly listings only'),
      findsOneWidget,
    );
    expect(fake.saves, isNotEmpty);
    expect(fake.saves.last.ecoFriendly, isTrue);
  });

  testWidgets('Copy Report puts the real summary on the clipboard and '
      'says so truthfully', (tester) async {
    final fake = _FakeBudgetRepository();
    addTearDown(fake.dispose);

    final log = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      log.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpPlanner(tester, overrides: [
      budgetRepositoryProvider.overrideWithValue(fake),
      marketplaceProductsProvider
          .overrideWith((ref) => Stream.value(_seedCatalogue)),
    ]);

    await tester.enterText(find.byType(TextFormField), '5000');
    await tester.pump();

    // Tap the label itself: ElevatedButton.icon builds a private
    // _ElevatedButtonWithIcon subclass, which find.byType(ElevatedButton)
    // (exact runtimeType match) would miss.
    await tester.tap(find.text('Copy Report'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final setData = log.where((c) => c.method == 'Clipboard.setData');
    expect(setData, hasLength(1));
    final args = setData.single.arguments! as Map;
    final report = args['text'] as String;

    expect(report, contains('Kitchen'));
    expect(report, contains('Budget: RM 5,000'));
    expect(report, contains('Wall Paint: RM 90'));
    expect(report, contains('Furniture: RM 1,050'));
    expect(report, contains('Total estimate: RM 1,540'));
    expect(report, contains('Remaining: RM 3,460'));
    expect(report, isNot(contains('mocked')));

    expect(
      find.text('Budget report copied to clipboard'),
      findsOneWidget,
    );
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

    // The estimates still render — one failed stream must not blank the page.
    expect(find.text('RM 90'), findsOneWidget);
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
    // All five lines are honest dashes underneath the banner.
    expect(find.text('—'), findsNWidgets(budgetLineLabels.length));
    // 'RM 0' ×4: Total Budget, Total Cost, breakdown Total, Remaining —
    // every figure honestly zero, none fabricated.
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
    // Never a fabricated number while the load has failed — 'RM 0' ×4
    // (Total Budget, Total Cost, breakdown Total, Remaining).
    expect(find.text('RM 0'), findsNWidgets(4));
  });
}
