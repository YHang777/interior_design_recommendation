import type { AdminOrderStatus, ApplicationStatus, UserRole, VerificationStatus } from '../api/types';

const STATUS_LABEL: Record<string, string> = {
  verified: 'Verified',
  pending: 'Pending',
  rejected: 'Rejected',
  unknown: 'No profile',
};

/** Pill for users/{uid}.verificationStatus. */
export function StatusBadge({ status }: { status: VerificationStatus | 'unknown' }) {
  return <span className={`badge badge-status-${status}`}>{STATUS_LABEL[status] ?? status}</span>;
}

const ROLE_LABEL: Record<UserRole, string> = {
  homeowner: 'Customer',
  supplier: 'Supplier',
  unknown: 'Auth only',
};

/** Pill for users/{uid}.role (homeowner | supplier | unknown). */
export function RoleBadge({ role }: { role: UserRole }) {
  return <span className={`badge badge-role-${role}`}>{ROLE_LABEL[role]}</span>;
}

/** Display-only pill for admin accounts (claim or ADMIN_UIDS allowlist). */
export function AdminBadge() {
  return <span className="badge badge-admin">Admin</span>;
}

/** Role pill + optional Admin pill on one row. */
export function RoleBadges({ role, isAdmin }: { role: UserRole; isAdmin?: boolean }) {
  return (
    <span className="badge-row">
      <RoleBadge role={role} />
      {isAdmin && <AdminBadge />}
    </span>
  );
}

const APPLICATION_LABEL: Record<ApplicationStatus, string> = {
  pending: 'Pending',
  approved: 'Approved',
  rejected: 'Rejected',
};

/** Pill for verification_applications/{uid}.status. */
export function ApplicationStatusBadge({ status }: { status: ApplicationStatus }) {
  const tone = status === 'approved' ? 'verified' : status === 'rejected' ? 'rejected' : 'pending';
  return <span className={`badge badge-status-${tone}`}>{APPLICATION_LABEL[status]}</span>;
}

const ORDER_LABEL: Record<AdminOrderStatus, string> = {
  pending: 'Pending',
  confirmed: 'Confirmed',
  shipped: 'Shipped',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
};

/** Pill for orders/{id}.status. */
export function OrderStatusBadge({ status }: { status: AdminOrderStatus }) {
  return <span className={`badge badge-status-${status}`}>{ORDER_LABEL[status]}</span>;
}
