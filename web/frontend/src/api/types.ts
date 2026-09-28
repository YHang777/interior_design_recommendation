/** Mirrors the backend's `web/backend/src/types/models.ts`, which in turn
 * mirrors the Flutter app's Firestore schema. */

export type UserRole = 'homeowner' | 'supplier' | 'unknown';
export type VerificationStatus = 'verified' | 'pending' | 'rejected';

export interface AdminUserRow {
  uid: string;
  email: string;
  name: string;
  role: UserRole;
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
    'uid' | 'email' | 'name' | 'role' | 'verificationStatus' | 'createdAt'
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
