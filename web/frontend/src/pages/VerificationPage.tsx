import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { verificationApi } from '../api/api';
import { ApiError, apiBaseConfigured, apiBaseUrl } from '../api/client';
import type {
  ApplicationFilter,
  VerificationApplication,
  VerificationApplicationSummary,
  VerificationDocument,
} from '../api/types';
import { ApplicationStatusBadge } from '../components/Badge';
import { DataTable, type Column, type SortState } from '../components/DataTable';
import { Modal } from '../components/Modal';
import {
  IconAlertTriangle,
  IconBox,
  IconRefresh,
  IconShield,
  IconX,
} from '../components/icons';
import { useToast } from '../state/ToastContext';

/**
 * Verification review console — suppliers upload IC (identity card) images
 * plus 0–5 supporting documents to earn the "Verified" badge; an admin
 * inspects every file here and approves or rejects.
 *
 * All bytes travel through the authenticated API
 * (`GET /verification/applications/:uid/documents/:docId`) as Blobs — there
 * is deliberately no public Storage URL for `verification/**`, so a leaked
 * link can never expose an identity card.
 */

/* ── Honest error copy (same house style as LoginPage.describeLoginError) ── */
function describeVerificationError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Something went wrong while loading verification data. Try again.';
  switch (err.code) {
    case 'UNAUTHENTICATED':
      return 'Your session has expired. Sign in again to keep reviewing applications.';
    case 'NOT_ADMIN':
      return 'This account doesn’t have admin access — only administrators can review verification applications.';
    case 'HTTP_403':
      return 'Access denied — this account isn’t an administrator.';
    case 'NETWORK_ERROR':
      return apiBaseConfigured
        ? 'Can’t reach the admin API. Check your internet connection — or the backend may be down.'
        : `Can’t reach the admin API at ${apiBaseUrl}. VITE_API_BASE_URL isn’t set for this build, so the console fell back to the local default — whoever deployed it must set that variable and rebuild.`;
    case 'FIREBASE_NOT_CONFIGURED':
      return 'The server has no Firebase credentials configured (FIREBASE_SERVICE_ACCOUNT_JSON / SERVICE_ACCOUNT_PATH), so documents can’t be read. Ask whoever deployed this console to set them.';
    case 'APPLICATION_NOT_FOUND':
      return 'This application doesn’t exist — the supplier hasn’t submitted documents yet.';
    case 'DOCUMENT_NOT_FOUND':
      return 'That document isn’t part of this application.';
    case 'STORAGE_OBJECT_MISSING':
      return 'The uploaded file is missing from Storage. Ask the supplier to submit their documents again.';
    case 'INVALID_DOCUMENT_PATH':
      return 'This application declared an unexpected file location and was refused — re-check the upload before approving.';
    case 'STORAGE_READ_ERROR':
      return 'The document couldn’t be read from Storage. Try opening it again.';
    case 'USER_NOT_FOUND':
      return 'No user profile exists for this applicant — restore the profile before deciding.';
    case 'NOT_SUPPLIER':
      return 'Only supplier accounts can be verified; this account’s role is not “supplier”.';
    case 'VALIDATION_ERROR':
      return err.message;
    default:
      return err.message || `Request failed (${err.status}).`;
  }
}

/* ── Formatting helpers ─────────────────────────────────────────────────── */
function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

function formatBytes(n: number): string {
  if (!n || n < 0) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

const DOC_KIND_LABEL: Record<VerificationDocument['kind'], string> = {
  ic_front: 'IC card — front',
  ic_back: 'IC card — back',
  supporting: 'Supporting document',
};

function isImageType(contentType: string): boolean {
  return contentType.toLowerCase().startsWith('image/');
}

function isPdfType(contentType: string): boolean {
  return contentType.toLowerCase() === 'application/pdf';
}

/** IC front, IC back, then supporting docs — the identity proof leads. */
function orderDocuments(docs: VerificationDocument[]): VerificationDocument[] {
  const rank = (d: VerificationDocument) =>
    d.kind === 'ic_front' ? 0 : d.kind === 'ic_back' ? 1 : 2;
  return [...docs].sort((a, b) => rank(a) - rank(b));
}

const FILTER_CHIPS: { value: ApplicationFilter; label: string }[] = [
  { value: 'pending', label: 'Pending' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'all', label: 'All' },
];

/* ── Document previews ──────────────────────────────────────────────────── */
interface PreviewState {
  url?: string;
  loading?: boolean;
  error?: string;
}

/**
 * Object URLs keyed `uid:docId`. They survive opening/closing the drawer
 * (no refetch on every click) but are revoked — with the cache cleared —
 * when the page unmounts, so nothing outlives the session.
 */
const previewCache = new Map<string, string>();

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface Props {
  /** Global search from the topbar — filters this queue client-side. */
  query?: string;
}

export function VerificationPage({ query = '' }: Props) {
  const { push } = useToast();

  /* ── Queue ── */
  const [filter, setFilter] = useState<ApplicationFilter>('pending');
  const [rows, setRows] = useState<VerificationApplicationSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sort, setSort] = useState<SortState | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  /* ── Detail drawer ── */
  const [selectedUid, setSelectedUid] = useState<string | null>(null);
  const [detail, setDetail] = useState<VerificationApplication | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [previews, setPreviews] = useState<Record<string, PreviewState>>({});
  const drawerRef = useRef<HTMLDivElement>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const selectedRef = useRef<string | null>(null);

  /* ── Decisions ── */
  const [note, setNote] = useState('');
  const [rejectAttempted, setRejectAttempted] = useState(false);
  const [busy, setBusy] = useState<'approve' | 'reject' | null>(null);
  const [confirmReject, setConfirmReject] = useState(false);

  /* ── Enlarged viewer ── */
  const [viewerDoc, setViewerDoc] = useState<VerificationDocument | null>(null);

  const refresh = () => setReloadKey((k) => k + 1);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await verificationApi.list(filter);
      setRows(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(describeVerificationError(err));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  // Revoke every object URL when the page goes away.
  useEffect(
    () => () => {
      for (const url of previewCache.values()) URL.revokeObjectURL(url);
      previewCache.clear();
    },
    []
  );

  const loadDetail = useCallback(async (uid: string) => {
    setDetailLoading(true);
    setDetailError(null);
    try {
      const { application } = await verificationApi.get(uid);
      if (selectedRef.current !== uid) return; // superseded by a newer open
      setDetail(application);
      // Fetch thumbnails — one request per document, through the API.
      for (const doc of application.documents) {
        const key = `${application.uid}:${doc.id}`;
        const cached = previewCache.get(key);
        if (cached) {
          setPreviews((p) => ({ ...p, [key]: { url: cached } }));
          continue;
        }
        setPreviews((p) => ({ ...p, [key]: { loading: true } }));
        try {
          const blob = await verificationApi.documentBlob(application.uid, doc.id);
          const url = URL.createObjectURL(blob);
          previewCache.set(key, url);
          setPreviews((p) => ({ ...p, [key]: { url } }));
        } catch (err) {
          if (selectedRef.current !== uid) return;
          setPreviews((p) => ({ ...p, [key]: { error: describeVerificationError(err) } }));
        }
      }
    } catch (err) {
      if (selectedRef.current !== uid) return;
      setDetailError(describeVerificationError(err));
    } finally {
      if (selectedRef.current === uid) setDetailLoading(false);
    }
  }, []);

  const openDetail = (uid: string) => {
    openerRef.current = document.activeElement as HTMLElement | null;
    selectedRef.current = uid;
    setSelectedUid(uid);
    setDetail(null);
    setNote('');
    setRejectAttempted(false);
    setConfirmReject(false);
    setViewerDoc(null);
    void loadDetail(uid);
  };

  const closeDetail = () => {
    selectedRef.current = null;
    setSelectedUid(null);
    setDetail(null);
    setNote('');
    setRejectAttempted(false);
    setConfirmReject(false);
    setViewerDoc(null);
    openerRef.current?.focus?.();
  };

  /* Drawer: focus in on open, Escape closes, Tab cycles within — and it
   * stands down whenever a Modal is on top (the Modal owns focus then). */
  useEffect(() => {
    if (!selectedUid) return;
    drawerRef.current?.focus();
    const onKeyDown = (e: KeyboardEvent) => {
      if (document.querySelector('.overlay .modal')) return;
      if (e.key === 'Escape') {
        e.preventDefault();
        closeDetail();
        return;
      }
      const dialog = drawerRef.current;
      if (e.key !== 'Tab' || !dialog) return;
      const focusables = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (el) => el.offsetParent !== null
      );
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || active === dialog)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [selectedUid]);

  /* ── Approve / reject ─────────────────────────────────────────────────── */
  const decide = async (status: 'approved' | 'rejected') => {
    if (!selectedUid || busy) return;
    const trimmed = note.trim();
    if (status === 'rejected' && !trimmed) {
      setRejectAttempted(true);
      return;
    }
    setBusy(status === 'approved' ? 'approve' : 'reject');
    try {
      const result = await verificationApi.decide(selectedUid, status, trimmed || undefined);
      push(
        'success',
        `${result.application.businessName || result.application.email} ${
          status === 'approved' ? 'approved' : 'rejected'
        } → ${result.verificationStatus}` +
          (result.productsSynced
            ? ` · ${result.productsSynced} listing${result.productsSynced === 1 ? '' : 's'} synced`
            : '')
      );
      setNote('');
      setRejectAttempted(false);
      setConfirmReject(false);
      await loadDetail(selectedUid);
      refresh();
    } catch (err) {
      push('error', describeVerificationError(err));
    } finally {
      setBusy(null);
    }
  };

  const onRejectClick = () => {
    if (!note.trim()) {
      setRejectAttempted(true);
      return;
    }
    setConfirmReject(true);
  };

  /* ── Table ────────────────────────────────────────────────────────────── */
  const debouncedQuery = query.trim().toLowerCase();

  const filteredRows = useMemo(() => {
    if (!debouncedQuery) return rows;
    return rows.filter(
      (r) =>
        r.email.toLowerCase().includes(debouncedQuery) ||
        r.businessName.toLowerCase().includes(debouncedQuery) ||
        r.uid.toLowerCase().includes(debouncedQuery)
    );
  }, [rows, debouncedQuery]);

  const columns = useMemo<Column<VerificationApplicationSummary>[]>(
    () => [
      {
        key: 'applicant',
        header: 'Applicant',
        sortValue: (r) => (r.businessName || r.email).toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span>{r.businessName || '—'}</span>
            <small className="mono">{r.email}</small>
          </div>
        ),
      },
      {
        key: 'submitted',
        header: 'Submitted',
        sortValue: (r) => r.submittedAt,
        render: (r) => formatDateTime(r.submittedAt),
        width: '170px',
      },
      {
        key: 'documents',
        header: 'Documents',
        sortValue: (r) => r.documentCount,
        render: (r) => `${r.documentCount} file${r.documentCount === 1 ? '' : 's'}`,
        width: '110px',
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (r) => r.status,
        render: (r) => <ApplicationStatusBadge status={r.status} />,
        width: '120px',
      },
      {
        key: 'actions',
        header: 'Actions',
        align: 'right',
        width: '110px',
        render: (r) => (
          <div className="row-actions">
            <button
              className={`btn-mini ${r.status === 'pending' ? 'btn-verify' : ''}`}
              onClick={() => openDetail(r.uid)}
            >
              Review
            </button>
          </div>
        ),
      },
    ],
    []
  );

  const sortedRows = useMemo(() => {
    if (!sort) return filteredRows;
    const col = columns.find((c) => c.key === sort.key);
    if (!col?.sortValue) return filteredRows;
    const get = col.sortValue;
    const dir = sort.dir === 'asc' ? 1 : -1;
    return [...filteredRows].sort((a, b) => {
      const va = get(a);
      const vb = get(b);
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * dir;
      return String(va).localeCompare(String(vb), undefined, { numeric: true }) * dir;
    });
  }, [filteredRows, sort, columns]);

  const onSortChange = (key: string) => {
    setSort((prev) => (prev?.key === key ? (prev.dir === 'asc' ? { key, dir: 'desc' } : null) : { key, dir: 'asc' }));
  };

  const noteError =
    rejectAttempted && !note.trim()
      ? 'A note is required when rejecting — the supplier sees it and needs to know what to fix.'
      : null;

  const emptyMessage = debouncedQuery
    ? 'No applications match your search.'
    : filter === 'pending'
      ? 'No applications awaiting review — the queue is clear.'
      : `No ${filter} applications.`;

  const orderedDocs = detail ? orderDocuments(detail.documents) : [];

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Supplier verification queue</h2>
          <p className="subtitle">
            Suppliers submit IC (identity card) images and supporting documents to earn the
            Verified badge. Inspect every file, then approve or reject — your decision updates the
            supplier&apos;s status and every one of their listings.
          </p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={refresh} disabled={loading}>
          <IconRefresh size={14} />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      <div className="toolbar">
        <div className="filter-group" role="group" aria-label="Filter applications by status">
          <span className="filter-label">Status</span>
          <div className="chip-group">
            {FILTER_CHIPS.map((c) => (
              <button
                key={c.value}
                className="chip"
                aria-pressed={filter === c.value}
                onClick={() => {
                  setFilter(c.value);
                  setSort(null);
                }}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>
        {debouncedQuery && (
          <span className="panel-note">
            {filteredRows.length} of {total} match “{query.trim()}”
          </span>
        )}
      </div>

      <section className="panel">
        <DataTable
          columns={columns}
          rows={sortedRows}
          rowKey={(r) => r.uid}
          loading={loading}
          error={error}
          onRetry={() => void load()}
          sort={sort}
          onSortChange={onSortChange}
          emptyMessage={emptyMessage}
        />
        <div className="panel-footer">
          <span>
            {filteredRows.length} of {total.toLocaleString()} shown
            {filter !== 'all' ? ` · ${filter} only` : ''}
          </span>
        </div>
      </section>

      {/* ── Detail drawer ── */}
      {selectedUid && (
        <div
          className="drawer-overlay"
          onMouseDown={(e) => e.target === e.currentTarget && closeDetail()}
        >
          <div
            className="drawer"
            ref={drawerRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="drawer-title"
            tabIndex={-1}
          >
            <div className="drawer-header">
              <div className="modal-title-wrap">
                <span className="modal-icon tone-accent">
                  <IconShield size={18} />
                </span>
                <div>
                  <h2 id="drawer-title">
                    {detail?.businessName || detail?.email || 'Verification application'}
                  </h2>
                  <span className="drawer-subtitle mono">{selectedUid}</span>
                </div>
              </div>
              <button className="icon-button" aria-label="Close review panel" onClick={closeDetail}>
                <IconX size={16} />
              </button>
            </div>

            <div className="drawer-body">
              {detailLoading && !detail && (
                <div className="drawer-state">
                  <span className="spinner" />
                  Loading application…
                </div>
              )}
              {detailError && (
                <div className="alert error-box" role="alert">
                  <IconAlertTriangle size={16} />
                  <span>
                    {detailError}{' '}
                    <button className="link-button" onClick={() => void loadDetail(selectedUid)}>
                      Retry
                    </button>
                  </span>
                </div>
              )}

              {detail && (
                <>
                  <div className="review-meta">
                    <div className="review-meta-row">
                      <span className="review-meta-label">Status</span>
                      <ApplicationStatusBadge status={detail.status} />
                    </div>
                    <div className="review-meta-row">
                      <span className="review-meta-label">Email</span>
                      <span className="mono">{detail.email}</span>
                    </div>
                    <div className="review-meta-row">
                      <span className="review-meta-label">Business</span>
                      <span>{detail.businessName || '—'}</span>
                    </div>
                    <div className="review-meta-row">
                      <span className="review-meta-label">Submitted</span>
                      <span>{formatDateTime(detail.submittedAt)}</span>
                    </div>
                    {detail.reviewedAt && (
                      <div className="review-meta-row">
                        <span className="review-meta-label">Reviewed</span>
                        <span>
                          {formatDateTime(detail.reviewedAt)}
                          {detail.reviewedBy ? <small className="mono"> by {detail.reviewedBy}</small> : null}
                        </span>
                      </div>
                    )}
                    {detail.reviewNote && (
                      <div className="review-meta-row note-row">
                        <span className="review-meta-label">Review note</span>
                        <span className="review-note-bubble">{detail.reviewNote}</span>
                      </div>
                    )}
                  </div>

                  <section className="doc-section">
                    <div className="doc-section-head">
                      <h3>Submitted documents</h3>
                      <span className="panel-note">Click a file to view it full size</span>
                    </div>
                    <div className="doc-grid">
                      {orderedDocs.map((doc) => {
                        const key = `${detail.uid}:${doc.id}`;
                        const p = previews[key];
                        const ic = doc.kind !== 'supporting';
                        return (
                          <button
                            type="button"
                            key={doc.id}
                            className={`doc-card${ic ? ' is-ic' : ''}`}
                            onClick={() => setViewerDoc(doc)}
                            aria-label={`View ${DOC_KIND_LABEL[doc.kind]} — ${doc.fileName}`}
                          >
                            <span className="doc-thumb">
                              {p?.url ? (
                                <img src={p.url} alt="" />
                              ) : p?.error ? (
                                <IconAlertTriangle size={20} />
                              ) : (
                                <span className="spinner" />
                              )}
                            </span>
                            <span className="doc-card-body">
                              <span className="doc-kind">{DOC_KIND_LABEL[doc.kind]}</span>
                              <span className="doc-name mono" title={doc.fileName}>
                                {doc.fileName}
                              </span>
                              <span className="doc-meta">
                                {formatBytes(doc.sizeBytes)} · {formatDateTime(doc.uploadedAt)}
                              </span>
                              {p?.error && <span className="field-error">{p.error}</span>}
                            </span>
                          </button>
                        );
                      })}
                      {orderedDocs.length === 0 && (
                        <div className="doc-empty">
                          <IconBox size={20} />
                          No documents were attached to this application.
                        </div>
                      )}
                    </div>
                  </section>

                  <section className="doc-section">
                    <div className="doc-section-head">
                      <h3>Decision</h3>
                    </div>
                    <div className="field">
                      <label className="field-label" htmlFor="review-note">
                        Review note
                      </label>
                      <textarea
                        id="review-note"
                        className="input textarea"
                        value={note}
                        maxLength={2000}
                        onChange={(e) => {
                          setNote(e.target.value);
                          if (noteError) setRejectAttempted(false);
                        }}
                        placeholder="e.g. IC photo is blurry — please re-upload a sharper scan."
                        aria-invalid={noteError ? true : undefined}
                        aria-describedby={noteError ? 'review-note-error' : 'review-note-hint'}
                      />
                      <span className="field-hint" id="review-note-hint">
                        Required when rejecting — the supplier sees this note. Optional when
                        approving.
                      </span>
                      {noteError && (
                        <span className="field-error" id="review-note-error" role="alert">
                          {noteError}
                        </span>
                      )}
                    </div>
                  </section>
                </>
              )}
            </div>

            <div className="drawer-footer">
              <button
                className="btn btn-secondary"
                onClick={closeDetail}
                disabled={busy !== null}
              >
                Close
              </button>
              <span className="drawer-footer-spacer" />
              <button
                className="btn btn-danger"
                onClick={onRejectClick}
                disabled={!detail || busy !== null}
                aria-busy={busy === 'reject'}
              >
                {busy === 'reject' ? (
                  <>
                    <span className="spinner spinner-inline" />
                    Rejecting…
                  </>
                ) : (
                  'Reject'
                )}
              </button>
              <button
                className="btn btn-primary"
                onClick={() => void decide('approved')}
                disabled={!detail || busy !== null}
                aria-busy={busy === 'approve'}
              >
                {busy === 'approve' ? (
                  <>
                    <span className="spinner spinner-inline" />
                    Approving…
                  </>
                ) : (
                  'Approve'
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Confirm rejection (destructive → always confirmed) ── */}
      {confirmReject && detail && (
        <Modal
          title="Reject this application?"
          tone="danger"
          headerIcon={<IconAlertTriangle size={18} />}
          onClose={() => !busy && setConfirmReject(false)}
          width={520}
        >
          <p className="confirm-copy">
            <strong>{detail.businessName || detail.email}</strong> will be marked{' '}
            <strong>rejected</strong>: they lose the Verified badge, their listings are unverified
            for buyers, and they see the note below. They can fix the issue and re-apply.
          </p>
          <div className="note-preview">{note.trim()}</div>
          <div className="modal-actions">
            <button className="btn btn-secondary" onClick={() => setConfirmReject(false)} disabled={busy !== null}>
              Cancel
            </button>
            <button
              className="btn btn-danger"
              onClick={() => void decide('rejected')}
              disabled={busy !== null}
              aria-busy={busy === 'reject'}
            >
              {busy === 'reject' ? (
                <>
                  <span className="spinner spinner-inline" />
                  Rejecting…
                </>
              ) : (
                'Reject application'
              )}
            </button>
          </div>
        </Modal>
      )}

      {/* ── Enlarged document viewer ── */}
      {viewerDoc && detail && (
        <Modal
          title={`${DOC_KIND_LABEL[viewerDoc.kind]} — ${viewerDoc.fileName}`}
          onClose={() => setViewerDoc(null)}
          width={860}
        >
          <DocumentViewer
            url={previews[`${detail.uid}:${viewerDoc.id}`]?.url}
            document={viewerDoc}
          />
          <div className="viewer-meta">
            <span>{formatBytes(viewerDoc.sizeBytes)}</span>
            <span>{viewerDoc.contentType}</span>
            <span>Uploaded {formatDateTime(viewerDoc.uploadedAt)}</span>
          </div>
        </Modal>
      )}
    </div>
  );
}

/** Full-size render of one already-fetched document (object URL from the
 * authenticated blob fetch — no public link exists for these files). */
function DocumentViewer({ url, document: doc }: { url?: string; document: VerificationDocument }) {
  const [broken, setBroken] = useState(false);

  if (!url) {
    return (
      <div className="viewer-state">
        <span className="spinner" />
        Fetching document…
      </div>
    );
  }

  if (broken) {
    return (
      <div className="viewer-state error-state">
        <IconAlertTriangle size={22} />
        <span>This file couldn’t be rendered in the browser.</span>
        <a className="btn btn-secondary btn-sm" href={url} target="_blank" rel="noreferrer">
          Open in a new tab
        </a>
      </div>
    );
  }

  if (isImageType(doc.contentType)) {
    return (
      <img
        className="viewer-img"
        src={url}
        alt={`${DOC_KIND_LABEL[doc.kind]} — ${doc.fileName}`}
        onError={() => setBroken(true)}
      />
    );
  }

  if (isPdfType(doc.contentType)) {
    return (
      <object className="viewer-frame" data={url} type="application/pdf">
        <div className="viewer-state">
          <span>Your browser can’t display this PDF inline.</span>
          <a className="btn btn-secondary btn-sm" href={url} target="_blank" rel="noreferrer">
            Open in a new tab
          </a>
        </div>
      </object>
    );
  }

  return (
    <div className="viewer-state">
      <IconBox size={22} />
      <span>
        {doc.fileName} ({doc.contentType}) can’t be previewed inline.
      </span>
      <a className="btn btn-secondary btn-sm" href={url} download={doc.fileName}>
        Download file
      </a>
    </div>
  );
}
