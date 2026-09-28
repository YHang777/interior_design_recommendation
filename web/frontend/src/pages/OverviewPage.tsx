import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { statsApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminStats } from '../api/types';
import { RoleBadge, StatusBadge } from '../components/Badge';
import {
  IconAlertTriangle,
  IconBag,
  IconBox,
  IconRefresh,
  IconShield,
  IconStore,
  IconUsers,
  IconXCircle,
} from '../components/icons';

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString();
}

interface Kpi {
  key: string;
  label: string;
  value: number;
  hint: string;
  tone: 'accent' | 'success' | 'warning' | 'danger' | 'neutral';
  icon: ReactNode;
  /** When true the tile is visually flagged (attention state). */
  attention?: boolean;
}

function buildKpis(stats: AdminStats): Kpi[] {
  return [
    {
      key: 'customers',
      label: 'Customers',
      value: stats.customers,
      hint: 'Homeowner accounts',
      tone: 'accent',
      icon: <IconUsers size={17} />,
    },
    {
      key: 'suppliers',
      label: 'Suppliers',
      value: stats.suppliers,
      hint: 'Seller accounts',
      tone: 'success',
      icon: <IconStore size={17} />,
    },
    {
      key: 'pending',
      label: 'Pending approvals',
      value: stats.pendingSuppliers,
      hint: 'Awaiting verification',
      tone: 'warning',
      icon: <IconAlertTriangle size={17} />,
      attention: stats.pendingSuppliers > 0,
    },
    {
      key: 'rejected',
      label: 'Rejected suppliers',
      value: stats.rejectedSuppliers,
      hint: 'Blocked from the marketplace',
      tone: 'danger',
      icon: <IconXCircle size={17} />,
    },
    {
      key: 'verificationQueue',
      label: 'IC applications',
      value: stats.pendingVerifications,
      hint: 'Identity uploads awaiting review',
      tone: 'accent',
      icon: <IconShield size={17} />,
      attention: stats.pendingVerifications > 0,
    },
    {
      key: 'products',
      label: 'Products',
      value: stats.products,
      hint: 'Active listings',
      tone: 'neutral',
      icon: <IconBox size={17} />,
    },
    {
      key: 'orders',
      label: 'Orders',
      value: stats.orders,
      hint: 'Placed to date',
      tone: 'neutral',
      icon: <IconBag size={17} />,
    },
  ];
}

export function OverviewPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setStats(await statsApi.get());
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Failed to load stats.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const kpis = stats ? buildKpis(stats) : [];

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Marketplace health at a glance</h2>
          <p className="subtitle">
            Headline numbers from Firebase Auth, Firestore products and orders. Refresh to pull the
            latest snapshot.
          </p>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={() => void load()} disabled={loading}>
          <IconRefresh size={14} />
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {error && (
        <div className="alert error-box" role="alert">
          <IconAlertTriangle size={16} />
          <span>
            {error}{' '}
            <button className="link-button" onClick={() => void load()}>
              Retry
            </button>
          </span>
        </div>
      )}

      <div className="kpi-grid">
        {(loading && !stats ? Array.from({ length: 7 }) : kpis).map((entry, i) => {
          const kpi = entry as Kpi | undefined;
          if (!kpi) {
            return (
              <div className="kpi" key={`skel-${i}`} aria-hidden="true">
                <div className="kpi-top">
                  <span className="skel" style={{ width: 34, height: 34, borderRadius: 8 }} />
                </div>
                <span className="skel" style={{ width: '55%' }} />
                <span className="skel" style={{ width: '40%', height: 26 }} />
              </div>
            );
          }
          return (
            <div
              className="kpi"
              key={kpi.key}
              role="group"
              aria-label={`${kpi.label}: ${kpi.value.toLocaleString()}`}
            >
              <div className="kpi-top">
                <span className={`kpi-icon tone-${kpi.tone}`}>{kpi.icon}</span>
                {kpi.attention && (
                  <span className="badge badge-status-pending">Needs review</span>
                )}
              </div>
              <span className="kpi-label">{kpi.label}</span>
              <span className="kpi-value">{kpi.value.toLocaleString()}</span>
              <span className="kpi-hint">{kpi.hint}</span>
            </div>
          );
        })}
      </div>

      <section className="panel">
        <div className="panel-header">
          <h2>Newest signups</h2>
          {stats && (
            <span className="panel-note">
              {stats.authOnlyAccounts.toLocaleString()} auth-only account
              {stats.authOnlyAccounts === 1 ? '' : 's'} (no profile document)
            </span>
          )}
        </div>
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th>Joined</th>
              </tr>
            </thead>
            <tbody>
              {loading && !stats ? (
                Array.from({ length: 5 }, (_, r) => (
                  <tr key={`skel-${r}`} aria-hidden="true">
                    {Array.from({ length: 5 }, (_, c) => (
                      <td key={c}>
                        <span className="skel" style={{ width: c === 1 ? '80%' : '60%' }} />
                      </td>
                    ))}
                  </tr>
                ))
              ) : stats && stats.recentUsers.length > 0 ? (
                stats.recentUsers.map((u) => (
                  <tr key={u.uid}>
                    <td>
                      <div className="cell-primary">
                        <span>{u.name || '—'}</span>
                      </div>
                    </td>
                    <td>
                      <span className="mono">{u.email}</span>
                    </td>
                    <td>
                      <RoleBadge role={u.role} />
                    </td>
                    <td>
                      <StatusBadge status={u.verificationStatus} />
                    </td>
                    <td>{formatDate(u.createdAt)}</td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td className="table-state" colSpan={5}>
                    <div className="state-inner">
                      <span className="state-icon">
                        <IconUsers size={28} />
                      </span>
                      <span>No users yet — accounts appear here as they register.</span>
                    </div>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
