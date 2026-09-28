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
    'uid' | 'email' | 'name' | 'role' | 'verificationStatus' | 'createdAt'
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
