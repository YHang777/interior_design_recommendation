import test from 'node:test';
import assert from 'node:assert/strict';
import { computeTotals, tierForOrderCount } from './checkout.service';

// ── computeTotals (mirrors the app's pricing.dart breakdown) ────────────────

test('totals → no discount, 6% tax', () => {
  assert.deepEqual(computeTotals(1000, 0, 0.06), {
    subtotal: 1000,
    discount: 0,
    tax: 60,
    total: 1060,
  });
});

test('totals → 5% Silver discount, tax on the chargeable amount', () => {
  assert.deepEqual(computeTotals(1000, 5, 0.06), {
    subtotal: 1000,
    discount: 50,
    tax: 57,
    total: 1007,
  });
});

test('totals → 10% Gold discount', () => {
  assert.deepEqual(computeTotals(2000, 10, 0.06), {
    subtotal: 2000,
    discount: 200,
    tax: 108,
    total: 1908,
  });
});

test('totals → rounding: discount and tax both round half up', () => {
  // 999 * 5% = 49.95 → 50; chargeable 949; tax 56.94 → 57; total 1006.
  assert.deepEqual(computeTotals(999, 5, 0.06), {
    subtotal: 999,
    discount: 50,
    tax: 57,
    total: 1006,
  });
});

test('totals → zero tax rate', () => {
  assert.deepEqual(computeTotals(500, 0, 0), {
    subtotal: 500,
    discount: 0,
    tax: 0,
    total: 500,
  });
});

test('totals → free cart stays zero', () => {
  assert.deepEqual(computeTotals(0, 0, 0.06), {
    subtotal: 0,
    discount: 0,
    tax: 0,
    total: 0,
  });
});

// ── tierForOrderCount (mirrors AppConfigData.membershipTiers) ────────────────

test('tier → 0 collected orders is Free', () => {
  assert.deepEqual(tierForOrderCount(0), { name: 'Free', discountPercent: 0 });
});

test('tier → 4 collected orders is still Free (Silver starts at 5)', () => {
  assert.deepEqual(tierForOrderCount(4), { name: 'Free', discountPercent: 0 });
});

test('tier → 5 collected orders is Silver', () => {
  assert.deepEqual(tierForOrderCount(5), { name: 'Silver', discountPercent: 5 });
});

test('tier → 14 collected orders is still Silver (Gold starts at 15)', () => {
  assert.deepEqual(tierForOrderCount(14), { name: 'Silver', discountPercent: 5 });
});

test('tier → 15 collected orders is Gold', () => {
  assert.deepEqual(tierForOrderCount(15), { name: 'Gold', discountPercent: 10 });
});

test('tier → 100 collected orders stays Gold', () => {
  assert.deepEqual(tierForOrderCount(100), { name: 'Gold', discountPercent: 10 });
});
