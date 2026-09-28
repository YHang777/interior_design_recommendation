import type { ReactNode } from 'react';
import { IconAlertTriangle, IconInbox, IconRefresh, IconSort } from './icons';

export interface Column<T> {
  key: string;
  header: string;
  render: (row: T) => ReactNode;
  /** Presence makes the header sortable; used to derive a comparable value. */
  sortValue?: (row: T) => string | number;
  width?: string;
  align?: 'left' | 'right';
}

export interface SortState {
  key: string;
  dir: 'asc' | 'desc';
}

interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  emptyMessage: string;
  loading?: boolean;
  error?: string | null;
  onRetry?: () => void;
  sort?: SortState | null;
  onSortChange?: (key: string) => void;
  /** Skeleton rows shown while `loading` (0 disables). */
  skeletonRows?: number;
}

/**
 * Generic admin data table: sticky header, sortable columns, zebra + hover
 * rows, skeleton loading, error-with-retry and an illustrated empty state.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  emptyMessage,
  loading,
  error,
  onRetry,
  sort,
  onSortChange,
  skeletonRows = 6,
}: DataTableProps<T>) {
  const colCount = columns.length;

  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            {columns.map((c) => {
              const active = sort?.key === c.key ? sort.dir : null;
              const ariaSort = !c.sortValue
                ? undefined
                : active === 'asc'
                  ? 'ascending'
                  : active === 'desc'
                    ? 'descending'
                    : 'none';
              return (
                <th
                  key={c.key}
                  style={{ width: c.width, textAlign: c.align ?? 'left' }}
                  aria-sort={ariaSort}
                >
                  {c.sortValue && onSortChange ? (
                    <button
                      type="button"
                      className="th-sort"
                      onClick={() => onSortChange(c.key)}
                      title={`Sort by ${c.header.toLowerCase()}`}
                    >
                      {c.header}
                      <IconSort dir={active} />
                    </button>
                  ) : (
                    c.header
                  )}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {loading ? (
            Array.from({ length: skeletonRows }, (_, r) => (
              <tr key={`skel-${r}`} aria-hidden="true">
                {columns.map((c, i) => (
                  <td key={c.key}>
                    <span
                      className="skel"
                      style={{
                        width: i === 0 ? '70%' : i === columns.length - 1 ? '55%' : `${45 + ((r + i) % 3) * 15}%`,
                      }}
                    />
                  </td>
                ))}
              </tr>
            ))
          ) : error ? (
            <tr>
              <td className="table-state error-state" colSpan={colCount}>
                <div className="state-inner">
                  <span className="state-icon">
                    <IconAlertTriangle size={28} />
                  </span>
                  <strong>Couldn&apos;t load this table</strong>
                  <span>{error}</span>
                  {onRetry && (
                    <button type="button" className="btn btn-secondary btn-sm" onClick={onRetry}>
                      <IconRefresh size={14} />
                      Retry
                    </button>
                  )}
                </div>
              </td>
            </tr>
          ) : rows.length === 0 ? (
            <tr>
              <td className="table-state" colSpan={colCount}>
                <div className="state-inner">
                  <span className="state-icon">
                    <IconInbox size={28} />
                  </span>
                  <span>{emptyMessage}</span>
                </div>
              </td>
            </tr>
          ) : (
            rows.map((row) => (
              <tr key={rowKey(row)}>
                {columns.map((c) => (
                  <td key={c.key} style={{ textAlign: c.align ?? 'left' }}>
                    {c.render(row)}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
