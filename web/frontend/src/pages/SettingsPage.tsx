import { useEffect, useState } from 'react';
import { settingsApi } from '../api/api';
import { ApiError } from '../api/client';
import type { AppSettings } from '../api/types';
import { IconAlertTriangle, IconRefresh } from '../components/icons';
import { useToast } from '../state/ToastContext';

function describeSettingsError(err: unknown): string {
  if (!(err instanceof ApiError)) return 'Could not load settings.';
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

function toPercentInput(taxRate: number): string {
  return String(Math.round(taxRate * 10000) / 100);
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
}

export function SettingsPage() {
  const { push } = useToast();

  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [taxPercent, setTaxPercent] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    settingsApi
      .get()
      .then((res) => {
        if (cancelled) return;
        setSettings(res.settings);
        setTaxPercent(toPercentInput(res.settings.taxRate));
      })
      .catch((err) => {
        if (!cancelled) setError(describeSettingsError(err));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [reloadKey]);

  const save = async () => {
    if (saving) return;
    const pct = Number(taxPercent);
    if (!taxPercent.trim() || !Number.isFinite(pct) || pct < 0 || pct > 100) {
      setFieldError('Enter a percentage between 0 and 100.');
      return;
    }
    setFieldError(null);
    setSaving(true);
    try {
      const { settings: next } = await settingsApi.update(Math.round(pct * 10000) / 10000);
      setSettings(next);
      setTaxPercent(toPercentInput(next.taxRate));
      push('success', 'Tax rate saved.');
    } catch (err) {
      push('error', describeSettingsError(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="page">
      <div className="page-intro">
        <div>
          <h2>Settings</h2>
          <p className="subtitle">Marketplace-wide pricing rules for buyers and sellers.</p>
        </div>
        <button
          className="btn btn-secondary btn-sm"
          onClick={() => setReloadKey((k) => k + 1)}
          disabled={loading || saving}
        >
          <IconRefresh size={14} />
          {loading ? 'Loading…' : 'Reload'}
        </button>
      </div>

      {error && (
        <div className="alert error-box" role="alert">
          <IconAlertTriangle size={16} />
          <span style={{ flex: 1 }}>{error}</span>
          <button className="link-button" onClick={() => setReloadKey((k) => k + 1)}>
            Retry
          </button>
        </div>
      )}

      <section className="panel">
        <div className="panel-header">
          <h2>Pricing</h2>
          <span className="panel-note">Applies to new orders at checkout.</span>
        </div>
        <div className="modal-body">
          {loading && !settings ? (
            <div className="drawer-state">
              <span className="spinner" />
              Loading settings…
            </div>
          ) : (
            <div className="form-grid">
              <div className="field">
                <label className="field-label" htmlFor="tax-rate">
                  Tax rate (%)
                </label>
                <input
                  id="tax-rate"
                  className="input"
                  type="number"
                  min={0}
                  max={100}
                  step={0.01}
                  value={taxPercent}
                  aria-invalid={fieldError ? true : undefined}
                  onChange={(e) => {
                    setTaxPercent(e.target.value);
                    setFieldError(null);
                  }}
                />
                <span className="field-hint">Applied to the chargeable total after discounts. Default 6%.</span>
                {fieldError && <span className="field-error">{fieldError}</span>}
              </div>
              <div className="field field-span">
                <span className="field-hint">
                  Last updated {formatDateTime(settings?.updatedAt ?? null)}
                  {settings?.updatedBy ? ` by ${settings.updatedBy}` : ''}.
                </span>
              </div>
            </div>
          )}
        </div>
        <div className="panel-footer">
          <span />
          <div className="pager">
            <button className="btn btn-primary btn-sm" onClick={() => void save()} disabled={loading || saving} aria-busy={saving}>
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
        </div>
      </section>
    </div>
  );
}
