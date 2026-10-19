import type { RequestHandler } from 'express';
import { fbDb } from '../config/firebase';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import type {
  AdminProductDetail,
  AdminProductRow,
  DeleteProductResult,
  ListProductsQuery,
  ListProductsResult,
  ProductUpdate,
} from '../types/models';

export interface ProductsDeps {
  list: (query: ListProductsQuery) => Promise<ListProductsResult>;
  get: (productId: string) => Promise<AdminProductDetail>;
  update: (productId: string, patch: ProductUpdate) => Promise<AdminProductDetail>;
  remove: (productId: string) => Promise<DeleteProductResult>;
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultProductsDeps(): ProductsDeps {
  return {
    list: (query) => listProducts(query),
    get: (productId) => getProductDetail(productId),
    update: (productId, patch) => updateProduct(productId, patch),
    remove: (productId) => deleteProduct(productId),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

function toIso(value: unknown): string | null {
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'string' && value) return value;
  return null;
}

function asRecord(data: Record<string, unknown> | undefined): Record<string, unknown> {
  return data ?? {};
}

function nestedString(data: Record<string, unknown>, key: string): string {
  const v = data[key];
  return typeof v === 'string' ? v : '';
}

function nestedNumber(data: Record<string, unknown>, key: string): number {
  const v = data[key];
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

/** products/{id} → list row (defensive coercion; legacy docs become empty). */
export function toProductRow(productId: string, raw: Record<string, unknown>): AdminProductRow {
  const data = asRecord(raw);
  const supplier = (data.supplier ?? {}) as Record<string, unknown>;
  const original = data.originalPrice;
  return {
    productId,
    name: nestedString(data, 'name'),
    category: nestedString(data, 'category'),
    designStyle: nestedString(data, 'designStyle'),
    price: Math.round(nestedNumber(data, 'price')),
    originalPrice: typeof original === 'number' && Number.isFinite(original) ? Math.round(original) : null,
    stock: Math.round(nestedNumber(data, 'stock')),
    isActive: data.isActive !== false,
    isEcoFriendly: data.isEcoFriendly === true,
    rating: nestedNumber(data, 'rating'),
    ratingCount: Math.round(nestedNumber(data, 'ratingCount')),
    supplierId: nestedString(data, 'supplierId') || nestedString(supplier, 'id'),
    supplierName: nestedString(supplier, 'name') || nestedString(data, 'supplierName'),
    image: nestedString(data, 'image'),
    createdAt: toIso(data.createdAt),
  };
}

/** products/{id} → detail row (list fields + copy, shipping, read-only echoes). */
export function toProductDetail(
  productId: string,
  raw: Record<string, unknown>
): AdminProductDetail {
  const data = asRecord(raw);
  const supplier = (data.supplier ?? {}) as Record<string, unknown>;
  const vision = (data.vision ?? {}) as Record<string, unknown>;
  const mismatch = (vision.mismatch ?? {}) as Record<string, unknown>;
  const ar3d = (data.ar3d ?? {}) as Record<string, unknown>;
  const images = Array.isArray(data.images)
    ? (data.images as unknown[]).filter((i): i is string => typeof i === 'string' && i.length > 0)
    : [];
  return {
    ...toProductRow(productId, data),
    description: nestedString(data, 'description'),
    images,
    shippingEnabled: data.shippingEnabled === true,
    shippingFee: Math.max(0, Math.round(nestedNumber(data, 'shippingFee'))),
    shippingLongDistanceNotice: data.shippingLongDistanceNotice === true,
    ar3dStatus: nestedString(ar3d, 'status') || 'none',
    visionFlagged: mismatch.flagged === true,
    supplierPhone: nestedString(supplier, 'phone') || nestedString(data, 'supplierPhone'),
    supplierEmail: nestedString(supplier, 'email') || nestedString(data, 'supplierEmail'),
    supplierVerificationStatus: nestedString(supplier, 'verificationStatus'),
  };
}

/** Only the 12 editable fields ever reach Firestore — field-level update. */
export function buildProductUpdateData(patch: ProductUpdate): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (typeof patch.name === 'string') out.name = patch.name;
  if (typeof patch.description === 'string') out.description = patch.description;
  if (typeof patch.category === 'string') out.category = patch.category;
  if (typeof patch.designStyle === 'string') out.designStyle = patch.designStyle;
  if (typeof patch.price === 'number') out.price = Math.round(patch.price);
  if (patch.originalPrice === null) out.originalPrice = null;
  else if (typeof patch.originalPrice === 'number') out.originalPrice = Math.round(patch.originalPrice);
  if (typeof patch.stock === 'number') out.stock = Math.round(patch.stock);
  if (typeof patch.isActive === 'boolean') out.isActive = patch.isActive;
  if (typeof patch.isEcoFriendly === 'boolean') out.isEcoFriendly = patch.isEcoFriendly;
  if (typeof patch.shippingEnabled === 'boolean') out.shippingEnabled = patch.shippingEnabled;
  if (typeof patch.shippingFee === 'number') out.shippingFee = Math.max(0, Math.round(patch.shippingFee));
  if (typeof patch.shippingLongDistanceNotice === 'boolean') {
    out.shippingLongDistanceNotice = patch.shippingLongDistanceNotice;
  }
  return out;
}

export async function listProducts(query: ListProductsQuery): Promise<ListProductsResult> {
  const snap = await fbDb().collection('products').get();
  let rows = snap.docs.map((doc) => toProductRow(doc.id, doc.data()));

  const q = (query.q ?? '').trim().toLowerCase();
  if (q) {
    rows = rows.filter(
      (r) =>
        r.name.toLowerCase().includes(q) ||
        r.supplierName.toLowerCase().includes(q) ||
        r.productId.toLowerCase().includes(q)
    );
  }
  if (query.category) {
    rows = rows.filter((r) => r.category === query.category);
  }
  if (query.status === 'active') rows = rows.filter((r) => r.isActive);
  if (query.status === 'inactive') rows = rows.filter((r) => !r.isActive);

  rows.sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));

  return {
    total: rows.length,
    limit: query.limit,
    offset: query.offset,
    items: rows.slice(query.offset, query.offset + query.limit),
  };
}

export async function getProductDetail(productId: string): Promise<AdminProductDetail> {
  const snap = await fbDb().collection('products').doc(productId).get();
  if (!snap.exists) {
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }
  return toProductDetail(productId, snap.data() ?? {});
}

export async function updateProduct(
  productId: string,
  patch: ProductUpdate
): Promise<AdminProductDetail> {
  const ref = fbDb().collection('products').doc(productId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }
  const data = buildProductUpdateData(patch);
  if (Object.keys(data).length === 0) {
    return toProductDetail(productId, snap.data() ?? {});
  }
  try {
    await ref.update(data);
  } catch (err) {
    throw new ApiError(
      500,
      'PRODUCT_WRITE_FAILED',
      'We could not save that product. Try again.',
      { cause: (err as Error).message }
    );
  }
  const after = await ref.get();
  return toProductDetail(productId, after.data() ?? {});
}

/**
 * Delete the listing and best-effort its reviews subcollection. Order items
 * are checkout-time snapshots, so past orders keep their copy and prices.
 */
export async function deleteProduct(productId: string): Promise<DeleteProductResult> {
  const ref = fbDb().collection('products').doc(productId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }

  let reviewsDeleted = 0;
  try {
    const reviews = await ref.collection('reviews').get();
    if (!reviews.empty) {
      const batch = fbDb().batch();
      for (const doc of reviews.docs) {
        batch.delete(doc.ref);
        reviewsDeleted += 1;
      }
      await batch.commit();
    }
  } catch {
    reviewsDeleted = 0;
  }

  try {
    await ref.delete();
  } catch (err) {
    throw new ApiError(
      500,
      'PRODUCT_DELETE_FAILED',
      'We could not delete that product. Try again.',
      { cause: (err as Error).message }
    );
  }

  return { productId, deleted: true, reviewsDeleted };
}
