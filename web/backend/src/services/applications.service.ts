import type { Readable } from 'node:stream';
import { ApiError } from '../lib/errors';
import { fbDb, fbStorage } from '../config/firebase';
import { setSupplierVerification } from './verification.service';
import type {
  ApplicationStatus,
  ReviewDecisionResult,
  VerificationApplication,
  VerificationApplicationSummary,
  VerificationDocument,
  VerificationListResult,
} from '../types/models';

/**
 * Verification applications — the supplier's IC (identity card) images and
 * supporting documents, written by the mobile app to
 * `verification_applications/{uid}` + Storage `verification/{uid}/{id}.{ext}`.
 *
 * This service is mounted ONLY behind `authenticate` + `requireAdmin`.
 * Invariant: response payloads carry document METADATA only — the raw bytes
 * are served one document at a time by `GET …/documents/:docId` (streamed
 * from Storage via the Admin SDK, which bypasses the deny-all client read
 * rule in `storage.rules`). Nothing here ever logs file bytes, and the
 * list/detail responses never inline an IC image.
 */

/** Storage content types rendered inline; anything else is forced to a
 * safe generic type + attachment disposition (the `documents[]` array is
 * supplier-authored, so `contentType` is untrusted input). */
const INLINE_SAFE_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/webp',
  'image/gif',
  'image/heic',
  'application/pdf',
]);

function toIso(value: unknown): string {
  if (value && typeof (value as { toISOString?: unknown }).toISOString === 'function') {
    return (value as Date).toISOString();
  }
  if (typeof value === 'string') return value;
  return new Date(0).toISOString();
}

function toIsoOrNull(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null;
  return toIso(value);
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function normalizeStatus(raw: unknown): ApplicationStatus {
  return raw === 'approved' || raw === 'rejected' ? raw : 'pending';
}

function normalizeDocument(raw: unknown): VerificationDocument | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const d = raw as Record<string, unknown>;
  const id = asString(d.id);
  const storagePath = asString(d.storagePath);
  if (!id || !storagePath) return null; // malformed entry — never streamed
  const kind =
    d.kind === 'ic_front' || d.kind === 'ic_back' || d.kind === 'supporting'
      ? d.kind
      : 'supporting';
  return {
    id,
    kind,
    fileName: asString(d.fileName, id),
    contentType: asString(d.contentType, 'application/octet-stream'),
    sizeBytes: typeof d.sizeBytes === 'number' && d.sizeBytes >= 0 ? d.sizeBytes : 0,
    storagePath,
    uploadedAt: toIso(d.uploadedAt),
  };
}

function normalizeApplication(uid: string, data: Record<string, unknown>): VerificationApplication {
  const documents = Array.isArray(data.documents)
    ? data.documents.map(normalizeDocument).filter((d): d is VerificationDocument => d !== null)
    : [];
  return {
    uid,
    email: asString(data.email),
    businessName: asString(data.businessName),
    status: normalizeStatus(data.status),
    submittedAt: toIso(data.submittedAt),
    reviewedAt: toIsoOrNull(data.reviewedAt),
    reviewedBy: asString(data.reviewedBy) || null,
    reviewNote: asString(data.reviewNote) || null,
    documents,
  };
}

/**
 * GET list. `status: 'all'` returns every application; otherwise a single
 * status bucket. Sorting/slicing happens in memory (one document per
 * supplier — deliberately avoids needing a composite index).
 */
export async function listApplications(
  status: ApplicationStatus | 'all',
  limit: number,
  offset: number
): Promise<VerificationListResult> {
  const col = fbDb().collection('verification_applications');
  const snap = status === 'all' ? await col.get() : await col.where('status', '==', status).get();

  const items: VerificationApplicationSummary[] = snap.docs.map((doc) => {
    const app = normalizeApplication(doc.id, doc.data() as Record<string, unknown>);
    return {
      uid: app.uid,
      email: app.email,
      businessName: app.businessName,
      status: app.status,
      submittedAt: app.submittedAt,
      documentCount: app.documents.length,
    };
  });
  items.sort((a, b) => b.submittedAt.localeCompare(a.submittedAt));

  return { total: items.length, limit, offset, items: items.slice(offset, offset + limit) };
}

/** Full application (including document metadata) — 404 when absent. */
export async function getApplication(uid: string): Promise<VerificationApplication> {
  const snap = await fbDb().collection('verification_applications').doc(uid).get();
  if (!snap.exists) {
    throw new ApiError(404, 'APPLICATION_NOT_FOUND', `No verification application for uid ${uid}.`);
  }
  return normalizeApplication(snap.id, snap.data() as Record<string, unknown>);
}

/**
 * Resolve one declared document to its Storage object and open a read
 * stream.
 *
 * Safety order (all three checks must pass):
 *  1. `:docId` is matched against THIS application's `documents[]` array —
 *     an admin cannot probe storage paths the application never declared;
 *  2. the declared `storagePath` must sit inside `verification/{uid}/` with
 *     no nested segments or `..` (the array is supplier-authored, so a
 *     crafted path must not reach another user's files);
 *  3. the object must actually exist.
 */
export async function openApplicationDocument(
  uid: string,
  docId: string
): Promise<{ document: VerificationDocument; stream: Readable; sizeBytes: number | null }> {
  const application = await getApplication(uid);
  const document = application.documents.find((d) => d.id === docId);
  if (!document) {
    throw new ApiError(
      404,
      'DOCUMENT_NOT_FOUND',
      'That document id is not part of this verification application.'
    );
  }

  const prefix = `verification/${uid}/`;
  const rest = document.storagePath.startsWith(prefix)
    ? document.storagePath.slice(prefix.length)
    : null;
  if (rest === null || rest.includes('/') || document.storagePath.includes('..')) {
    throw new ApiError(
      400,
      'INVALID_DOCUMENT_PATH',
      'Declared storage path is outside this application’s verification folder — refusing to read it.'
    );
  }

  const file = fbStorage().file(document.storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new ApiError(
      404,
      'STORAGE_OBJECT_MISSING',
      'The uploaded file is missing from Storage. Ask the supplier to submit again.'
    );
  }

  // Real object size for Content-Length — NEVER the declared `sizeBytes`,
  // which is supplier-authored and could be wrong (truncated/hung reads).
  let sizeBytes: number | null = null;
  try {
    const [meta] = await file.getMetadata();
    const size = Number(meta.size);
    if (Number.isFinite(size) && size >= 0) sizeBytes = size;
  } catch {
    sizeBytes = null; // fall back to chunked transfer — still correct
  }

  return { document, stream: file.createReadStream(), sizeBytes };
}

/**
 * Headers for one document: inline only for image/PDF types we trust,
 * everything else (untrusted `contentType` from the supplier's own upload
 * metadata) becomes `application/octet-stream` + attachment so a crafted
 * type can never render as HTML/script on the admin origin.
 */
export function documentContentType(document: VerificationDocument): {
  contentType: string;
  disposition: string;
} {
  const safe = INLINE_SAFE_TYPES.has(document.contentType.toLowerCase());
  const fileName = document.fileName.replace(/[^\w.\- ()[\]]+/g, '_').slice(0, 120) || 'document';
  return {
    contentType: safe ? document.contentType : 'application/octet-stream',
    disposition: `${safe ? 'inline' : 'attachment'}; filename="${fileName}"`,
  };
}

/**
 * PATCH — the admin's decision.
 *
 * 1. application must exist (404 otherwise);
 * 2. `setSupplierVerification` flips `users/{uid}.verificationStatus`
 *    (`verified` / `rejected`) AND syncs every owned product's embedded
 *    `supplier.verificationStatus` (batched) — the copy the buyer app's
 *    badge/filter reads;
 * 3. the application gets `status`, `reviewedAt`, `reviewedBy` (the admin's
 *    uid) and `reviewNote`; the note is mirrored to
 *    `users/{uid}.verificationReviewNote` so the supplier sees it from
 *    their own profile.
 *
 * Decision first, application second: if step 2 fails (missing profile /
 * not a supplier) nothing is written to the application.
 */
export async function decideApplication(
  uid: string,
  adminUid: string,
  status: 'approved' | 'rejected',
  reviewNote?: string
): Promise<ReviewDecisionResult> {
  const db = fbDb();
  const appRef = db.collection('verification_applications').doc(uid);
  const snap = await appRef.get();
  if (!snap.exists) {
    throw new ApiError(404, 'APPLICATION_NOT_FOUND', `No verification application for uid ${uid}.`);
  }

  const note = reviewNote?.trim() ? reviewNote.trim() : null;
  const verificationStatus = status === 'approved' ? 'verified' : 'rejected';

  const sync = await setSupplierVerification(uid, verificationStatus);
  await db
    .collection('users')
    .doc(uid)
    .update({ verificationReviewNote: note });

  const reviewedAt = new Date().toISOString();
  await appRef.update({ status, reviewedAt, reviewedBy: adminUid, reviewNote: note });

  const application = normalizeApplication(
    uid,
    { ...(snap.data() as Record<string, unknown>), status, reviewedAt, reviewedBy: adminUid, reviewNote: note }
  );
  return { application, verificationStatus, productsSynced: sync.productsSynced };
}
