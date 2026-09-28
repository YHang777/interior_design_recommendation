import { Router } from 'express';
import { z } from 'zod';
import { authenticate } from '../middleware/authenticate';
import { requireAdmin } from '../middleware/requireAdmin';
import { validateBody, validateParams, validateQuery } from '../middleware/validate';
import { asyncHandler, ApiError } from '../lib/errors';
import {
  decideApplication,
  documentContentType,
  getApplication,
  listApplications,
  openApplicationDocument,
} from '../services/applications.service';
import type { ApplicationStatus } from '../types/models';

/**
 * Supplier verification review console — IC + supporting documents.
 *
 * Chain on every route: authenticate → requireAdmin → validate → handler →
 * services/. There is NO unauthenticated or non-admin path here: these
 * documents are identity PII. File bytes are never returned in list/detail
 * JSON — only `GET …/documents/:docId` streams one declared object, via the
 * Admin SDK (Storage client reads of `verification/**` are denied by
 * `storage.rules`, so no public download URL exists for these files).
 */

const uidParam = z.object({
  uid: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid Firebase UID.'),
});

const documentParams = z.object({
  uid: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/, 'Not a valid Firebase UID.'),
  docId: z
    .string()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9._-]+$/, 'Not a valid document id.')
    .refine((v) => !v.includes('..'), 'Not a valid document id.'),
});

const listQuery = z.object({
  status: z.enum(['pending', 'approved', 'rejected', 'all']).default('pending'),
  limit: z.coerce.number().int().min(1).max(200).default(100),
  offset: z.coerce.number().int().min(0).default(0),
});

const decisionBody = z.object({
  status: z.enum(['approved', 'rejected']),
  reviewNote: z.string().max(2000, 'Review notes are capped at 2000 characters.').optional(),
});

export const verificationRouter = Router();

verificationRouter.use(authenticate, requireAdmin);

/**
 * GET /api/verification/applications?status=pending|approved|rejected|all
 * Queue rows: uid, email, businessName, status, submittedAt, document count.
 * Metadata only — never file bytes.
 */
verificationRouter.get(
  '/applications',
  validateQuery(listQuery),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as z.infer<typeof listQuery>;
    res.json(await listApplications(q.status as ApplicationStatus | 'all', q.limit, q.offset));
  })
);

/** GET /api/verification/applications/:uid — full application + documents[]. */
verificationRouter.get(
  '/applications/:uid',
  validateParams(uidParam),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as z.infer<typeof uidParam>;
    res.json({ application: await getApplication(uid) });
  })
);

/**
 * GET /api/verification/applications/:uid/documents/:docId
 * Streams the raw bytes of ONE declared document. `:docId` is matched
 * against the application's own `documents[]` first, so the admin cannot
 * probe arbitrary Storage paths. `Content-Type` is re-validated against an
 * image/PDF allowlist (the stored value is supplier-authored).
 */
verificationRouter.get(
  '/applications/:uid/documents/:docId',
  validateParams(documentParams),
  asyncHandler(async (req, res) => {
    const { uid, docId } = req.params as z.infer<typeof documentParams>;
    const { document, stream, sizeBytes } = await openApplicationDocument(uid, docId);
    const { contentType, disposition } = documentContentType(document);

    res.status(200);
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Disposition', disposition);
    // Identity documents: never cacheable by shared/intermediary caches.
    res.setHeader('Cache-Control', 'private, max-age=0, no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (sizeBytes !== null) res.setHeader('Content-Length', String(sizeBytes));

    stream.on('error', (err: Error) => {
      // Log the failure only — never the payload.
      console.error(`[verification] document stream failed for ${uid}/${docId}: ${err.message}`);
      if (res.headersSent) res.destroy(err);
      else res.status(500).json({ error: { code: 'STORAGE_READ_ERROR', message: 'Could not read the document from Storage.' } });
    });
    res.on('close', () => stream.destroy());
    stream.pipe(res);
  })
);

/**
 * PATCH /api/verification/applications/:uid
 * Body: { status: 'approved' | 'rejected', reviewNote?: string }
 * Approve → users/{uid}.verificationStatus = 'verified';
 * Reject  → users/{uid}.verificationStatus = 'rejected'.
 * Both also sync every owned product's embedded supplier.verificationStatus
 * (batched) and record reviewedAt / reviewedBy / reviewNote.
 */
verificationRouter.patch(
  '/applications/:uid',
  validateParams(uidParam),
  validateBody(decisionBody),
  asyncHandler(async (req, res) => {
    const { uid } = req.params as z.infer<typeof uidParam>;
    const { status, reviewNote } = req.body as z.infer<typeof decisionBody>;
    const adminUid = req.user?.uid;
    if (!adminUid) throw new ApiError(401, 'UNAUTHENTICATED', 'Authentication required.');
    res.json(await decideApplication(uid, adminUid, status, reviewNote));
  })
);
