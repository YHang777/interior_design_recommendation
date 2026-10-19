/** Mirrors the backend's `web/backend/src/types/models.ts`, which in turn
 * mirrors the Flutter app's Firestore schema. */

export type UserRole = 'homeowner' | 'supplier' | 'unknown';
export type VerificationStatus = 'verified' | 'pending' | 'rejected';

export interface AdminUserRow {
  uid: string;
  email: string;
  name: string;
  role: UserRole;
  /** Firebase admin claim or ADMIN_UIDS allowlist — display-only badge. */
  isAdmin: boolean;
  verificationStatus: VerificationStatus | 'unknown';
  phone: string;
  businessName: string;
  businessPhone: string;
  createdAt: string | null;
  authCreatedAt: string | null;
  lastSignInAt: string | null;
  emailVerified: boolean;
  disabled: boolean;
  profileExists: boolean;
  productCount: number;
  orderCount: number;
}

export interface AdminUserDetail extends AdminUserRow {
  address: string;
  profilePicture: string;
  businessAddress: string;
  updatedAt: string | null;
}

export interface ListUsersResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminUserRow[];
}

export interface AdminStats {
  customers: number;
  suppliers: number;
  authOnlyAccounts: number;
  products: number;
  orders: number;
  pendingSuppliers: number;
  rejectedSuppliers: number;
  /** Suppliers whose verificationStatus is anything but 'verified'. */
  unverifiedSuppliers: number;
  /** verification_applications still awaiting a decision (IC queue). */
  pendingVerifications: number;
  recentUsers: Pick<
    AdminUserRow,
    'uid' | 'email' | 'name' | 'role' | 'isAdmin' | 'verificationStatus' | 'createdAt'
  >[];
}

export interface LoginResponse {
  uid: string;
  email: string;
  idToken: string;
  expiresIn: string;
  isAdmin: boolean;
  profile: Record<string, unknown> | null;
}

export interface MeResponse {
  uid: string;
  email: string | null;
  name: string | null;
  isAdmin: boolean;
  adminViaClaim: boolean;
  profile: Record<string, unknown> | null;
}

export interface VerificationResult {
  uid: string;
  verificationStatus: VerificationStatus;
  productsSynced: number;
}

export type PasswordResetResponse =
  | { mode: 'reset_link'; email: string; link: string }
  | { mode: 'temp_password'; email: string; tempPassword: string };

/**
 * Supplier verification applications — `verification_applications/{uid}`.
 * Document bytes are NOT part of these payloads; they are streamed through
 * `GET /verification/applications/:uid/documents/:docId` with the bearer
 * token (Storage itself denies all client reads of `verification/**`).
 */
export type ApplicationStatus = 'pending' | 'approved' | 'rejected';
export type ApplicationFilter = ApplicationStatus | 'all';
export type VerificationDocumentKind = 'ic_front' | 'ic_back' | 'supporting';

export interface VerificationDocument {
  id: string;
  kind: VerificationDocumentKind;
  fileName: string;
  contentType: string;
  sizeBytes: number;
  storagePath: string;
  uploadedAt: string;
}

export interface VerificationApplication {
  uid: string;
  email: string;
  businessName: string;
  status: ApplicationStatus;
  submittedAt: string;
  reviewedAt: string | null;
  reviewedBy: string | null;
  reviewNote: string | null;
  documents: VerificationDocument[];
}

export interface VerificationApplicationSummary {
  uid: string;
  email: string;
  businessName: string;
  status: ApplicationStatus;
  submittedAt: string;
  documentCount: number;
}

export interface VerificationListResult {
  total: number;
  limit: number;
  offset: number;
  items: VerificationApplicationSummary[];
}

export interface ReviewDecisionResult {
  application: VerificationApplication;
  verificationStatus: 'verified' | 'rejected';
  productsSynced: number;
}

export interface DeleteResult {
  uid: string;
  email: string;
  authDeleted: boolean;
  profileDeleted: boolean;
  cartItemsDeleted: number;
  wishlistItemsDeleted: number;
  productsDeactivated: number;
}

/**
 * Photo-vs-claim flag queue — mirrors the backend's `ProductFlagRow`
 * (`products/{id}.vision` + `vision.review`, both written server-side).
 */
export type ProductFlagStatusFilter = 'open' | 'resolved' | 'all';

export interface ProductFlagReview {
  status: 'open' | 'resolved';
  note?: string;
  reviewedAt: string;
  reviewedBy: string;
}

export interface ProductFlagVision {
  status: string;
  labels: string[];
  visualCategory: string;
  summary: string;
  mismatch: { flagged: boolean; reason: string };
  analyzedAt: string | null;
  model: string;
}

export interface ProductFlagRow {
  productId: string;
  name: string;
  category: string;
  price: number;
  supplierId: string;
  image: string;
  description: string;
  vision: ProductFlagVision;
  review: ProductFlagReview | null;
}

export interface ProductFlagListResult {
  items: ProductFlagRow[];
  total: number;
}

// ── Product catalogue admin ─────────────────────────────────────────────────

export interface AdminProductRow {
  productId: string;
  name: string;
  category: string;
  designStyle: string;
  price: number;
  originalPrice: number | null;
  stock: number;
  isActive: boolean;
  isEcoFriendly: boolean;
  rating: number;
  ratingCount: number;
  supplierId: string;
  supplierName: string;
  image: string;
  createdAt: string | null;
}

export interface AdminProductDetail extends AdminProductRow {
  description: string;
  images: string[];
  shippingEnabled: boolean;
  shippingFee: number;
  shippingLongDistanceNotice: boolean;
  ar3dStatus: string;
  visionFlagged: boolean;
  supplierPhone: string;
  supplierEmail: string;
  supplierVerificationStatus: string;
}

export interface ProductUpdate {
  name?: string;
  description?: string;
  category?: string;
  designStyle?: string;
  price?: number;
  originalPrice?: number | null;
  stock?: number;
  isActive?: boolean;
  isEcoFriendly?: boolean;
  shippingEnabled?: boolean;
  shippingFee?: number;
  shippingLongDistanceNotice?: boolean;
}

export interface ListProductsResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminProductRow[];
}

export interface DeleteProductResult {
  productId: string;
  deleted: boolean;
  reviewsDeleted: number;
}

// ── Orders admin ────────────────────────────────────────────────────────────

export type AdminOrderStatus = 'pending' | 'confirmed' | 'shipped' | 'delivered' | 'cancelled';

export interface AdminOrderItem {
  productId: string;
  name: string;
  image: string;
  unitPrice: number;
  quantity: number;
  supplierId: string;
}

export interface AdminOrderRow {
  orderId: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  status: AdminOrderStatus;
  itemCount: number;
  total: number;
  paymentMethod: string;
  createdAt: string | null;
  nextStatuses: AdminOrderStatus[];
}

export interface AdminOrderDetail extends AdminOrderRow {
  customerEmail: string;
  customerPhone: string;
  shippingAddress: string;
  items: AdminOrderItem[];
  subtotal: number;
  shippingFee: number;
  discount: number;
  tax: number;
  supplierIds: string[];
  statusHistory: Record<string, string>;
  invoiceSupplierIds: string[];
}

export interface ListOrdersResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminOrderRow[];
}
