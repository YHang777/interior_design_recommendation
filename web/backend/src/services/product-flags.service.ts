import type { RequestHandler } from 'express';
import { fbDb } from '../config/firebase';
import { ApiError } from '../lib/errors';
import { authenticate } from '../middleware/authenticate';
import type {
  ProductFlagListResult,
  ProductFlagReview,
  ProductFlagRow,
} from '../types/models';

/**
 * Admin review queue for photo-vs-claim mismatches (`/api/products/flags`).
 *
 * The upload-time vision pass (`product-vision.service`) stamps
 * `products/{id}.vision.mismatch.flagged = true` when the photo clearly
 * shows something other than what the listing claims. This service is the
 * other half of that contract: it lists those rows and records the admin's
 * decision at `vision.review` — written only through firebase-admin, so a
 * client can neither forge a verdict nor clear its own flag.
 *
 * The list query only asks Firestore for `mismatch.flagged == true` (a
 * single-field filter — automatic index); open/resolved filtering and the
 * newest-first sort happen here, because "open" includes the majority case
 * where `review` does not exist yet.
 */

export type ProductFlagStatusFilter = 'open' | 'resolved' | 'all';

/** Collaborators the routes need — injectable so tests never touch Firestore. */
export interface ProductFlagsDeps {
  list: (status: ProductFlagStatusFilter) => Promise<ProductFlagListResult>;
  setReview: (
    productId: string,
    status: 'resolved' | 'open',
    note: string | undefined,
    adminUid: string
  ) => Promise<ProductFlagRow>;
  /** Auth step. Defaults to the real Firebase ID-token check. */
  authorize: RequestHandler;
  log?: (message: string) => void;
}

export function defaultProductFlagsDeps(): ProductFlagsDeps {
  return {
    list: (status) => listFlaggedProducts(status),
    setReview: (productId, status, note, adminUid) =>
      setProductReview(productId, status, note, adminUid),
    authorize: authenticate,
    log: (message) => console.log(message),
  };
}

export async function listFlaggedProducts(
  status: ProductFlagStatusFilter
): Promise<ProductFlagListResult> {
  const snap = await fbDb()
    .collection('products')
    .where('vision.mismatch.flagged', '==', true)
    .get();

  const rows = snap.docs
    .map((doc) => toFlagRow(doc.id, doc.data()))
    // Absent review ⇒ open (the majority case for a fresh flag).
    .filter((row) => status === 'all' || (row.review?.status ?? 'open') === status)
    // Newest analysis first — what an admin triages top-down.
    .sort((a, b) => (b.vision.analyzedAt ?? '').localeCompare(a.vision.analyzedAt ?? ''));

  return { items: rows, total: rows.length };
}

export async function setProductReview(
  productId: string,
  status: 'resolved' | 'open',
  note: string | undefined,
  adminUid: string
): Promise<ProductFlagRow> {
  const ref = fbDb().collection('products').doc(productId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }
  const data = snap.data() ?? {};
  const existingVision = data.vision;
  if (!existingVision || typeof existingVision !== 'object' || Array.isArray(existingVision)) {
    // PATCH only makes sense on an analyzed listing (the queue only ever
    // shows those) — a review-only `vision` map must never be born here.
    throw new ApiError(404, 'PRODUCT_NOT_FOUND', 'That product could not be found.');
  }

  const review: ProductFlagReview = {
    status,
    ...(note !== undefined && note.length > 0 ? { note } : {}),
    reviewedAt: new Date().toISOString(),
    reviewedBy: adminUid,
  };

  // Merge the review into the EXISTING vision map: a dotted-path update
  // would risk clobbering sibling keys if the shape ever drifts.
  await ref.update({
    vision: { ...(existingVision as Record<string, unknown>), review },
  });

  return { ...toFlagRow(productId, data), review };
}

/** Firestore doc → queue row, defensively (legacy/missing fields become empty). */
export function toFlagRow(
  productId: string,
  data: Record<string, unknown>
): ProductFlagRow {
  const vision = (data.vision ?? {}) as Record<string, unknown>;
  const mismatch = (vision.mismatch ?? {}) as { flagged?: unknown; reason?: unknown };
  const rawReview = vision.review as Record<string, unknown> | undefined;
  const review: ProductFlagReview | null =
    rawReview && (rawReview.status === 'open' || rawReview.status === 'resolved')
      ? {
          status: rawReview.status,
          ...(typeof rawReview.note === 'string' ? { note: rawReview.note } : {}),
          reviewedAt:
            typeof rawReview.reviewedAt === 'string' ? rawReview.reviewedAt : '',
          reviewedBy:
            typeof rawReview.reviewedBy === 'string' ? rawReview.reviewedBy : '',
        }
      : null;

  return {
    productId,
    name: typeof data.name === 'string' ? data.name : '',
    category: typeof data.category === 'string' ? data.category : '',
    price: typeof data.price === 'number' ? data.price : 0,
    supplierId: typeof data.supplierId === 'string' ? data.supplierId : '',
    image: typeof data.image === 'string' ? data.image : '',
    description: typeof data.description === 'string' ? data.description : '',
    vision: {
      status: typeof vision.status === 'string' ? vision.status : '',
      labels: Array.isArray(vision.labels)
        ? vision.labels.filter((l): l is string => typeof l === 'string')
        : [],
      visualCategory:
        typeof vision.visualCategory === 'string' ? vision.visualCategory : '',
      summary: typeof vision.summary === 'string' ? vision.summary : '',
      mismatch: {
        flagged: mismatch.flagged === true,
        reason: typeof mismatch.reason === 'string' ? mismatch.reason : '',
      },
      analyzedAt:
        typeof vision.analyzedAt === 'string' ? vision.analyzedAt : null,
      model: typeof vision.model === 'string' ? vision.model : '',
    },
    review,
  };
}
