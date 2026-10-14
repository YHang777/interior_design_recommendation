import { useCallback, useEffect, useMemo, useState } from 'react';
import { productFlagsApi } from '../api/api';
import { ApiError, apiBaseConfigured, apiBaseUrl } from '../api/client';
import type { ProductFlagRow, ProductFlagStatusFilter } from '../api/types';
import { DataTable, type Column, type SortState } from '../components/DataTable';
import { Modal } from '../components/Modal';
import { IconAlertTriangle, IconBox, IconCamera, IconRefresh, IconX } from '../components/icons';
import { useToast } from '../state/ToastContext';

/**
 * Photo-vs-claim review queue — the upload-time vision pass flags listings
 * whose photo clearly contradicts the seller's text; an admin inspects the
 * verdict here and resolves or reopens the flag. The decision is written to
 * `vision.review` through the API (server-owned field — clients can't forge
 * or clear it).
 */

/* ── Honest error copy (house style: short, plain, actionable) ── */
function describeFlagError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Something went wrong while loading photo flags. Try again.';
  switch (err.code) {
    case 'UNAUTHENTICATED':
      return 'Your session has expired. Sign in again to keep reviewing flags.';
    case 'NOT_ADMIN':
      return 'This account doesn’t have admin access — only administrators can review photo flags.';
    case 'HTTP_403':
      return 'Access denied — this account isn’t an administrator.';
    case 'NETWORK_ERROR':
      return apiBaseConfigured
        ? 'Can’t reach the admin API. Check your internet connection — or the backend may be down.'
        : `Can’t reach the admin API at ${apiBaseUrl}. VITE_API_BASE_URL isn’t set for this build, so the console fell back to the local default — whoever deployed it must set that variable and rebuild.`;
    case 'PRODUCT_NOT_FOUND':
      return 'This product no longer exists — the listing was deleted after it was flagged.';
    case 'VALIDATION_ERROR':
      return err.message;
    default:
      return err.message || `Request failed (${err.status}).`;
  }
}

/* ── Formatting helpers ── */
function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

function formatPrice(price: number): string {
  return `RM ${price.toLocaleString()}`;
}

const FILTER_CHIPS: { value: ProductFlagStatusFilter; label: string }[] = [
  { value: 'open', label: 'Open' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'all', label: 'All' },
];

/** Open flags carry no `review` yet (or an explicit reopen). */
function isOpen(row: ProductFlagRow): boolean {
  return (row.review?.status ?? 'open') === 'open';
}

function FlagBadge({ row }: { row: ProductFlagRow }) {
  const open = isOpen(row);
  return (
    <span className={`badge badge-status-${open ? 'pending' : 'verified'}`}>
      {open ? 'Open' : 'Resolved'}
    </span>
  );
}

interface Props {
  /** Global search from the topbar — filters this queue client-side. */
  query?: string;
}

export function ProductFlagsPage({ query = '' }: Props) {
  const { push } = useToast();

  const [filter, setFilter] = useState<ProductFlagStatusFilter>('open');
  const [rows, setRows] = useState<ProductFlagRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sort, setSort] = useState<SortState | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  /* ── Detail modal ── */
  const [selected, setSelected] = useState<ProductFlagRow | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState<'resolve' | 'reopen' | null>(null);

  const refresh = () => setReloadKey((k) => k + 1);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await productFlagsApi.list(filter);
      setRows(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(describeFlagError(err));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const openDetail = (row: ProductFlagRow) => {
    setSelected(row);
    setNote('');
  };

  const closeDetail = () => {
    setSelected(null);
    setNote('');
  };

  /* ── Resolve / reopen ── */
  const decide = async (status: 'resolved' | 'open') => {
    if (!selected || busy) return;
    setBusy(status === 'resolved' ? 'resolve' : 'reopen');
    try {
      await productFlagsApi.setReview(selected.productId, status, note.trim() || undefined);
      push(
        'success',
        status === 'resolved'
          ? `${selected.name} resolved — it stays listed, and the chat keeps treating the photo as truth.`
          : `${selected.name} reopened — back in the open queue.`
      );
      closeDetail();
      refresh();
    } catch (err) {
      push('error', describeFlagError(err));
    } finally {
      setBusy(null);
    }
  };

  /* ── Table ── */
  const debouncedQuery = query.trim().toLowerCase();

  const filteredRows = useMemo(() => {
    if (!debouncedQuery) return rows;
    return rows.filter(
      (r) =>
        r.name.toLowerCase().includes(debouncedQuery) ||
        r.category.toLowerCase().includes(debouncedQuery) ||
        r.supplierId.toLowerCase().includes(debouncedQuery)
    );
  }, [rows, debouncedQuery]);

  const columns = useMemo<Column<ProductFlagRow>[]>(
    () => [
      {
        key: 'listing',
        header: 'Listing',
        sortValue: (r) => r.name.toLowerCase(),
        render: (r) => (
          <div className="cell-primary flag-listing">
            {r.image ? (
              <img className="flag-thumb" src={r.image} alt="" loading="lazy" />
            ) : (
              <span className="flag-thumb flag-thumb-empty">
                <IconBox size={16} />
              </span>
            )}
            <span className="flag-listing-meta">
              <span>{r.name || '—'}</span>
              <small>
                {r.category || 'Uncategorised'} · {formatPrice(r.price)}
              </small>
            </span>
          </div>
        ),
      },
      {
        key: 'photo',
        header: 'Photo says',
        sortValue: (r) => r.vision.summary.toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span>{r.vision.summary || '—'}</span>
            <small className="warn-text">{r.vision.mismatch.reason || 'Photo does not match the description.'}</small>
          </div>
        ),
      },
      {
        key: 'seller',
        header: 'Seller claims',
        sortValue: (r) => r.description.toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span className="flag-clip">{r.description || '—'}</span>
            <small className="mono">{r.supplierId}</small>
          </div>
        ),
      },
      {
        key: 'analyzed',
        header: 'Analyzed',
        sortValue: (r) => r.vision.analyzedAt ?? '',
        render: (r) => formatDateTime(r.vision.analyzedAt),
        width: '170px',
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (r) => (isOpen(r) ? 'open' : 'resolved'),
        render: (r) => <FlagBadge row={r} />,
        width: '110px',
      },
      {
        key: 'actions',
        header: 'Actions',
        align: 'right',
        width: '110px',
        render: (r) => (
          <div className="row-actions">
            <button className={`btn-mini ${isOpen(r) ? 'btn-verify' : ''}`} onClick={() => openDetail(r)}>
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

  const emptyMessage = debouncedQuery
    ? 'No photo flags match your search.'
    : filter === 'open'
      ? 'No open photo flags — every flagged listing has been reviewed.'
      : `No ${filter} photo flags.`;

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Photo-vs-claim review queue</h2>
          <p className="subtitle">
            When a product photo clearly contradicts the seller&apos;s description, the upload-time
            vision pass flags the listing and the design chat trusts the photo over the seller text.
            Inspect each verdict, then resolve or reopen the flag.
          </p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={refresh} disabled={loading}>
          <IconRefresh size={14} />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      <div className="toolbar">
        <div className="filter-group" role="group" aria-label="Filter photo flags by status">
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
          rowKey={(r) => r.productId}
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

      {/* ── Detail modal: photo verdict vs seller text, then decide ── */}
      {selected && (
        <Modal
          title={selected.name || 'Photo flag'}
          onClose={() => !busy && closeDetail()}
          headerIcon={<IconCamera size={18} />}
          width={640}
        >
          <div className="review-meta">
            <div className="review-meta-row">
              <span className="review-meta-label">Status</span>
              <FlagBadge row={selected} />
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">Listing</span>
              <span>
                {selected.category || 'Uncategorised'} · {formatPrice(selected.price)}{' '}
                <small className="mono">{selected.productId}</small>
              </span>
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">Supplier</span>
              <span className="mono">{selected.supplierId || '—'}</span>
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">Analyzed</span>
              <span>
                {formatDateTime(selected.vision.analyzedAt)}
                {selected.vision.model ? <small className="mono"> · {selected.vision.model}</small> : null}
              </span>
            </div>
            {selected.review && (
              <div className="review-meta-row">
                <span className="review-meta-label">Reviewed</span>
                <span>
                  {formatDateTime(selected.review.reviewedAt)}
                  {selected.review.reviewedBy ? (
                    <small className="mono"> by {selected.review.reviewedBy}</small>
                  ) : null}
                </span>
              </div>
            )}
            {selected.review?.note && (
              <div className="review-meta-row note-row">
                <span className="review-meta-label">Review note</span>
                <span className="review-note-bubble">{selected.review.note}</span>
              </div>
            )}
          </div>

          <section className="doc-section">
            <div className="doc-section-head">
              <h3>Photo verdict vs seller text</h3>
            </div>
            <div className="flag-compare">
              <div className="flag-compare-col">
                <span className="flag-compare-label">Photo shows</span>
                {selected.image ? (
                  <img className="flag-shot" src={selected.image} alt={selected.name} />
                ) : (
                  <span className="flag-shot flag-thumb-empty">
                    <IconBox size={22} />
                  </span>
                )}
                <p>{selected.vision.summary || '—'}</p>
                {selected.vision.labels.length > 0 && (
                  <p className="flag-labels mono">{selected.vision.labels.join(' · ')}</p>
                )}
                <p className="warn-text">
                  <IconAlertTriangle size={13} />{' '}
                  {selected.vision.mismatch.reason || 'Photo does not match the description.'}
                </p>
              </div>
              <div className="flag-compare-col">
                <span className="flag-compare-label">Seller claims</span>
                <p>{selected.description || '—'}</p>
              </div>
            </div>
          </section>

          <section className="doc-section">
            <div className="doc-section-head">
              <h3>Decision</h3>
            </div>
            <div className="field">
              <label className="field-label" htmlFor="flag-note">
                Review note
              </label>
              <textarea
                id="flag-note"
                className="input textarea"
                value={note}
                maxLength={1000}
                onChange={(e) => setNote(e.target.value)}
                placeholder="e.g. Photo is a stock living-room shot — the wallpaper itself is never shown."
              />
              <span className="field-hint">Optional. Saved with the decision for the audit trail.</span>
            </div>
          </section>

          <div className="modal-actions">
            <button className="btn btn-secondary" onClick={closeDetail} disabled={busy !== null}>
              Cancel
            </button>
            {isOpen(selected) ? (
              <button
                className="btn btn-primary"
                onClick={() => void decide('resolved')}
                disabled={busy !== null}
                aria-busy={busy === 'resolve'}
              >
                {busy === 'resolve' ? (
                  <>
                    <span className="spinner spinner-inline" />
                    Saving…
                  </>
                ) : (
                  'Resolve flag'
                )}
              </button>
            ) : (
              <button
                className="btn btn-danger"
                onClick={() => void decide('open')}
                disabled={busy !== null}
                aria-busy={busy === 'reopen'}
              >
                {busy === 'reopen' ? (
                  <>
                    <span className="spinner spinner-inline" />
                    Saving…
                  </>
                ) : (
                  <>
                    <IconX size={14} />
                    Reopen flag
                  </>
                )}
              </button>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
