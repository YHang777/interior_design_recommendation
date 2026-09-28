import { useState } from 'react';
import { AuthProvider, useAuth } from './state/AuthContext';
import { ToastProvider } from './state/ToastContext';
import { Layout, type PageKey } from './components/Layout';
import { LoginPage } from './pages/LoginPage';
import { OverviewPage } from './pages/OverviewPage';
import { UsersPage } from './pages/UsersPage';
import { VerificationPage } from './pages/VerificationPage';

function Shell() {
  const { user, ready } = useAuth();
  const [page, setPage] = useState<PageKey>('overview');
  // Global search — lives in the topbar (Layout) and filters the users
  // table (UsersPage), so it persists while switching directory pages.
  const [query, setQuery] = useState('');

  if (!ready) {
    return (
      <div className="boot-screen">
        <span className="spinner" />
        Loading admin console…
      </div>
    );
  }
  if (!user) return <LoginPage />;

  return (
    <Layout current={page} onNavigate={setPage} query={query} onQueryChange={setQuery}>
      {page === 'overview' && <OverviewPage />}
      {page === 'users' && <UsersPage key="users" role="all" showRoleChips query={query} onQueryChange={setQuery} />}
      {page === 'suppliers' && <UsersPage key="suppliers" role="supplier" query={query} onQueryChange={setQuery} />}
      {page === 'verification' && <VerificationPage query={query} />}
    </Layout>
  );
}

export default function App() {
  return (
    <ToastProvider>
      <AuthProvider>
        <Shell />
      </AuthProvider>
    </ToastProvider>
  );
}
