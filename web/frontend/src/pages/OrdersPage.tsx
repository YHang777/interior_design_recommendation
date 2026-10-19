import { useCallback, useEffect, useMemo, useState } from 'react';
import { ordersApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminOrderDetail, AdminOrderRow, AdminOrderStatus } from '../api/types';
import { OrderStatusBadge } from '../components/Badge';
import { DataTable, type Column, type SortState } from '../components/DataTable';
import { Modal } from '../components/Modal';
import { IconBag, IconDownload, IconRefresh, IconX } from '../components/icons';
import { downloadInvoice } from '../lib/invoicePdf';
import { useToast } from '../state/ToastContext';

const PAGE_SIZE = 25;

type StatusFilter = AdminOrderStatus | '';

const STATUS_CHIPS: { value: StatusFilter; label: string }[] = [
  { value: '', label: 'All' },
  { value: 'pending', label: 'Pending' },
  { value: 'confirmed', label: 'Confirmed' },
  { value: 'shipped', label: 'Shipped' },
  { value: 'delivered', label: 'Delivered' },
  { value: 'cancelled', label: 'Cancelled' },
];

const NEXT_LABEL: Partial<Record<AdminOrderStatus, string>> = {
  confirmed: 'Confirmed',
  shipped: 'Shipped',
  delivered: 'Delivered',
};

const STATUS_NAME: Record<AdminOrderStatus, string> = {
  pending: 'Pending',
  confirmed: 'Confirmed',
  shipped: 'Shipped',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
};

function formatPrice(price: number): string {
  return `RM ${price.toLocaleString()}`;
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

function describeOrdersError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Could not load orders.';
  switch (err.code) {
    case 'UNAUTHENTICATED':
      return 'Session expired. Sign in again.';
    case 'NOT_ADMIN':
      return 'Admin access required.';
    case 'NETWORK_ERROR':
      return 'Cannot reach the admin API.';
    case 'ORDER_NOT_FOUND':
      return 'Order not found.';
    case 'ORDER_INVALID_TRANSITION':
      return err.message;
    case 'VALIDATION_ERROR':
      return err.message;
    default:
      return err.message || `Request failed (${err.status}).`;
  }
}

export function OrdersPage({ query }: { query: string }) {
  const { push } = useToast();

  const [status, setStatus] = useState<StatusFilter>('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [offset, setOffset] = useState(0);
  const [sort, setSort] = useState<SortState | null>(null);
  const [rows, setRows] = useState<AdminOrderRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  const [selected, setSelected] = useState<AdminOrderDetail | null>(null);
  const [busy, setBusy] = useState<AdminOrderStatus | null>(null);
  const [confirmCancel, setConfirmCancel] = useState(false);

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedQuery(query.trim()), 300);
    return () => window.clearTimeout(t);
  }, [query]);

  useEffect(() => {
    setOffset(0);
  }, [debouncedQuery, status]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await ordersApi.list({
        status: status || undefined,
        q: debouncedQuery || undefined,
        limit: PAGE_SIZE,
        offset,
      });
      setRows(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(describeOrdersError(err));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [debouncedQuery, status, offset]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const refresh = () => setReloadKey((k) => k + 1);

  const openDetail = async (row: AdminOrderRow) => {
    try {
      const { order } = await ordersApi.get(row.orderId);
      setSelected(order);
      setConfirmCancel(false);
    } catch (err) {
      push('error', describeOrdersError(err));
    }
  };

  const advance = async (next: AdminOrderStatus) => {
    if (!selected || busy) return;
    setBusy(next);
    try {
      const { order } = await ordersApi.setStatus(selected.orderId, next);
      setSelected(order);
      push('success', `Order → ${STATUS_NAME[next]}.`);
      refresh();
    } catch (err) {
      push('error', describeOrdersError(err));
    } finally {
      setBusy(null);
    }
  };

  const columns = useMemo<Column<AdminOrderRow>[]>(
    () => [
      {
        key: 'order',
        header: 'Order',
        sortValue: (r) => r.orderNumber.toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span>{r.orderNumber || r.orderId}</span>
            <small className="mono">{r.orderId}</small>
          </div>
        ),
      },
      {
        key: 'customer',
        header: 'Customer',
        sortValue: (r) => r.customerName.toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span>{r.customerName || '—'}</span>
            <small className="mono">{r.customerId}</small>
          </div>
        ),
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (r) => r.status,
        render: (r) => <OrderStatusBadge status={r.status} />,
        width: '120px',
      },
      {
        key: 'items',
        header: 'Items',
        sortValue: (r) => r.itemCount,
        render: (r) => r.itemCount,
        width: '70px',
        align: 'right',
      },
      {
        key: 'total',
        header: 'Total',
        sortValue: (r) => r.total,
        render: (r) => formatPrice(r.total),
        width: '110px',
        align: 'right',
      },
      {
        key: 'placed',
        header: 'Placed',
        sortValue: (r) => r.createdAt ?? '',
        render: (r) => formatDateTime(r.createdAt),
        width: '170px',
      },
      {
        key: 'actions',
        header: 'Actions',
        align: 'right',
        width: '100px',
        render: (r) => (
          <div className="row-actions">
            <button className="btn-mini" onClick={() => void openDetail(r)}>
              View
            </button>
          </div>
        ),
      },
    ],
    []
  );

  const sortedRows = useMemo(() => {
    if (!sort) return rows;
    const col = columns.find((c) => c.key === sort.key);
    if (!col?.sortValue) return rows;
    const get = col.sortValue;
    const dir = sort.dir === 'asc' ? 1 : -1;
    return [...rows].sort((a, b) => {
      const va = get(a);
      const vb = get(b);
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * dir;
      return String(va).localeCompare(String(vb), undefined, { numeric: true }) * dir;
    });
  }, [rows, sort, columns]);

  const onSortChange = (key: string) => {
    setSort((prev) => (prev?.key === key ? (prev.dir === 'asc' ? { key, dir: 'desc' } : null) : { key, dir: 'asc' }));
  };

  const hasFilters = Boolean(debouncedQuery || status);
  const from = total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + PAGE_SIZE, total);

  const isTerminal = selected ? selected.status === 'delivered' || selected.status === 'cancelled' : true;

  const invoiceBtn = selected ? (
    <button className="btn btn-secondary" onClick={() => downloadInvoice(selected)} disabled={busy !== null}>
      <IconDownload size={14} />
      Download invoice
    </button>
  ) : null;

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Orders</h2>
          <p className="subtitle">All marketplace orders.</p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={refresh} disabled={loading}>
          <IconRefresh size={14} />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      <div className="toolbar">
        <div className="filter-group" role="group" aria-label="Filter by status">
          <span className="filter-label">Status</span>
          <div className="chip-group">
            {STATUS_CHIPS.map((c) => (
              <button
                key={c.value || 'all'}
                className="chip"
                aria-pressed={status === c.value}
                onClick={() => setStatus(c.value)}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>
        {hasFilters && (
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => {
              setStatus('');
            }}
          >
            <IconX size={13} />
            Clear filters
          </button>
        )}
      </div>

      <section className="panel">
        <DataTable
          columns={columns}
          rows={sortedRows}
          rowKey={(r) => r.orderId}
          loading={loading}
          error={error}
          onRetry={() => void load()}
          sort={sort}
          onSortChange={onSortChange}
          emptyMessage={hasFilters ? 'No orders match.' : 'No orders yet.'}
        />
        <div className="panel-footer">
          <span>
            {from}–{to} of {total.toLocaleString()}
          </span>
          <div className="pager">
            <button
              className="btn btn-secondary btn-sm"
              disabled={offset === 0 || loading}
              onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
            >
              Previous
            </button>
            <button
              className="btn btn-secondary btn-sm"
              disabled={offset + PAGE_SIZE >= total || loading}
              onClick={() => setOffset(offset + PAGE_SIZE)}
            >
              Next
            </button>
          </div>
        </div>
      </section>

      {selected && (
        <Modal
          title={selected.orderNumber || selected.orderId}
          onClose={() => !busy && (setSelected(null), setConfirmCancel(false))}
          headerIcon={<IconBag size={18} />}
          width={640}
        >
          <div className="review-meta">
            <div className="review-meta-row">
              <span className="review-meta-label">Status</span>
              <OrderStatusBadge status={selected.status} />
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">Customer</span>
              <span>
                {selected.customerName || '—'} <small className="mono">{selected.customerEmail || selected.customerId}</small>
              </span>
            </div>
            {selected.customerPhone && (
              <div className="review-meta-row">
                <span className="review-meta-label">Phone</span>
                <span>{selected.customerPhone}</span>
              </div>
            )}
            {selected.shippingAddress && (
              <div className="review-meta-row">
                <span className="review-meta-label">Ship to</span>
                <span>{selected.shippingAddress}</span>
              </div>
            )}
            <div className="review-meta-row">
              <span className="review-meta-label">Placed</span>
              <span>
                {formatDateTime(selected.createdAt)} · {selected.paymentMethod || '—'}
              </span>
            </div>
          </div>

          <section className="doc-section">
            <div className="doc-section-head">
              <h3>Items</h3>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Product</th>
                  <th style={{ textAlign: 'right' }}>Qty</th>
                  <th style={{ textAlign: 'right' }}>Unit</th>
                  <th style={{ textAlign: 'right' }}>Line</th>
                </tr>
              </thead>
              <tbody>
                {selected.items.map((item, i) => (
                  <tr key={`${item.productId}-${i}`}>
                    <td>{item.name}</td>
                    <td style={{ textAlign: 'right' }}>{item.quantity}</td>
                    <td style={{ textAlign: 'right' }}>{formatPrice(item.unitPrice)}</td>
                    <td style={{ textAlign: 'right' }}>{formatPrice(item.unitPrice * item.quantity)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>

          <section className="doc-section">
            <div className="doc-section-head">
              <h3>Payment</h3>
            </div>
            <div className="review-meta">
              <div className="review-meta-row">
                <span className="review-meta-label">Subtotal</span>
                <span>{formatPrice(selected.subtotal)}</span>
              </div>
              <div className="review-meta-row">
                <span className="review-meta-label">Shipping</span>
                <span>{formatPrice(selected.shippingFee)}</span>
              </div>
              {selected.discount > 0 && (
                <div className="review-meta-row">
                  <span className="review-meta-label">Discount</span>
                  <span>−{formatPrice(selected.discount)}</span>
                </div>
              )}
              {selected.tax > 0 && (
                <div className="review-meta-row">
                  <span className="review-meta-label">Tax</span>
                  <span>{formatPrice(selected.tax)}</span>
                </div>
              )}
              <div className="review-meta-row">
                <span className="review-meta-label">Total</span>
                <strong>{formatPrice(selected.total)}</strong>
              </div>
            </div>
          </section>

          <section className="doc-section">
            <div className="doc-section-head">
              <h3>History</h3>
            </div>
            <div className="review-meta">
              {Object.entries(selected.statusHistory)
                .sort((a, b) => a[1].localeCompare(b[1]))
                .map(([name, at]) => (
                  <div className="review-meta-row" key={name}>
                    <span className="review-meta-label">{name}</span>
                    <span>{formatDateTime(at)}</span>
                  </div>
                ))}
            </div>
          </section>

          {!isTerminal && !confirmCancel && (
            <div className="modal-actions">
              <button className="btn btn-secondary" onClick={() => (setSelected(null), setConfirmCancel(false))} disabled={busy !== null}>
                Close
              </button>
              {invoiceBtn}
              <button className="btn btn-danger-outline" onClick={() => setConfirmCancel(true)} disabled={busy !== null}>
                Cancel order
              </button>
              {selected.nextStatuses
                .map((next) => ({ next, label: NEXT_LABEL[next] }))
                .filter((entry): entry is { next: AdminOrderStatus; label: string } => Boolean(entry.label))
                .map(({ next, label }) => (
                  <button
                    key={next}
                    className="btn btn-primary"
                    onClick={() => void advance(next)}
                    disabled={busy !== null}
                    aria-busy={busy === next}
                  >
                    {busy === next ? (
                      <>
                        <span className="spinner spinner-inline" />
                        Saving…
                      </>
                    ) : (
                      label
                    )}
                  </button>
                ))}
            </div>
          )}

          {!isTerminal && confirmCancel && (
            <div className="modal-actions">
              <span style={{ marginRight: 'auto', color: 'var(--text-muted)' }}>
                Stock returns to sellers.
              </span>
              {invoiceBtn}
              <button className="btn btn-secondary" onClick={() => setConfirmCancel(false)} disabled={busy !== null}>
                Keep order
              </button>
              <button
                className="btn btn-danger"
                onClick={() => void advance('cancelled')}
                disabled={busy !== null}
                aria-busy={busy === 'cancelled'}
              >
                {busy === 'cancelled' ? (
                  <>
                    <span className="spinner spinner-inline" />
                    Cancelling…
                  </>
                ) : (
                  'Cancel order'
                )}
              </button>
            </div>
          )}

          {isTerminal && (
            <div className="modal-actions">
              {invoiceBtn}
              <button className="btn btn-secondary" onClick={() => setSelected(null)}>
                Close
              </button>
            </div>
          )}
        </Modal>
      )}
    </div>
  );
}
