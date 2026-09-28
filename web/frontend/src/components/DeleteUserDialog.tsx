import { useState } from 'react';
import { Modal } from './Modal';
import { usersApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AdminUserRow } from '../api/types';
import { IconAlertTriangle, IconTrash } from './icons';

interface Props {
  user: AdminUserRow;
  onClose: () => void;
  onDeleted: (email: string) => void;
}

/**
 * Type-to-confirm deletion dialog. The confirm button stays disabled until
 * the admin types the target's email exactly (case-insensitive), and
 * PARTIAL_DELETE failures are surfaced verbatim so a half-finished cleanup
 * is never mistaken for success.
 */
export function DeleteUserDialog({ user, onClose, onDeleted }: Props) {
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const matches = typed.trim().toLowerCase() === user.email.trim().toLowerCase() && user.email.length > 0;

  const confirm = async () => {
    if (!matches || busy) return;
    setBusy(true);
    setError(null);
    try {
      const result = await usersApi.delete(user.uid, typed.trim());
      onDeleted(result.email);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError('Deletion failed unexpectedly. Check the backend logs.');
      }
      setBusy(false);
    }
  };

  return (
    <Modal
      title="Delete account"
      onClose={busy ? () => undefined : onClose}
      width={520}
      tone="danger"
      headerIcon={<IconTrash size={16} />}
    >
      <div className="danger-box" role="alert">
        <strong>This permanently deletes {user.email}.</strong>
        <ul>
          <li>The Firebase Auth account is removed — the user can no longer sign in.</li>
          <li>Their profile, cart and wishlist documents are deleted.</li>
          <li>
            {user.role === 'supplier'
              ? 'Their product listings are deactivated (kept for order history).'
              : 'Past orders are kept for history.'}
          </li>
          <li>This cannot be undone.</li>
        </ul>
      </div>

      <div className="field">
        <label className="field-label" htmlFor="delete-confirm-input">
          Type <code>{user.email}</code> to confirm:
        </label>
        <input
          id="delete-confirm-input"
          className="input"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          placeholder={user.email}
          autoComplete="off"
          spellCheck={false}
          disabled={busy}
          aria-label="Confirmation email"
        />
      </div>

      {error && (
        <div className="alert error-box" role="alert">
          <IconAlertTriangle size={16} />
          <span>{error}</span>
        </div>
      )}

      <div className="modal-actions">
        <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
          Cancel
        </button>
        <button className="btn btn-danger" onClick={confirm} disabled={!matches || busy}>
          {busy && <span className="spinner spinner-inline" />}
          {busy ? 'Deleting…' : 'Delete permanently'}
        </button>
      </div>
    </Modal>
  );
}
