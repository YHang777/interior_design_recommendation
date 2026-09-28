import { useEffect, useState, type KeyboardEvent, type ReactNode } from 'react';
import { verificationApi } from '../api/api';
import { useAuth } from '../state/AuthContext';
import { IconGrid, IconLogout, IconSearch, IconShield, IconStore, IconUsers } from './icons';

export type PageKey = 'overview' | 'users' | 'suppliers' | 'verification';

export const PAGE_META: Record<PageKey, { title: string; breadcrumb: string }> = {
  overview: { title: 'Overview', breadcrumb: 'Marketplace health' },
  users: { title: 'Users', breadcrumb: 'Directory · all accounts' },
  suppliers: { title: 'Suppliers', breadcrumb: 'Directory · sellers' },
  verification: { title: 'Verification', breadcrumb: 'Directory · IC review queue' },
};

interface Props {
  current: PageKey;
  onNavigate: (page: PageKey) => void;
  /** Global search value — filters the users table on the directory pages. */
  query: string;
  onQueryChange: (value: string) => void;
  children: ReactNode;
}

interface NavItem {
  key: PageKey;
  label: string;
  icon: ReactNode;
}

const NAV_GROUPS: { label: string; items: NavItem[] }[] = [
  {
    label: 'Monitor',
    items: [
      {
        key: 'overview',
        label: 'Overview',
        icon: <IconGrid size={17} />,
      },
    ],
  },
  {
    label: 'Directory',
    items: [
      {
        key: 'users',
        label: 'Users',
        icon: <IconUsers size={17} />,
      },
      {
        key: 'suppliers',
        label: 'Suppliers',
        icon: <IconStore size={17} />,
      },
      {
        key: 'verification',
        label: 'Verification',
        icon: <IconShield size={17} />,
      },
    ],
  },
];

/**
 * App shell: dark brand sidebar (grouped nav, active state, admin identity +
 * sign-out at the bottom) and a sticky topbar carrying the breadcrumb, page
 * title and a global search that drives the users table. Under 900px the
 * sidebar collapses to an icon rail.
 */
export function Layout({ current, onNavigate, query, onQueryChange, children }: Props) {
  const { user, logout } = useAuth();
  const meta = PAGE_META[current];

  // Pending-verification count for the sidebar badge. Best-effort: failures
  // are silent here (the Verification page surfaces its own error state) —
  // a 401 still triggers the shared logout event from the API client.
  const [pendingReviews, setPendingReviews] = useState(0);
  useEffect(() => {
    let cancelled = false;
    verificationApi
      .list('pending', { limit: 1 })
      .then((res) => {
        if (!cancelled) setPendingReviews(res.total);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [current]);

  const onSearchKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    // On the overview page the search jumps into the directory with the
    // query applied; on directory pages it already filters the table.
    if (current === 'overview') onNavigate('users');
  };

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">
            I
          </span>
          <span className="brand-text">
            Intellar
            <small>Admin console</small>
          </span>
        </div>

        <nav className="nav" aria-label="Primary">
          {NAV_GROUPS.map((group) => (
            <div className="nav-group" key={group.label}>
              <div className="nav-group-label">{group.label}</div>
              {group.items.map((item) => (
                <button
                  key={item.key}
                  className={`nav-item ${current === item.key ? 'active' : ''}`}
                  onClick={() => onNavigate(item.key)}
                  aria-current={current === item.key ? 'page' : undefined}
                  title={item.label}
                >
                  {item.icon}
                  <span>{item.label}</span>
                  {item.key === 'verification' && pendingReviews > 0 && (
                    <span className="nav-count" aria-label={`${pendingReviews} awaiting review`}>
                      {pendingReviews > 99 ? '99+' : pendingReviews}
                    </span>
                  )}
                </button>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-spacer" />

        <div className="sidebar-footer">
          <div className="whoami" title={user?.email ?? undefined}>
            <span className="avatar" aria-hidden="true">
              {(user?.email ?? '?').charAt(0).toUpperCase()}
            </span>
            <span className="whoami-meta">
              <span className="whoami-name">Signed in</span>
              <span className="whoami-email">{user?.email}</span>
            </span>
          </div>
          <button className="nav-item signout" onClick={logout} title="Sign out">
            <IconLogout size={17} />
            <span>Sign out</span>
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <div className="topbar-left">
            <div className="breadcrumb" aria-hidden="true">
              <span>Admin</span>
              <span className="breadcrumb-sep">/</span>
              <span>{meta.breadcrumb}</span>
            </div>
            <h1 className="topbar-title">{meta.title}</h1>
          </div>
          <div className="topbar-right">
            <label className="search-global">
              <IconSearch size={15} />
              <input
                type="search"
                placeholder="Search name, email, business…"
                aria-label="Search users"
                value={query}
                onChange={(e) => onQueryChange(e.target.value)}
                onKeyDown={onSearchKeyDown}
              />
            </label>
          </div>
        </header>

        <main className="content">{children}</main>
      </div>
    </div>
  );
}
