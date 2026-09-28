/**
 * The ONLY way this app talks to anything: the admin backend API.
 * No Firebase / Supabase SDKs exist in this frontend — the backend owns
 * every Firebase interaction.
 */

const EXPLICIT_API_BASE = import.meta.env.VITE_API_BASE_URL as string | undefined;

const API_BASE = EXPLICIT_API_BASE?.replace(/\/$/, '') ?? 'http://localhost:4000/api';

/** Whether VITE_API_BASE_URL was actually set — surfaced in network-error
 * copy so a misconfigured deploy is distinguishable from a down backend. */
export const apiBaseConfigured = Boolean(EXPLICIT_API_BASE);
export const apiBaseUrl = API_BASE;

const TOKEN_KEY = 'admin_id_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

/** Fired when the API answers 401 — AuthContext listens and logs out. */
export const UNAUTHORIZED_EVENT = 'admin:unauthorized';

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
}

export async function api<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body } = options;
  const headers: Record<string, string> = {};
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError(0, 'NETWORK_ERROR', 'Cannot reach the admin API. Is the backend running?');
  }

  let payload: unknown = null;
  try {
    payload = await res.json();
  } catch {
    // Non-JSON response (e.g. proxy error page) — handled below.
  }

  if (!res.ok) {
    const err = (payload as { error?: { code?: string; message?: string; details?: unknown } } | null)?.error;
    if (res.status === 401) {
      clearToken();
      window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
    }
    throw new ApiError(
      res.status,
      err?.code ?? `HTTP_${res.status}`,
      err?.message ?? `Request failed (${res.status}).`,
      err?.details
    );
  }
  return payload as T;
}

/**
 * Binary variant of `api()` — same auth, 401 and network handling, but the
 * response body stays raw bytes. Used to pull IC images through the
 * authenticated API (Storage has no public read for `verification/**`, so
 * there is no URL that could be embedded directly).
 */
export async function apiBlob(path: string): Promise<Blob> {
  const headers: Record<string, string> = {};
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;

  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, { headers });
  } catch {
    throw new ApiError(0, 'NETWORK_ERROR', 'Cannot reach the admin API. Is the backend running?');
  }

  if (!res.ok) {
    let code = `HTTP_${res.status}`;
    let message = `Request failed (${res.status}).`;
    try {
      const payload = (await res.json()) as {
        error?: { code?: string; message?: string; details?: unknown };
      } | null;
      if (payload?.error?.code) code = payload.error.code;
      if (payload?.error?.message) message = payload.error.message;
    } catch {
      // Non-JSON error body — keep the generic message.
    }
    if (res.status === 401) {
      clearToken();
      window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
    }
    throw new ApiError(res.status, code, message);
  }
  return res.blob();
}

export const apiGet = <T>(path: string) => api<T>(path);
export const apiPost = <T>(path: string, body: unknown) => api<T>(path, { method: 'POST', body });
export const apiPatch = <T>(path: string, body: unknown) => api<T>(path, { method: 'PATCH', body });
export const apiDelete = <T>(path: string, body: unknown) => api<T>(path, { method: 'DELETE', body });
