import { useState, type FormEvent } from 'react';
import { useAuth } from '../state/AuthContext';
import { ApiError } from '../api/client';
import {
  IconAlertTriangle,
  IconEye,
  IconEyeOff,
  IconLock,
  IconMail,
} from '../components/icons';

/** Map the backend's structured `{error:{code}}` to plain-language copy. */
function describeLoginError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Sign-in failed. Try again.';
  switch (err.code) {
    case 'BAD_CREDENTIALS':
      return 'Incorrect email or password.';
    case 'NOT_ADMIN':
      return 'This account has no admin access.';
    case 'UNAUTHENTICATED':
      return 'Could not verify your credentials.';
    case 'LOGIN_NOT_CONFIGURED':
      return 'Password sign-in is not set up. Set FIREBASE_WEB_API_KEY.';
    case 'FIREBASE_NOT_CONFIGURED':
      return 'Firebase credentials are missing on the server.';
    case 'ACCOUNT_DISABLED':
      return 'This account is disabled.';
    case 'RATE_LIMITED':
      return 'Too many attempts. Wait a minute.';
    case 'NETWORK_ERROR':
      return 'Cannot reach the admin API.';
    case 'IDENTITY_TOOLKIT_ERROR':
      return 'Sign-in failed at Firebase. Try again.';
    case 'VALIDATION_ERROR':
      return err.message;
    default:
      return err.message || `Sign-in failed (${err.status}).`;
  }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Email/password sign-in — posts to the backend's login proxy only. */
export function LoginPage() {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [touched, setTouched] = useState<{ email: boolean; password: boolean }>({
    email: false,
    password: false,
  });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const trimmedEmail = email.trim();
  const emailError = !touched.email
    ? null
    : !trimmedEmail
      ? 'Email is required.'
      : !EMAIL_RE.test(trimmedEmail)
        ? 'Enter a valid email address.'
        : null;
  const passwordError = !touched.password
    ? null
    : !password
      ? 'Password is required.'
      : password.length < 6
        ? 'Passwords are at least 6 characters.'
        : null;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setTouched({ email: true, password: true });
    setFormError(null);
    if (!EMAIL_RE.test(trimmedEmail) || password.length < 6) return;

    setBusy(true);
    try {
      await login(trimmedEmail, password);
      // Signed in — the shell swaps this screen out.
    } catch (err) {
      setFormError(describeLoginError(err));
      setBusy(false);
    }
  };

  return (
    <div className="login-screen">
      <aside className="login-aside" aria-hidden="true">
        <div className="brand">
          <span className="brand-mark">I</span>
          <span className="brand-text">
            Intellar
            <small>Admin console</small>
          </span>
        </div>
        <div className="login-aside-copy">
          <h1>Marketplace admin.</h1>
          <p>Users, sellers, catalog and orders.</p>
        </div>
        <div className="login-foot">Intellar · Admin console</div>
      </aside>

      <main className="login-main">
        <form className="login-card" onSubmit={submit} noValidate>
          <div className="login-compact-brand">
            <span className="brand-mark" aria-hidden="true">
              I
            </span>
            <span className="brand-text" style={{ color: 'var(--text)' }}>
              Intellar
              <small>Admin console</small>
            </span>
          </div>

          <h1>Sign in</h1>
          <p className="login-sub">Administrator account required.</p>

          <div className="login-form">
            <div className="field">
              <label className="field-label" htmlFor="login-email">
                Email
              </label>
              <span className="input-wrap">
                <IconMail size={16} />
                <input
                  id="login-email"
                  className="input"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  onBlur={() => setTouched((t) => ({ ...t, email: true }))}
                  placeholder="admin@example.com"
                  autoComplete="username"
                  autoCapitalize="none"
                  spellCheck={false}
                  required
                  disabled={busy}
                  aria-invalid={emailError ? true : undefined}
                  aria-describedby={emailError ? 'login-email-error' : undefined}
                />
              </span>
              {emailError && (
                <span className="field-error" id="login-email-error" role="alert">
                  {emailError}
                </span>
              )}
            </div>

            <div className="field">
              <label className="field-label" htmlFor="login-password">
                Password
              </label>
              <span className="input-wrap has-adorn">
                <IconLock size={16} />
                <input
                  id="login-password"
                  className="input"
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  onBlur={() => setTouched((t) => ({ ...t, password: true }))}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  required
                  disabled={busy}
                  aria-invalid={passwordError ? true : undefined}
                  aria-describedby={passwordError ? 'login-password-error' : undefined}
                />
                <button
                  type="button"
                  className="input-adorn"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  aria-pressed={showPassword}
                >
                  {showPassword ? <IconEyeOff size={16} /> : <IconEye size={16} />}
                </button>
              </span>
              {passwordError && (
                <span className="field-error" id="login-password-error" role="alert">
                  {passwordError}
                </span>
              )}
            </div>

            {formError && (
              <div className="alert error-box" role="alert">
                <IconAlertTriangle size={16} />
                <span>{formError}</span>
              </div>
            )}

            <button
              className="btn btn-primary btn-block login-submit"
              type="submit"
              disabled={busy}
              aria-busy={busy}
            >
              {busy ? (
                <>
                  <span className="spinner spinner-inline" />
                  Signing in…
                </>
              ) : (
                'Sign in'
              )}
            </button>
          </div>
        </form>
      </main>
    </div>
  );
}
