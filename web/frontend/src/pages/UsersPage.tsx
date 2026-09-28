import { useCallback, useEffect, useMemo, useState } from 'react';
import { usersApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminUserRow, VerificationStatus } from '../api/types';
import { RoleBadge, StatusBadge } from '../components/Badge';
import { DataTable, type Column, type SortState } from '../components/DataTable';
import { DeleteUserDialog } from '../components/DeleteUserDialog';
import { PasswordResetModal } from '../components/PasswordResetModal';
import { IconRefresh, IconX } from '../components/icons';
import { useToast } from '../state/ToastContext';

const PAGE_SIZE = 25;

type RoleFilter = 'all' | 'homeowner' | 'supplier';

interface Props {
  /** Initial role scope — 'all' unless the page is suppliers-specific. */
  role: RoleFilter;
  /** Show the role chip group (the all/customers/suppliers switcher). */
  showRoleChips?: boolean;
  /** Global search from the topbar — filters this table. */
  query: string;
  onQueryChange: (value: string) => void;
}

const ROLE_CHIPS: { value: RoleFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'homeowner', label: 'Customers' },
  { value: 'supplier', label: 'Suppliers' },
];

const STATUS_CHIPS: { value: VerificationStatus | ''; label: string }[] = [
  { value: '', label: 'Any status' },
  { value: 'verified', label: 'Verified' },
  { value: 'pending', label: 'Pending' },
  { value: 'rejected', label: 'Rejected' },
];

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

const ROLE_SUBTITLE: Record<RoleFilter, string> = {
  all: 'Every account in the marketplace — customers, suppliers and auth-only users. Manage passwords and guarded deletion from any row.',
  homeowner: 'Homeowner accounts: monitor activity, help with passwords, delete accounts.',
  supplier:
    'Approve or reject sellers; their status drives the marketplace’s “Verified sellers only” filter.',
};

const ROLE_HEADING: Record<RoleFilter, string> = {
  all: 'All accounts',
  homeowner: 'Customer accounts',
  supplier: 'Supplier accounts',
};

/**
 * Directory table: global (topbar) search, role + status filter chips,
 * sortable columns, server paging, verification actions, password help and
 * guarded deletion.
 */
export function UsersPage({ role, showRoleChips = false, query, onQueryChange }: Props) {
  const isSupplierScope = role === 'supplier';
  const { push } = useToast();

  const [roleFilter, setRoleFilter] = useState<RoleFilter>(role);
  const [status, setStatus] = useState<VerificationStatus | ''>('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [offset, setOffset] = useState(0);
  const [sort, setSort] = useState<SortState | null>(null);
  const [rows, setRows] = useState<AdminUserRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyUid, setBusyUid] = useState<string | null>(null);
  const [dialog, setDialog] = useState<{ type: 'reset' | 'delete'; user: AdminUserRow } | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  // Debounce the global search box.
  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedQuery(query.trim()), 300);
    return () => window.clearTimeout(t);
  }, [query]);

  // New filters restart paging (but not while only sorting changed).
  useEffect(() => {
    setOffset(0);
  }, [debouncedQuery, status, roleFilter]);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await usersApi.list({
        role: roleFilter,
        status: status || undefined,
        q: debouncedQuery || undefined,
        limit: PAGE_SIZE,
        offset,
      });
      setRows(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Failed to load users.');
      setRows([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [roleFilter, status, debouncedQuery, offset]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const refresh = () => setReloadKey((k) => k + 1);

  const setVerification = async (user: AdminUserRow, next: VerificationStatus) => {
    if (busyUid) return;
    setBusyUid(user.uid);
    try {
      const result = await usersApi.setVerification(user.uid, next);
      push(
        'success',
        `${user.email} → ${next}${result.productsSynced ? ` (${result.productsSynced} listing${result.productsSynced === 1 ? '' : 's'} synced)` : ''}`
      );
      refresh();
    } catch (err) {
      push('error', err instanceof ApiError ? err.message : 'Verification update failed.');
    } finally {
      setBusyUid(null);
    }
  };

  const columns = useMemo<Column<AdminUserRow>[]>(() => {
    const base: Column<AdminUserRow>[] = [
      {
        key: 'name',
        header: isSupplierScope ? 'Business / name' : 'Name',
        sortValue: (u) => (u.businessName || u.name || u.email).toLowerCase(),
        render: (u) => (
          <div className="cell-primary">
            <span>{u.businessName || u.name || '—'}</span>
            {isSupplierScope && u.name && u.businessName && u.businessName !== u.name && (
              <small>{u.name}</small>
            )}
            {!u.profileExists && <small className="warn-text">No profile document</small>}
          </div>
        ),
      },
      {
        key: 'email',
        header: 'Email',
        sortValue: (u) => u.email.toLowerCase(),
        render: (u) => <span className="mono">{u.email}</span>,
      },
      {
        key: 'role',
        header: 'Role',
        sortValue: (u) => u.role,
        render: (u) => <RoleBadge role={u.role} />,
        width: '110px',
      },
      {
        key: 'status',
        header: 'Status',
        sortValue: (u) => u.verificationStatus,
        render: (u) => <StatusBadge status={u.verificationStatus} />,
        width: '120px',
      },
      {
        key: 'created',
        header: 'Joined',
        sortValue: (u) => u.createdAt ?? '',
        render: (u) => formatDate(u.createdAt),
        width: '110px',
      },
      {
        key: 'orders',
        header: 'Orders',
        sortValue: (u) => u.orderCount,
        render: (u) => u.orderCount.toLocaleString(),
        width: '80px',
        align: 'right',
      },
    ];
    if (isSupplierScope) {
      base.splice(5, 0, {
        key: 'products',
        header: 'Products',
        sortValue: (u) => u.productCount,
        render: (u) => u.productCount.toLocaleString(),
        width: '90px',
        align: 'right',
      });
    }
    base.push({
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (u) => {
        const busy = busyUid === u.uid;
        const canVerify = roleFilter !== 'homeowner' && u.profileExists && u.role === 'supplier';
        return (
          <div className="row-actions">
            {canVerify && u.verificationStatus !== 'verified' && (
              <button className="btn-mini btn-verify" disabled={busy} onClick={() => void setVerification(u, 'verified')}>
                Verify
              </button>
            )}
            {canVerify && u.verificationStatus !== 'pending' && (
              <button className="btn-mini btn-pending" disabled={busy} onClick={() => void setVerification(u, 'pending')}>
                Set pending
              </button>
            )}
            {canVerify && u.verificationStatus !== 'rejected' && (
              <button className="btn-mini btn-reject" disabled={busy} onClick={() => void setVerification(u, 'rejected')}>
                Reject
              </button>
            )}
            <button className="btn-mini" onClick={() => setDialog({ type: 'reset', user: u })}>
              Password
            </button>
            <button className="btn-mini btn-danger-outline" onClick={() => setDialog({ type: 'delete', user: u })}>
              Delete
            </button>
          </div>
        );
      },
    });
    return base;
  }, [isSupplierScope, roleFilter, busyUid]);

  // Client-side sort of the current page's rows.
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

  const clearFilters = () => {
    onQueryChange('');
    setStatus('');
    setRoleFilter(role);
    setSort(null);
  };

  const hasFilters = Boolean(debouncedQuery || status || (showRoleChips && roleFilter !== role));
  const from = total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + PAGE_SIZE, total);
  const noun = roleFilter === 'homeowner' ? 'customers' : roleFilter === 'supplier' ? 'suppliers' : 'users';

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>{ROLE_HEADING[roleFilter]}</h2>
          <p className="subtitle">{ROLE_SUBTITLE[roleFilter]}</p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={refresh} disabled={loading}>
          <IconRefresh size={14} />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      <div className="toolbar">
        {showRoleChips && (
          <div className="filter-group" role="group" aria-label="Filter by role">
            <span className="filter-label">Role</span>
            <div className="chip-group">
              {ROLE_CHIPS.map((c) => (
                <button
                  key={c.value}
                  className="chip"
                  aria-pressed={roleFilter === c.value}
                  onClick={() => setRoleFilter(c.value)}
                >
                  {c.label}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="filter-group" role="group" aria-label="Filter by verification status">
          <span className="filter-label">Status</span>
          <div className="chip-group">
            {STATUS_CHIPS.map((c) => (
              <button
                key={c.value || 'any'}
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
          <button className="btn btn-ghost btn-sm" onClick={clearFilters}>
            <IconX size={13} />
            Clear filters
          </button>
        )}
      </div>

      <section className="panel">
        <DataTable
          columns={columns}
          rows={sortedRows}
          rowKey={(u) => u.uid}
          loading={loading}
          error={error}
          onRetry={() => void load()}
          sort={sort}
          onSortChange={onSortChange}
          emptyMessage={
            hasFilters ? `No ${noun} match the current filters.` : `No ${noun} yet.`
          }
        />
        <div className="panel-footer">
          <span>
            {from}–{to} of {total.toLocaleString()}
            {sort ? ' · sorted' : ''}
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

      {dialog?.type === 'reset' && <PasswordResetModal user={dialog.user} onClose={() => setDialog(null)} />}
      {dialog?.type === 'delete' && (
        <DeleteUserDialog
          user={dialog.user}
          onClose={() => setDialog(null)}
          onDeleted={(email) => {
            setDialog(null);
            push('success', `Deleted ${email}.`);
            refresh();
          }}
        />
      )}
    </div>
  );
}
