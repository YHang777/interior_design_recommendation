import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/budget/data/budget_plan.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_proactive_chips.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

ProactiveInputs _inputs({
  int cartCount = 0,
  int cartSubtotal = 0,
  BudgetPlan? budget,
  int? estimateRm,
  RoomDesign? plan,
  int pendingPlacements = 0,
  String? latestOrderStatus,
  int wishlistCount = 0,
}) =>
    ProactiveInputs(
      cartCount: cartCount,
      cartSubtotal: cartSubtotal,
      budget: budget,
      estimateRm: estimateRm,
      plan: plan,
      pendingPlacements: pendingPlacements,
      latestOrderStatus: latestOrderStatus,
      wishlistCount: wishlistCount,
    );

RoomDesign _plan({List<FurniturePlacement> furniture = const []}) => RoomDesign(
      id: 'd1',
      name: 'Living Room A',
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      furniture: furniture,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      userId: 'u1',
    );

BudgetPlan _budget(int cap) => BudgetPlan(
      budgetRm: cap,
      room: 'Kitchen',
      ecoFriendly: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

List<String> _labels(List<ProactiveChip> chips) =>
    [for (final c in chips) c.label];

void main() {
  test('empty state still suggests setting a budget first', () {
    final chips = buildProactiveChips(_inputs());
    expect(_labels(chips).first, 'Set my budget');
    expect(chips.first.kind, ProactiveChipKind.action);
    expect(chips.first.path, '/budget');
  });

  test('pending placements outrank everything else', () {
    final chips = buildProactiveChips(_inputs(
      pendingPlacements: 2,
      cartCount: 3,
      wishlistCount: 5,
    ));
    expect(_labels(chips).first, 'Place pending items');
    expect(chips.first.kind, ProactiveChipKind.action);
    expect(chips.first.path, '/design');
  });

  test('over-budget branches on the estimate and on the cart subtotal', () {
    final byEstimate = buildProactiveChips(_inputs(
      budget: _budget(1000),
      estimateRm: 1500,
    ));
    expect(_labels(byEstimate), contains("I'm over budget"));

    final byCart = buildProactiveChips(_inputs(
      budget: _budget(1000),
      estimateRm: 100,
      cartSubtotal: 1200,
    ));
    expect(_labels(byCart), contains("I'm over budget"));

    final under = buildProactiveChips(_inputs(
      budget: _budget(5000),
      estimateRm: 1000,
    ));
    expect(_labels(under), contains('What else fits my budget?'));
  });

  test('an empty plan with cart items offers to plan the room', () {
    final chips = buildProactiveChips(_inputs(cartCount: 2, budget: _budget(9999)));
    expect(_labels(chips), contains('Plan my room with these'));
  });

  test('a plan without lighting asks for lighting in that room', () {
    final chips = buildProactiveChips(_inputs(
      budget: _budget(9999),
      plan: _plan(furniture: const [
        FurniturePlacement(
          id: 'f1',
          name: 'Sofa',
          iconName: 'sofa',
          x: 0,
          y: 0,
          width: 100,
          height: 50,
        ),
      ]),
    ));
    expect(_labels(chips), contains('Lighting for my living room'));

    final lit = buildProactiveChips(_inputs(
      budget: _budget(9999),
      plan: _plan(furniture: const [
        FurniturePlacement(
          id: 'f1',
          name: 'Arc Floor Lamp',
          iconName: 'floor_lamp',
          x: 0,
          y: 0,
          width: 25,
          height: 25,
        ),
      ]),
    ));
    expect(_labels(lit), isNot(contains('Lighting for my living room')));
  });

  test('orders awaiting collection surface an order-status chip', () {
    final chips = buildProactiveChips(_inputs(
      budget: _budget(9999),
      latestOrderStatus: 'waitingCollection',
    ));
    expect(_labels(chips), contains("Where's my order?"));

    final collected = buildProactiveChips(_inputs(
      budget: _budget(9999),
      latestOrderStatus: 'collected',
    ));
    expect(_labels(collected), isNot(contains("Where's my order?")));
  });

  test('three or more saved items offer a comparison', () {
    final chips = buildProactiveChips(_inputs(
      budget: _budget(9999),
      wishlistCount: 3,
    ));
    expect(_labels(chips), contains('Compare my saved items'));
  });

  test('caps at three chips and tops up with fillers', () {
    final chips = buildProactiveChips(
      _inputs(
        pendingPlacements: 1,
        cartCount: 2,
        budget: _budget(10),
        estimateRm: 999,
        wishlistCount: 9,
        latestOrderStatus: 'waitingCollection',
      ),
      fillers: const ['A filler', 'Another filler', 'Third filler'],
    );
    expect(chips, hasLength(3));
    expect(_labels(chips).first, 'Place pending items');
  });

  test('fillers skip labels that would duplicate a proactive chip', () {
    final chips = buildProactiveChips(
      _inputs(),
      fillers: const ['Set my budget', 'Fresh idea'],
    );
    expect(_labels(chips), ['Set my budget', 'Fresh idea']);
    expect(_labels(chips).where((l) => l == 'Set my budget'), hasLength(1));
  });

  test('fillers only appear when there is room', () {
    final chips = buildProactiveChips(
      _inputs(),
      fillers: const ['One', 'Two'],
    );
    expect(_labels(chips), ['Set my budget', 'One', 'Two']);
  });
}
