/**
 * Shapes returned by the admin API. Field names mirror the Flutter app's
 * Firestore schema (`lib/features/auth/data/models/app_user.dart`,
 * `lib/services/marketplace_repository.dart`):
 *
 *   users/{uid}    : name, email, role ('homeowner'|'supplier'), phone,
 *                    address, profilePicture, verificationStatus
 *                    ('verified'|'pending'|'rejected'), businessName,
 *                    businessPhone, businessAddress, createdAt, updatedAt
 *   products/{id}  : …, supplierId, supplier{ id,name,phone,address,email,
 *                    verificationStatus }, isActive, price, stock …
 *   orders/{id}    : …, customerId, supplierIds[], status, total, createdAt …
 */

export type UserRole = 'homeowner' | 'supplier' | 'unknown';
export type VerificationStatus = 'verified' | 'pending' | 'rejected';

export interface AdminUserRow {
  uid: string;
  /** Firebase Auth email (profile email mirrors it when a profile exists). */
  email: string;
  /** `users/{uid}.name` — empty when the profile document is missing. */
  name: string;
  role: UserRole;
  /** Firebase `admin:true` claim or the ADMIN_UIDS allowlist — display-only. */
  isAdmin: boolean;
  /** `users/{uid}.verificationStatus`. 'unknown' for Auth-only accounts. */
  verificationStatus: VerificationStatus | 'unknown';
  phone: string;
  /** Suppliers: business storefront fields from the profile document. */
  businessName: string;
  businessPhone: string;
  /** `users/{uid}.createdAt` (ISO-8601) when present. */
  createdAt: string | null;
  /** Firebase Auth record creation time (ISO-8601). */
  authCreatedAt: string | null;
  /** Last sign-in time from Firebase Auth (ISO-8601), null if never. */
  lastSignInAt: string | null;
  emailVerified: boolean;
  disabled: boolean;
  /** False when a Firebase Auth account exists but `users/{uid}` is missing. */
  profileExists: boolean;
  /** Products owned (`products` where supplierId/​supplier.id == uid). */
  productCount: number;
  /** Orders placed (`customerId == uid`) or fulfilled (`supplierIds` contains uid). */
  orderCount: number;
}

export interface AdminUserDetail extends AdminUserRow {
  address: string;
  profilePicture: string;
  businessAddress: string;
  updatedAt: string | null;
}

export interface AdminStats {
  customers: number;
  suppliers: number;
  /** Users with a Firebase Auth account but no `users/{uid}` profile doc. */
  authOnlyAccounts: number;
  products: number;
  orders: number;
  /** Suppliers whose `verificationStatus` is 'pending'. */
  pendingSuppliers: number;
  /** Suppliers currently 'rejected'. */
  rejectedSuppliers: number;
  /** Suppliers whose profile `verificationStatus` is anything but 'verified'. */
  unverifiedSuppliers: number;
  /** `verification_applications` docs still at status 'pending' (IC queue). */
  pendingVerifications: number;
  /** Five newest profile documents, newest first. */
  recentUsers: Pick<
    AdminUserRow,
    'uid' | 'email' | 'name' | 'role' | 'isAdmin' | 'verificationStatus' | 'createdAt'
  >[];
}

/**
 * Supplier verification applications — `verification_applications/{uid}`
 * (document id IS the supplier's uid), written by the mobile app on submit.
 * File bytes live in Storage `verification/{uid}/{documentId}.{ext}` and are
 * admin-only (streamed by the API, never exposed through a public URL).
 */
export type ApplicationStatus = 'pending' | 'approved' | 'rejected';
export type VerificationDocumentKind = 'ic_front' | 'ic_back' | 'supporting';

export interface VerificationDocument {
  id: string;
  kind: VerificationDocumentKind;
  fileName: string;
  /** Stored value, re-validated at stream time against an image/PDF allowlist. */
  contentType: string;
  sizeBytes: number;
  /** `verification/{uid}/{id}.{ext}` — the only path the API will read. */
  storagePath: string;
  /** ISO-8601 UTC (Timestamp values are normalised on read). */
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

/** List-row shape — metadata only, never document bytes. */
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

/** PATCH /verification/applications/:uid response. */
export interface ReviewDecisionResult {
  application: VerificationApplication;
  /** users/{uid}.verificationStatus after the decision. */
  verificationStatus: 'verified' | 'rejected';
  /** products/{id}.supplier.verificationStatus rows kept in sync. */
  productsSynced: number;
}

// ── Photo-flag review queue (products whose photo contradicts the listing) ──

/** Admin decision stored at `products/{id}.vision.review`. */
export interface ProductFlagReview {
  status: 'open' | 'resolved';
  note?: string;
  /** ISO-8601. */
  reviewedAt: string;
  /** Admin UID that made the decision. */
  reviewedBy: string;
}

/** One flagged listing in the admin queue. */
export interface ProductFlagRow {
  productId: string;
  name: string;
  category: string;
  price: number;
  supplierId: string;
  image: string;
  /** Seller-written copy — what the photo allegedly contradicts. */
  description: string;
  /** The stored photo verdict (never fabricated here). */
  vision: {
    status: string;
    labels: string[];
    visualCategory: string;
    summary: string;
    mismatch: { flagged: boolean; reason: string };
    analyzedAt: string | null;
    model: string;
  };
  /** Absent ⇒ open. */
  review: ProductFlagReview | null;
}

/** GET /products/flags response. */
export interface ProductFlagListResult {
  items: ProductFlagRow[];
  total: number;
}

// ── Product catalogue admin (products/* routes) ────────────────────────────

/** One listing in the admin table. */
export interface AdminProductRow {
  productId: string;
  name: string;
  category: string;
  designStyle: string;
  /** int RM. */
  price: number;
  /** int RM; null when the seller never set a compare-at price. */
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

/** Detail payload — adds seller copy, shipping and read-only echoes. */
export interface AdminProductDetail extends AdminProductRow {
  description: string;
  images: string[];
  shippingEnabled: boolean;
  shippingFee: number;
  shippingLongDistanceNotice: boolean;
  /** products/{id}.ar3d.status — never written by the admin API. */
  ar3dStatus: string;
  /** products/{id}.vision.mismatch.flagged — the photo-flag queue's input. */
  visionFlagged: boolean;
  supplierPhone: string;
  supplierEmail: string;
  supplierVerificationStatus: string;
}

/** PATCH /products/:id body — the 12 seller-editable fields only. */
export interface ProductUpdate {
  name?: string;
  description?: string;
  category?: string;
  designStyle?: string;
  price?: number;
  /** null clears the compare-at price; omitted leaves it untouched. */
  originalPrice?: number | null;
  stock?: number;
  isActive?: boolean;
  isEcoFriendly?: boolean;
  shippingEnabled?: boolean;
  shippingFee?: number;
  shippingLongDistanceNotice?: boolean;
}

export interface ListProductsQuery {
  q?: string;
  category?: string;
  status: 'all' | 'active' | 'inactive';
  limit: number;
  offset: number;
}

export interface ListProductsResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminProductRow[];
}

/** DELETE /products/:id response. */
export interface DeleteProductResult {
  productId: string;
  deleted: boolean;
  /** Best-effort `reviews` subcollection count removed alongside. */
  reviewsDeleted: number;
}

// ── Orders admin (orders/* routes) ─────────────────────────────────────────

export type AdminOrderStatus = 'pending' | 'confirmed' | 'shipped' | 'delivered' | 'cancelled';

export interface AdminOrderItem {
  productId: string;
  name: string;
  image: string;
  /** int RM. */
  unitPrice: number;
  quantity: number;
  supplierId: string;
}

/** One order in the admin table. */
export interface AdminOrderRow {
  orderId: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  status: AdminOrderStatus;
  itemCount: number;
  /** int RM. */
  total: number;
  paymentMethod: string;
  createdAt: string | null;
  /** Forward transitions from the current status (empty on terminal). */
  nextStatuses: AdminOrderStatus[];
}

/** Detail payload — adds items, money breakdown and history. */
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
  /** ISO-8601 values keyed by status name. */
  statusHistory: Record<string, string>;
  /** `invoices` map keys only — invoice bodies are never re-serialized. */
  invoiceSupplierIds: string[];
}

export interface ListOrdersQuery {
  status?: AdminOrderStatus;
  q?: string;
  limit: number;
  offset: number;
}

export interface ListOrdersResult {
  total: number;
  limit: number;
  offset: number;
  items: AdminOrderRow[];
}
