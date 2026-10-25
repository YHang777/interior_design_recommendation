import test from 'node:test';
import assert from 'node:assert/strict';
import { buildProductUpdateData, toProductDetail, toProductRow } from './products.service';

// ── toProductRow ─────────────────────────────────────────────────────────────

test('row → a full product doc maps every column', () => {
  const row = toProductRow('sofa-1', {
    name: 'Linen Sofa',
    category: 'Furniture',
    designStyle: 'Scandinavian',
    price: 899,
    originalPrice: 1099,
    stock: 12,
    isActive: true,
    isEcoFriendly: true,
    rating: 4.5,
    ratingCount: 20,
    supplierId: 'seller-1',
    supplierName: 'Nordic Home',
    supplier: { id: 'seller-1', name: 'Nordic Home', phone: '012', email: 'n@e', verificationStatus: 'verified' },
    image: 'https://cdn.example/sofa.jpg',
    createdAt: '2026-10-01T00:00:00.000Z',
  });

  assert.equal(row.productId, 'sofa-1');
  assert.equal(row.name, 'Linen Sofa');
  assert.equal(row.category, 'Furniture');
  assert.equal(row.designStyle, 'Scandinavian');
  assert.equal(row.price, 899);
  assert.equal(row.originalPrice, 1099);
  assert.equal(row.stock, 12);
  assert.equal(row.isActive, true);
  assert.equal(row.isEcoFriendly, true);
  assert.equal(row.rating, 4.5);
  assert.equal(row.ratingCount, 20);
  assert.equal(row.supplierId, 'seller-1');
  assert.equal(row.supplierName, 'Nordic Home');
  assert.equal(row.image, 'https://cdn.example/sofa.jpg');
  assert.equal(row.createdAt, '2026-10-01T00:00:00.000Z');
});

test('row → missing/wrong-typed fields coerce to safe defaults', () => {
  const row = toProductRow('legacy-1', {
    name: 42,
    category: { nested: true },
    price: 'free',
    stock: null,
    isActive: 'yes',
    originalPrice: '999',
    rating: '4.2',
    createdAt: 1712345678,
  });

  assert.equal(row.name, '');
  assert.equal(row.category, '');
  assert.equal(row.price, 0);
  assert.equal(row.stock, 0);
  // Anything but an explicit false counts as active (app default: true).
  assert.equal(row.isActive, true);
  assert.equal(row.originalPrice, null);
  assert.equal(row.rating, 0);
  assert.equal(row.createdAt, null);
});

test('row → isActive false is preserved (inactive listing)', () => {
  const row = toProductRow('off-1', { name: 'Old Lamp', isActive: false });
  assert.equal(row.isActive, false);
});

test('row → supplierId falls back to nested supplier.id for legacy docs', () => {
  const row = toProductRow('legacy-2', {
    name: 'Rug',
    supplier: { id: 'seller-9', name: 'Legacy Shop' },
  });
  assert.equal(row.supplierId, 'seller-9');
  assert.equal(row.supplierName, 'Legacy Shop');
});

// ── toProductDetail ──────────────────────────────────────────────────────────

test('detail → adds copy and read-only echoes', () => {
  const detail = toProductDetail('sofa-1', {
    name: 'Linen Sofa',
    description: 'Three-seater in oatmeal linen.',
    images: ['https://cdn.example/1.jpg', 'https://cdn.example/2.jpg', '', 42],
    ar3d: { status: 'ready', url: 'https://cdn.example/model.glb' },
    vision: { mismatch: { flagged: true, reason: 'photo shows a room' } },
    supplier: { id: 'seller-1', name: 'Nordic Home', phone: '012', email: 'n@e', verificationStatus: 'verified' },
  });

  assert.equal(detail.description, 'Three-seater in oatmeal linen.');
  assert.deepEqual(detail.images, ['https://cdn.example/1.jpg', 'https://cdn.example/2.jpg']);
  assert.equal(detail.ar3dStatus, 'ready');
  assert.equal(detail.visionFlagged, true);
  assert.equal(detail.supplierPhone, '012');
  assert.equal(detail.supplierEmail, 'n@e');
  assert.equal(detail.supplierVerificationStatus, 'verified');
});

test('detail → empty doc: ar3d none, images empty', () => {
  const detail = toProductDetail('empty-1', {});
  assert.equal(detail.description, '');
  assert.deepEqual(detail.images, []);
  assert.equal(detail.ar3dStatus, 'none');
  assert.equal(detail.visionFlagged, false);
});

// ── buildProductUpdateData ───────────────────────────────────────────────────

test('update data → only the 9 editable fields pass through', () => {
  const data = buildProductUpdateData({
    name: 'New Name',
    description: 'Updated copy.',
    category: 'Lighting',
    designStyle: 'Modern',
    price: 150,
    originalPrice: 200,
    stock: 8,
    isActive: false,
    isEcoFriendly: true,
  });

  assert.deepEqual(Object.keys(data).sort(), [
    'category',
    'description',
    'designStyle',
    'isActive',
    'isEcoFriendly',
    'name',
    'originalPrice',
    'price',
    'stock',
  ]);
});

test('update data → null originalPrice clears it; omitted fields stay out', () => {
  const clear = buildProductUpdateData({ originalPrice: null });
  assert.deepEqual(clear, { originalPrice: null });

  const partial = buildProductUpdateData({ price: 100 });
  assert.deepEqual(partial, { price: 100 });
});

test('update data → money and stock round to integers', () => {
  const data = buildProductUpdateData({ price: 99.6, stock: 3.4, originalPrice: 120.2 });
  assert.equal(data.price, 100);
  assert.equal(data.stock, 3);
  assert.equal(data.originalPrice, 120);
});
