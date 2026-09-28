/**
 * Local inline-SVG icon set — no CDN, no icon font, no dependency.
 * Stroke-based on a 24×24 grid; sized via the `size` prop (default 18).
 * Decorative by default (aria-hidden); pass `title` for standalone meaning.
 */
import type { ReactNode } from 'react';

export interface IconProps {
  size?: number;
  className?: string;
  title?: string;
}

function Svg({
  size = 18,
  className,
  title,
  children,
  strokeWidth = 1.75,
}: IconProps & { children: ReactNode; strokeWidth?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
      focusable="false"
    >
      {title ? <title>{title}</title> : null}
      {children}
    </svg>
  );
}

export const IconGrid = (p: IconProps) => (
  <Svg {...p}>
    <rect x="3" y="3" width="7" height="7" rx="1.5" />
    <rect x="14" y="3" width="7" height="7" rx="1.5" />
    <rect x="3" y="14" width="7" height="7" rx="1.5" />
    <rect x="14" y="14" width="7" height="7" rx="1.5" />
  </Svg>
);

export const IconUsers = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="9" cy="8" r="3.5" />
    <path d="M3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5" />
    <path d="M16 4.6a3.5 3.5 0 0 1 0 6.8" />
    <path d="M17.5 14.7c1.9.7 3.5 2.3 3.5 5.3" />
  </Svg>
);

export const IconStore = (p: IconProps) => (
  <Svg {...p}>
    <path d="M3.5 9 5 4h14l1.5 5" />
    <path d="M4.5 9h15v11h-15z" />
    <path d="M9.5 20v-6h5v6" />
  </Svg>
);

export const IconSearch = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m20 20-3.6-3.6" />
  </Svg>
);

export const IconCheck = (p: IconProps) => (
  <Svg {...p}>
    <path d="m4.5 12.5 5 5 10-11" />
  </Svg>
);

export const IconCheckCircle = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="m8 12.5 2.5 2.5L16 9.5" />
  </Svg>
);

export const IconX = (p: IconProps) => (
  <Svg {...p}>
    <path d="m6 6 12 12M18 6 6 18" />
  </Svg>
);

export const IconXCircle = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="m9 9 6 6M15 9l-6 6" />
  </Svg>
);

export const IconAlertTriangle = (p: IconProps) => (
  <Svg {...p}>
    <path d="M12 4.5 2.8 20h18.4L12 4.5Z" />
    <path d="M12 10v4.5" />
    <path d="M12 17.4h.01" />
  </Svg>
);

export const IconInfo = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 11v5" />
    <path d="M12 7.8h.01" />
  </Svg>
);

export const IconEye = (p: IconProps) => (
  <Svg {...p}>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
    <circle cx="12" cy="12" r="3" />
  </Svg>
);

export const IconEyeOff = (p: IconProps) => (
  <Svg {...p}>
    <path d="M4 4l16 16" />
    <path d="M9.9 5.9A9.8 9.8 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17.6 17.6 0 0 1-3.4 4.2" />
    <path d="M6.4 7.6A16.9 16.9 0 0 0 2.5 12S6 18.5 12 18.5c1.4 0 2.6-.3 3.7-.8" />
    <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
  </Svg>
);

export const IconLogout = (p: IconProps) => (
  <Svg {...p}>
    <path d="M9.5 21H5.5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
    <path d="m16 16 4-4-4-4" />
    <path d="M20 12H9.5" />
  </Svg>
);

export const IconRefresh = (p: IconProps) => (
  <Svg {...p}>
    <path d="M20 5v5h-5" />
    <path d="M4 19v-5h5" />
    <path d="M19.4 10A7.5 7.5 0 0 0 6.2 7.2L4 9.5" />
    <path d="M4.6 14a7.5 7.5 0 0 0 13.2 2.8L20 14.5" />
  </Svg>
);

export const IconSort = ({ dir, ...p }: IconProps & { dir?: 'asc' | 'desc' | null }) => (
  <Svg {...p} size={p.size ?? 13}>
    {dir === 'asc' ? (
      <>
        <path d="M12 19V6" />
        <path d="m6.5 11.5 5.5-5.5 5.5 5.5" />
      </>
    ) : dir === 'desc' ? (
      <>
        <path d="M12 5v13" />
        <path d="m6.5 12.5 5.5 5.5 5.5-5.5" />
      </>
    ) : (
      <>
        <path d="m8 9 4-4 4 4" />
        <path d="m8 15 4 4 4-4" />
      </>
    )}
  </Svg>
);

export const IconMail = (p: IconProps) => (
  <Svg {...p}>
    <rect x="3" y="5.5" width="18" height="13" rx="2" />
    <path d="m4 7.5 8 5.5 8-5.5" />
  </Svg>
);

export const IconLock = (p: IconProps) => (
  <Svg {...p}>
    <rect x="5" y="10.5" width="14" height="9.5" rx="2" />
    <path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" />
  </Svg>
);

export const IconTrash = (p: IconProps) => (
  <Svg {...p}>
    <path d="M4.5 6.5h15" />
    <path d="M9 6.5V5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5v1.5" />
    <path d="M6.5 6.5 7.4 19a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9l.9-12.5" />
    <path d="M10.5 10.5v6M13.5 10.5v6" />
  </Svg>
);

export const IconClock = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 2" />
  </Svg>
);

export const IconBox = (p: IconProps) => (
  <Svg {...p}>
    <path d="m12 3 8 4.5v9L12 21l-8-4.5v-9L12 3Z" />
    <path d="M4.3 7.7 12 12l7.7-4.3" />
    <path d="M12 12v9" />
  </Svg>
);

export const IconBag = (p: IconProps) => (
  <Svg {...p}>
    <path d="M5.5 8h13l-1 12.5h-11L5.5 8Z" />
    <path d="M9 8V6.5a3 3 0 0 1 6 0V8" />
  </Svg>
);

export const IconShield = (p: IconProps) => (
  <Svg {...p}>
    <path d="M12 3.5 5 6v5.5c0 4.4 3 7.6 7 9 4-1.4 7-4.6 7-9V6l-7-2.5Z" />
    <path d="m9 12 2 2 4-4.5" />
  </Svg>
);

export const IconUserCheck = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="9.5" cy="8" r="3.5" />
    <path d="M3.5 20c0-3.3 2.7-5.5 6-5.5 1.2 0 2.3.3 3.2.8" />
    <path d="m15 17 2 2 4-4.5" />
  </Svg>
);

export const IconInbox = (p: IconProps) => (
  <Svg {...p}>
    <path d="M4 13.5 6.5 5h11L20 13.5V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-4.5Z" />
    <path d="M4 13.5h4l1.5 2.5h5l1.5-2.5h4" />
  </Svg>
);
