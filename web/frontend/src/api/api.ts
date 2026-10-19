import { apiBlob, apiDelete, apiGet, apiPatch, apiPost } from './client';
import type {
  AdminOrderDetail,
  AdminOrderStatus,
  AdminProductDetail,
  AdminStats,
  AdminUserDetail,
  ApplicationFilter,
  DeleteProductResult,
  DeleteResult,
  ListOrdersResult,
  ListProductsResult,
  ListUsersResult,
  LoginResponse,
  MeResponse,
  PasswordResetResponse,
  ProductFlagListResult,
  ProductFlagRow,
  ProductFlagStatusFilter,
  ProductUpdate,
  ReviewDecisionResult,
  AppSettings,
  VerificationApplication,
  VerificationListResult,
  VerificationResult,
  VerificationStatus,
} from './types';

export const authApi = {
  login: (email: string, password: string) =>
    apiPost<LoginResponse>('/auth/login', { email, password }),
  me: () => apiGet<MeResponse>('/auth/me'),
};

export interface UsersQuery {
  role: 'all' | 'homeowner' | 'supplier';
  status?: VerificationStatus | '';
  q?: string;
  limit?: number;
  offset?: number;
}

export const usersApi = {
  list: (query: UsersQuery) => {
    const params = new URLSearchParams();
    params.set('role', query.role);
    if (query.status) params.set('status', query.status);
    if (query.q) params.set('q', query.q);
    params.set('limit', String(query.limit ?? 50));
    params.set('offset', String(query.offset ?? 0));
    return apiGet<ListUsersResult>(`/users?${params.toString()}`);
  },
  detail: (uid: string) => apiGet<{ user: AdminUserDetail }>(`/users/${encodeURIComponent(uid)}`),
  setVerification: (uid: string, status: VerificationStatus) =>
    apiPatch<VerificationResult>(`/users/${encodeURIComponent(uid)}/verification`, { status }),
  passwordReset: (uid: string, mode: 'reset_link' | 'temp_password') =>
    apiPost<PasswordResetResponse>(`/users/${encodeURIComponent(uid)}/password-reset`, { mode }),
  delete: (uid: string, confirmEmail: string) =>
    apiDelete<DeleteResult>(`/users/${encodeURIComponent(uid)}`, { confirmEmail }),
};

export const statsApi = {
  get: () => apiGet<AdminStats>('/stats'),
};

/**
 * Supplier verification applications (IC + supporting docs). Every call
 * carries the bearer token; document bytes come back as a Blob through the
 * API — never through a public Storage URL (client reads are denied there).
 */
export const verificationApi = {
  list: (status: ApplicationFilter, opts?: { limit?: number; offset?: number }) => {
    const params = new URLSearchParams();
    params.set('status', status);
    if (opts?.limit !== undefined) params.set('limit', String(opts.limit));
    if (opts?.offset !== undefined) params.set('offset', String(opts.offset));
    return apiGet<VerificationListResult>(`/verification/applications?${params.toString()}`);
  },
  get: (uid: string) =>
    apiGet<{ application: VerificationApplication }>(
      `/verification/applications/${encodeURIComponent(uid)}`
    ),
  documentBlob: (uid: string, docId: string) =>
    apiBlob(
      `/verification/applications/${encodeURIComponent(uid)}/documents/${encodeURIComponent(docId)}`
    ),
  decide: (uid: string, status: 'approved' | 'rejected', reviewNote?: string) =>
    apiPatch<ReviewDecisionResult>(`/verification/applications/${encodeURIComponent(uid)}`, {
      status,
      ...(reviewNote !== undefined ? { reviewNote } : {}),
    }),
};

/**
 * Photo-vs-claim review queue (`/products/flags`). Rows come from the
 * upload-time vision verdict; the PATCH writes `vision.review` — a
 * server-owned field no client can forge.
 */
export const productFlagsApi = {
  list: (status: ProductFlagStatusFilter = 'open') =>
    apiGet<ProductFlagListResult>(`/products/flags?status=${status}`),
  setReview: (productId: string, status: 'resolved' | 'open', note?: string) =>
    apiPatch<{ item: ProductFlagRow }>(`/products/flags/${encodeURIComponent(productId)}`, {
      status,
      ...(note !== undefined && note.length > 0 ? { note } : {}),
    }),
};

export interface ProductsQuery {
  q?: string;
  category?: string;
  status?: 'all' | 'active' | 'inactive';
  limit?: number;
  offset?: number;
}

export const productsApi = {
  list: (query: ProductsQuery) => {
    const params = new URLSearchParams();
    if (query.q) params.set('q', query.q);
    if (query.category) params.set('category', query.category);
    params.set('status', query.status ?? 'all');
    params.set('limit', String(query.limit ?? 50));
    params.set('offset', String(query.offset ?? 0));
    return apiGet<ListProductsResult>(`/products?${params.toString()}`);
  },
  get: (productId: string) =>
    apiGet<{ product: AdminProductDetail }>(`/products/${encodeURIComponent(productId)}`),
  update: (productId: string, patch: ProductUpdate) =>
    apiPatch<{ product: AdminProductDetail }>(`/products/${encodeURIComponent(productId)}`, patch),
  remove: (productId: string) =>
    apiDelete<DeleteProductResult>(`/products/${encodeURIComponent(productId)}`, undefined),
};

export interface OrdersQuery {
  status?: AdminOrderStatus | '';
  q?: string;
  limit?: number;
  offset?: number;
}

export const ordersApi = {
  list: (query: OrdersQuery) => {
    const params = new URLSearchParams();
    if (query.status) params.set('status', query.status);
    if (query.q) params.set('q', query.q);
    params.set('limit', String(query.limit ?? 50));
    params.set('offset', String(query.offset ?? 0));
    return apiGet<ListOrdersResult>(`/orders?${params.toString()}`);
  },
  get: (orderId: string) => apiGet<{ order: AdminOrderDetail }>(`/orders/${encodeURIComponent(orderId)}`),
  setStatus: (orderId: string, status: AdminOrderStatus) =>
    apiPatch<{ order: AdminOrderDetail }>(`/orders/${encodeURIComponent(orderId)}`, { status }),
};

/** Marketplace-wide settings (tax rate), stored in `appConfig/marketplace`. */
export const settingsApi = {
  get: () => apiGet<{ settings: AppSettings }>('/settings'),
  update: (taxRate: number) => apiPatch<{ settings: AppSettings }>('/settings', { taxRate }),
};
