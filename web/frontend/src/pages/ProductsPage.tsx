import { useCallback, useEffect, useMemo, useState } from 'react';
import { productsApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminProductDetail, AdminProductRow } from '../api/types';
import { DataTable, type Column, type SortState } from '../components/DataTable';
import { Modal } from '../components/Modal';
import { IconBox, IconRefresh, IconTrash, IconX } from '../components/icons';
import { useToast } from '../state/ToastContext';

const PAGE_SIZE = 25;

const CATEGORIES = [
  'Furniture',
  'Lighting',
  'Decor',
  'Paint',
  'Flooring',
  'Textiles',
  'Wall Covering',
];

const STYLES = ['Modern', 'Classic', 'Industrial', 'Scandinavian', 'Bohemian', 'Minimalist'];

type StatusFilter = 'all' | 'active' | 'inactive';

const STATUS_CHIPS: { value: StatusFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
];

function formatPrice(price: number): string {
  return `RM ${price.toLocaleString()}`;
}

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

function describeProductsError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Could not load products.';
  switch (err.code) {
    case 'UNAUTHENTICATED':
      return 'Session expired. Sign in again.';
    case 'NOT_ADMIN':
      return 'Admin access required.';
    case 'NETWORK_ERROR':
      return 'Cannot reach the admin API.';
    case 'VALIDATION_ERROR':
      return err.message;
    default:
      return err.message || `Request failed (${err.status}).`;
  }
}

interface EditForm {
  name: string;
  description: string;
  category: string;
  designStyle: string;
  price: string;
  originalPrice: string;
  stock: string;
  isActive: boolean;
  isEcoFriendly: boolean;
  shippingEnabled: boolean;
  shippingFee: string;
  shippingLongDistanceNotice: boolean;
}

function toForm(d: AdminProductDetail): EditForm {
  return {
    name: d.name,
    description: d.description,
    category: d.category,
    designStyle: d.designStyle,
    price: String(d.price),
    originalPrice: d.originalPrice === null ? '' : String(d.originalPrice),
    stock: String(d.stock),
    isActive: d.isActive,
    isEcoFriendly: d.isEcoFriendly,
    shippingEnabled: d.shippingEnabled,
    shippingFee: String(d.shippingFee),
    shippingLongDistanceNotice: d.shippingLongDistanceNotice,
  };
}

export function ProductsPage({ query }: { query: string }) {
  const { push } = useToast();

  const [status, setStatus] = useState<StatusFilter>('all');
  const [category, setCategory] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [offset, setOffset] = useState(0);
  const [sort, setSort] = useState<SortState | null>(null);
  const [rows, setRows] = useState<AdminProductRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  const [editing, setEditing] = useState<AdminProductDetail | null>(null);
  const [form, setForm] = useState<EditForm | null>(null);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState<AdminProductRow | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);

  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedQuery(query.trim()), 300);
    return () => window.clearTimeout(t);
  }, [query]);

  useEffect(() => {
    setOffset(0);
  }, [debouncedQuery, status, category]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await productsApi.list({
        q: debouncedQuery || undefined,
        category: category || undefined,
        status,
        limit: PAGE_SIZE,
        offset,
      });
      setRows(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(describeProductsError(err));
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [debouncedQuery, category, status, offset]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const refresh = () => setReloadKey((k) => k + 1);

  const openEdit = async (row: AdminProductRow) => {
    try {
      const { product } = await productsApi.get(row.productId);
      setEditing(product);
      setForm(toForm(product));
    } catch (err) {
      push('error', describeProductsError(err));
    }
  };

  const save = async () => {
    if (!editing || !form || saving) return;
    setSaving(true);
    try {
      const price = Number(form.price);
      const stock = Number(form.stock);
      const shippingFee = Number(form.shippingFee);
      const originalPrice = form.originalPrice.trim() === '' ? null : Number(form.originalPrice);
      await productsApi.update(editing.productId, {
        name: form.name.trim(),
        description: form.description.trim(),
        category: form.category,
        designStyle: form.designStyle,
        price: Math.round(price),
        originalPrice: originalPrice === null ? null : Math.round(originalPrice),
        stock: Math.round(stock),
        isActive: form.isActive,
        isEcoFriendly: form.isEcoFriendly,
        shippingEnabled: form.shippingEnabled,
        shippingFee: Math.max(0, Math.round(shippingFee)),
        shippingLongDistanceNotice: form.shippingLongDistanceNotice,
      });
      push('success', 'Product saved.');
      setEditing(null);
      setForm(null);
      refresh();
    } catch (err) {
      push('error', describeProductsError(err));
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!deleting || deleteBusy) return;
    setDeleteBusy(true);
    try {
      await productsApi.remove(deleting.productId);
      push('success', 'Product deleted.');
      setDeleting(null);
      refresh();
    } catch (err) {
      push('error', describeProductsError(err));
    } finally {
      setDeleteBusy(false);
    }
  };

  const columns = useMemo<Column<AdminProductRow>[]>(
    () => [
      {
        key: 'listing',
        header: 'Product',
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
              <small className="mono">{r.productId}</small>
            </span>
          </div>
        ),
      },
      {
        key: 'category',
        header: 'Category',
        sortValue: (r) => r.category.toLowerCase(),
        render: (r) => (
          <div className="cell-primary">
            <span>{r.category || '—'}</span>
            <small>{r.designStyle || '—'}</small>
          </div>
        ),
        width: '150px',
      },
      {
        key: 'price',
        header: 'Price',
        sortValue: (r) => r.price,
        render: (r) => (
          <div className="cell-primary">
            <span>{formatPrice(r.price)}</span>
            {r.originalPrice !== null && r.originalPrice > r.price && (
              <small>
                <s>{formatPrice(r.originalPrice)}</s>
              </small>
            )}
          </div>
        ),
        width: '120px',
      },
      {
        key: 'stock',
        header: 'Stock',
        sortValue: (r) => r.stock,
        render: (r) => <span className={r.stock <= 0 ? 'warn-text' : undefined}>{r.stock}</span>,
        width: '80px',
        align: 'right',
      },
      {
        key: 'rating',
        header: 'Rating',
        sortValue: (r) => r.rating,
        render: (r) => `${r.rating.toFixed(1)} (${r.ratingCount})`,
        width: '110px',
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (r) => (r.isActive ? 'active' : 'inactive'),
        render: (r) => (
          <span className={`badge badge-status-${r.isActive ? 'verified' : 'unknown'}`}>
            {r.isActive ? 'Active' : 'Inactive'}
          </span>
        ),
        width: '100px',
      },
      {
        key: 'created',
        header: 'Added',
        sortValue: (r) => r.createdAt ?? '',
        render: (r) => formatDate(r.createdAt),
        width: '110px',
      },
      {
        key: 'actions',
        header: 'Actions',
        align: 'right',
        width: '120px',
        render: (r) => (
          <div className="row-actions">
            <button className="btn-mini" onClick={() => void openEdit(r)}>
              Edit
            </button>
            <button className="btn-mini btn-danger-outline" onClick={() => setDeleting(r)}>
              Delete
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

  const hasFilters = Boolean(debouncedQuery || status !== 'all' || category);
  const from = total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + PAGE_SIZE, total);

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Products</h2>
          <p className="subtitle">All marketplace listings.</p>
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
                key={c.value}
                className="chip"
                aria-pressed={status === c.value}
                onClick={() => setStatus(c.value)}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>
        <div className="filter-group" role="group" aria-label="Filter by category">
          <span className="filter-label">Category</span>
          <div className="chip-group">
            <button className="chip" aria-pressed={category === ''} onClick={() => setCategory('')}>
              All
            </button>
            {CATEGORIES.map((c) => (
              <button
                key={c}
                className="chip"
                aria-pressed={category === c}
                onClick={() => setCategory(c)}
              >
                {c}
              </button>
            ))}
          </div>
        </div>
        {hasFilters && (
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => {
              setStatus('all');
              setCategory('');
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
          rowKey={(r) => r.productId}
          loading={loading}
          error={error}
          onRetry={() => void load()}
          sort={sort}
          onSortChange={onSortChange}
          emptyMessage={hasFilters ? 'No products match.' : 'No products yet.'}
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

      {editing && form && (
        <Modal title={editing.name || 'Edit product'} onClose={() => !saving && (setEditing(null), setForm(null))} width={640}>
          <div className="form-grid">
            <div className="field">
              <label className="field-label" htmlFor="p-name">Name</label>
              <input id="p-name" className="input" value={form.name} maxLength={200} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-category">Category</label>
              <select id="p-category" className="input" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>{c}</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-style">Style</label>
              <select id="p-style" className="input" value={form.designStyle} onChange={(e) => setForm({ ...form, designStyle: e.target.value })}>
                {STYLES.map((s) => (
                  <option key={s} value={s}>{s}</option>
                ))}
              </select>
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-price">Price (RM)</label>
              <input id="p-price" className="input" type="number" min={0} value={form.price} onChange={(e) => setForm({ ...form, price: e.target.value })} />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-original">Original price (RM)</label>
              <input id="p-original" className="input" type="number" min={0} placeholder="None" value={form.originalPrice} onChange={(e) => setForm({ ...form, originalPrice: e.target.value })} />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-stock">Stock</label>
              <input id="p-stock" className="input" type="number" min={0} value={form.stock} onChange={(e) => setForm({ ...form, stock: e.target.value })} />
            </div>
            <div className="field field-span">
              <label className="field-label" htmlFor="p-desc">Description</label>
              <textarea id="p-desc" className="input textarea" rows={4} value={form.description} maxLength={4000} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="p-shipfee">Shipping fee (RM)</label>
              <input id="p-shipfee" className="input" type="number" min={0} value={form.shippingFee} onChange={(e) => setForm({ ...form, shippingFee: e.target.value })} />
            </div>
            <div className="field checkbox-field">
              <label>
                <input type="checkbox" checked={form.isActive} onChange={(e) => setForm({ ...form, isActive: e.target.checked })} />
                Active
              </label>
              <label>
                <input type="checkbox" checked={form.isEcoFriendly} onChange={(e) => setForm({ ...form, isEcoFriendly: e.target.checked })} />
                Eco-friendly
              </label>
              <label>
                <input type="checkbox" checked={form.shippingEnabled} onChange={(e) => setForm({ ...form, shippingEnabled: e.target.checked })} />
                Shipping enabled
              </label>
              <label>
                <input type="checkbox" checked={form.shippingLongDistanceNotice} onChange={(e) => setForm({ ...form, shippingLongDistanceNotice: e.target.checked })} />
                Long-distance notice
              </label>
            </div>
          </div>

          <div className="review-meta" style={{ marginTop: 16 }}>
            <div className="review-meta-row">
              <span className="review-meta-label">Rating</span>
              <span>{editing.rating.toFixed(1)} ({editing.ratingCount})</span>
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">Supplier</span>
              <span>{editing.supplierName || '—'} <small className="mono">{editing.supplierId}</small></span>
            </div>
            <div className="review-meta-row">
              <span className="review-meta-label">3D model</span>
              <span>{editing.ar3dStatus}</span>
            </div>
            {editing.visionFlagged && (
              <div className="review-meta-row">
                <span className="review-meta-label">Photo flag</span>
                <span className="warn-text">Flagged</span>
              </div>
            )}
          </div>

          <div className="modal-actions">
            <button className="btn btn-secondary" onClick={() => (setEditing(null), setForm(null))} disabled={saving}>
              Cancel
            </button>
            <button className="btn btn-primary" onClick={() => void save()} disabled={saving} aria-busy={saving}>
              {saving ? (
                <>
                  <span className="spinner spinner-inline" />
                  Saving…
                </>
              ) : (
                'Save'
              )}
            </button>
          </div>
        </Modal>
      )}

      {deleting && (
        <Modal title="Delete product?" onClose={() => !deleteBusy && setDeleting(null)} tone="danger" headerIcon={<IconTrash size={18} />} width={440}>
          <p>
            <strong>{deleting.name || deleting.productId}</strong> will be removed from the
            marketplace. Past orders keep their records.
          </p>
          <div className="modal-actions">
            <button className="btn btn-secondary" onClick={() => setDeleting(null)} disabled={deleteBusy}>
              Cancel
            </button>
            <button className="btn btn-danger" onClick={() => void remove()} disabled={deleteBusy} aria-busy={deleteBusy}>
              {deleteBusy ? (
                <>
                  <span className="spinner spinner-inline" />
                  Deleting…
                </>
              ) : (
                'Delete'
              )}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
