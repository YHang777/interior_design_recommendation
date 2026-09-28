import { useState } from 'react';
import { Modal } from './Modal';
import { usersApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminUserRow } from '../api/types';
import { IconLock } from './icons';

interface Props {
  user: AdminUserRow;
  onClose: () => void;
}

type Mode = 'reset_link' | 'temp_password';

/**
 * Admin-initiated password help. Two modes, both server-side only:
 *  - reset_link    → backend generates a Firebase reset link (user picks
 *                    their own new password); the link is shown once.
 *  - temp_password → backend sets a random one-time password via Admin SDK;
 *                    shown once. No password material is ever stored.
 */
export function PasswordResetModal({ user, onClose }: Props) {
  const [mode, setMode] = useState<Mode>('reset_link');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{ mode: Mode; value: string } | null>(null);
  const [copied, setCopied] = useState(false);

  const run = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await usersApi.passwordReset(user.uid, mode);
      if (res.mode === 'reset_link') {
        setResult({ mode: 'reset_link', value: res.link });
      } else {
        setResult({ mode: 'temp_password', value: res.tempPassword });
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Password action failed.');
    } finally {
      setBusy(false);
    }
  };

  const copy = async () => {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(result.value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setError('Clipboard unavailable — select the value and copy manually.');
    }
  };

  return (
    <Modal
      title={`Password help — ${user.email}`}
      onClose={onClose}
      width={540}
      headerIcon={<IconLock size={16} />}
    >
      {!result ? (
        <>
          <div className="radio-group">
            <label className={`radio-card ${mode === 'reset_link' ? 'selected' : ''}`}>
              <input
                type="radio"
                name="reset-mode"
                checked={mode === 'reset_link'}
                onChange={() => setMode('reset_link')}
              />
              <span>
                <strong>Send reset link</strong>
                <em>Generates a Firebase password-reset link you forward to the user.</em>
              </span>
            </label>
            <label className={`radio-card ${mode === 'temp_password' ? 'selected' : ''}`}>
              <input
                type="radio"
                name="reset-mode"
                checked={mode === 'temp_password'}
                onChange={() => setMode('temp_password')}
              />
              <span>
                <strong>Set one-time password</strong>
                <em>Replaces the password with a random one you hand over directly.</em>
              </span>
            </label>
          </div>

          {error && (
            <div className="alert error-box" role="alert">
              <span>{error}</span>
            </div>
          )}

          <div className="modal-actions">
            <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
              Cancel
            </button>
            <button className="btn btn-primary" onClick={run} disabled={busy}>
              {busy && <span className="spinner spinner-inline" />}
              {busy ? 'Working…' : mode === 'reset_link' ? 'Generate link' : 'Set password'}
            </button>
          </div>
        </>
      ) : (
        <>
          <p className="hint">
            {result.mode === 'reset_link'
              ? 'Reset link generated (valid per the project’s email-link settings). Send it to the user — it is not stored anywhere.'
              : 'A new random password was set. It is shown ONCE below — copy it now; the server does not keep it.'}
          </p>
          <div className="result-row">
            <input
              className="input"
              readOnly
              value={result.value}
              onFocus={(e) => e.currentTarget.select()}
              aria-label={result.mode === 'reset_link' ? 'Password reset link' : 'One-time password'}
            />
            <button className="btn btn-secondary" onClick={copy}>
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          {error && (
            <div className="alert error-box" role="alert">
              <span>{error}</span>
            </div>
          )}
          <div className="modal-actions">
            <button className="btn btn-primary" onClick={onClose}>
              Done
            </button>
          </div>
        </>
      )}
    </Modal>
  );
}
