import { useEffect, useRef, type ReactNode } from 'react';
import { IconX } from './icons';

interface ModalProps {
  title: string;
  onClose: () => void;
  children: ReactNode;
  width?: number;
  /** Destructive dialogs get a danger-tinted header icon. */
  tone?: 'default' | 'danger';
  headerIcon?: ReactNode;
}

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * Dialog shell: overlay, title bar, close button — with a real focus trap.
 * - Focus moves into the dialog on open (the dialog surface itself, never a
 *   destructive button) and returns to the opener on close.
 * - Tab / Shift+Tab cycle within the dialog; Escape closes.
 */
export function Modal({ title, onClose, children, width = 480, tone = 'default', headerIcon }: ModalProps) {
  const dialogRef = useRef<HTMLDivElement>(null);
  // Keep the latest onClose without re-running the focus effect on every
  // parent render (which would yank focus back to the dialog surface).
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    const dialog = dialogRef.current;
    dialog?.focus();

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (e.key !== 'Tab' || !dialog) return;
      const focusables = Array.from(dialog.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
        (el) => el.offsetParent !== null
      );
      if (focusables.length === 0) {
        e.preventDefault();
        dialog.focus();
        return;
      }
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || active === dialog)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      opener?.focus?.();
    };
  }, []);

  return (
    <div className="overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div
        className="modal"
        ref={dialogRef}
        style={{ width }}
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
        tabIndex={-1}
      >
        <div className="modal-header">
          <div className="modal-title-wrap">
            {headerIcon && (
              <span className={`modal-icon ${tone === 'danger' ? 'tone-danger' : 'tone-accent'}`}>
                {headerIcon}
              </span>
            )}
            <h2 id="modal-title">{title}</h2>
          </div>
          <button className="icon-button" aria-label="Close dialog" onClick={onClose}>
            <IconX size={16} />
          </button>
        </div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}
