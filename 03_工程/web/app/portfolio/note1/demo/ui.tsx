"use client";

import {
  useEffect,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type ReactNode,
  type SVGProps,
} from "react";

// ---------------------------------------------------------------------------
// 日期与格式化
// ---------------------------------------------------------------------------

const timeFmt = new Intl.DateTimeFormat("zh-CN", {
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});
const dateTimeFmt = new Intl.DateTimeFormat("zh-CN", {
  month: "long",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hour12: false,
});
const groupFmt = new Intl.DateTimeFormat("zh-CN", {
  month: "long",
  day: "numeric",
  weekday: "long",
});

export function formatTime(iso: string): string {
  return timeFmt.format(new Date(iso));
}

export function formatDisplay(iso: string): string {
  const date = new Date(iso);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const startOfYesterday = startOfToday - 24 * 60 * 60 * 1000;
  const time = date.getTime();
  if (time >= startOfToday) return `今天 ${timeFmt.format(date)}`;
  if (time >= startOfYesterday) return `昨天 ${timeFmt.format(date)}`;
  return dateTimeFmt.format(date);
}

export function formatGroup(iso: string): string {
  const date = new Date(iso);
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const startOfYesterday = startOfToday - 24 * 60 * 60 * 1000;
  const time = date.getTime();
  if (time >= startOfToday) return "今天";
  if (time >= startOfYesterday) return "昨天";
  return groupFmt.format(date);
}

export function formatBytes(size: number): string {
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatDuration(ms: number): string {
  const totalMinutes = Math.max(0, Math.round(ms / 60000));
  if (totalMinutes < 60) return `${totalMinutes} 分钟`;
  return `${Math.floor(totalMinutes / 60)} 小时 ${totalMinutes % 60} 分`;
}

export function formatDateTime(iso: string): string {
  const date = new Date(iso);
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

export function formatFullDate(iso: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(new Date(iso));
}

// ---------------------------------------------------------------------------
// 图标（stroke 风格，24×24 视口）
// ---------------------------------------------------------------------------

function Svg({
  children,
  size = 18,
  ...props
}: { children: ReactNode; size?: number } & SVGProps<SVGSVGElement>) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      {...props}
    >
      {children}
    </svg>
  );
}

export type IconName =
  | "sparkles"
  | "cards"
  | "folder"
  | "receipt"
  | "plus"
  | "search"
  | "history"
  | "trash"
  | "settings"
  | "chevron-left"
  | "chevron-right"
  | "chevron-up"
  | "chevron-down"
  | "close"
  | "menu"
  | "check"
  | "sort"
  | "filter"
  | "select"
  | "download"
  | "upload"
  | "doc"
  | "image"
  | "paperclip"
  | "pencil"
  | "more"
  | "undo"
  | "return";

export function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  const common = {
    fill: "none",
    stroke: "currentColor",
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    strokeWidth: 1.7,
  };
  switch (name) {
    case "sort":
      return <Svg size={size} {...common}><path d="M7 20V4m-4 4 4-4 4 4M17 4v16m-4-4 4 4 4-4" /></Svg>;
    case "filter":
      return <Svg size={size} {...common}><path d="M3 4h18l-7 8v8l-4-2v-6z" /></Svg>;
    case "select":
      return <Svg size={size} {...common}><path d="M21 11a9 9 0 1 1-6-8M8 10l4 4 9-10" /></Svg>;
    case "sparkles":
      return (
        <Svg size={size} {...common}>
          <path d="M12 3l1.8 4.6L18.5 9l-4.7 1.4L12 15l-1.8-4.6L5.5 9l4.7-1.4z" />
          <path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z" />
        </Svg>
      );
    case "cards":
      return (
        <Svg size={size} {...common}>
          <rect height="13" rx="2" width="13" x="8" y="8" />
          <path d="M3.5 7.5V6a2 2 0 0 1 2-2H19a2 2 0 0 1 2 2v11" />
        </Svg>
      );
    case "folder":
      return (
        <Svg size={size} {...common}>
          <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
        </Svg>
      );
    case "receipt":
      return (
        <Svg size={size} {...common}>
          <path d="M5 3h14v18l-2.5-1.5L14 21l-2-1.5L10 21l-2.5-1.5L5 21z" />
          <path d="M9 8h6M9 12h6" />
        </Svg>
      );
    case "plus":
      return (
        <Svg size={size} {...common}>
          <path d="M12 5v14M5 12h14" />
        </Svg>
      );
    case "search":
      return (
        <Svg size={size} {...common}>
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        </Svg>
      );
    case "history":
      return (
        <Svg size={size} {...common}>
          <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
          <path d="M3 3v5h5" />
          <path d="M12 7v5l3 2" />
        </Svg>
      );
    case "trash":
      return (
        <Svg size={size} {...common}>
          <path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
          <path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13" />
        </Svg>
      );
    case "settings":
      return (
        <Svg size={size} {...common}>
          <circle cx="12" cy="12" r="3" />
          <path d="M12 2.5v2M12 19.5v2M4.5 12h-2M21.5 12h-2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M18.7 5.3l-1.4 1.4M6.7 17.3l-1.4 1.4" />
        </Svg>
      );
    case "chevron-left":
      return (
        <Svg size={size} {...common}>
          <path d="m15 5-7 7 7 7" />
        </Svg>
      );
    case "chevron-right":
      return (
        <Svg size={size} {...common}>
          <path d="m9 5 7 7-7 7" />
        </Svg>
      );
    case "chevron-up":
      return (
        <Svg size={size} {...common}>
          <path d="m5 15 7-7 7 7" />
        </Svg>
      );
    case "chevron-down":
      return (
        <Svg size={size} {...common}>
          <path d="m5 9 7 7 7-7" />
        </Svg>
      );
    case "close":
      return (
        <Svg size={size} {...common}>
          <path d="M6 6l12 12M18 6 6 18" />
        </Svg>
      );
    case "menu":
      return (
        <Svg size={size} {...common}>
          <path d="M4 6h16M4 12h16M4 18h16" />
        </Svg>
      );
    case "check":
      return (
        <Svg size={size} {...common}>
          <path d="m5 12 5 5L20 7" />
        </Svg>
      );
    case "download":
      return (
        <Svg size={size} {...common}>
          <path d="M12 3v12M7 10l5 5 5-5" />
          <path d="M4 20h16" />
        </Svg>
      );
    case "upload":
      return (
        <Svg size={size} {...common}>
          <path d="M12 15V3M7 8l5-5 5 5" />
          <path d="M4 20h16" />
        </Svg>
      );
    case "doc":
      return (
        <Svg size={size} {...common}>
          <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
          <path d="M14 3v5h5" />
        </Svg>
      );
    case "image":
      return (
        <Svg size={size} {...common}>
          <rect height="16" rx="2" width="18" x="3" y="5" />
          <circle cx="8.5" cy="10" r="1.5" />
          <path d="m7 17 4-4 3 3 3-3 3 4" />
        </Svg>
      );
    case "paperclip":
      return (
        <Svg size={size} {...common}>
          <path d="m20 11-7.5 7.5a4.5 4.5 0 1 1-6.4-6.4L14.5 4.5a3 3 0 1 1 4.2 4.2l-8.4 8.4a1.5 1.5 0 1 1-2.1-2.1l7.4-7.4" />
        </Svg>
      );
    case "pencil":
      return (
        <Svg size={size} {...common}>
          <path d="M4 20h4L20 8l-4-4L4 16z" />
          <path d="M13 5l4 4" />
        </Svg>
      );
    case "more":
      return (
        <Svg size={size} {...common}>
          <circle cx="5" cy="12" r="1.4" fill="currentColor" stroke="none" />
          <circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none" />
          <circle cx="19" cy="12" r="1.4" fill="currentColor" stroke="none" />
        </Svg>
      );
    case "undo":
      return (
        <Svg size={size} {...common}>
          <path d="M9 14 4 9l5-5" />
          <path d="M4 9h10a6 6 0 1 1 0 12h-3" />
        </Svg>
      );
    case "return":
      return (
        <Svg size={size} {...common}>
          <path d="m9 10-4 4 4 4" />
          <path d="M5 14h10a5 5 0 0 0 0-10h-4" />
        </Svg>
      );
  }
}

// ---------------------------------------------------------------------------
// 小型基础组件
// ---------------------------------------------------------------------------

export function GlassButton({
  label,
  icon,
  onClick,
  className = "",
  ...rest
}: {
  label: string;
  icon: IconName;
  onClick?: () => void;
  className?: string;
} & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      aria-label={label}
      className={`note1-icon-btn ${className}`}
      onClick={onClick}
      type="button"
      {...rest}
    >
      <Icon name={icon} />
    </button>
  );
}

export function EmptyState({
  icon,
  title,
  message,
}: {
  icon: IconName;
  title: string;
  message?: string;
}) {
  return (
    <div className="note1-empty">
      <span className="note1-empty-icon">
        <Icon name={icon} size={30} />
      </span>
      <h2>{title}</h2>
      {message ? <p>{message}</p> : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// 路由与瞬态提示
// ---------------------------------------------------------------------------

export type RouteName =
  | "inspirations"
  | "cards"
  | "collections"
  | "receipts"
  | "collection"
  | "receipt"
  | "search"
  | "history"
  | "trash"
  | "settings";

export interface Route {
  name: RouteName;
  id?: string;
}

export function parseRoute(hash: string): Route {
  const cleaned = hash.replace(/^#/, "");
  const parts = cleaned.split("/").filter(Boolean);
  if (parts.length === 0) return { name: "inspirations" };
  switch (parts[0]) {
    case "cards":
      return { name: "cards" };
    case "collections":
      return parts[1] ? { name: "collection", id: parts[1] } : { name: "collections" };
    case "receipts":
      return parts[1] ? { name: "receipt", id: parts[1] } : { name: "receipts" };
    case "search":
      return { name: "search" };
    case "history":
      return { name: "history" };
    case "trash":
      return { name: "trash" };
    case "settings":
      return { name: "settings" };
    default:
      return { name: "inspirations" };
  }
}

export function routeToHash(route: Route): string {
  switch (route.name) {
    case "inspirations":
      return "#/";
    case "collection":
    case "receipt":
      return `#/${route.name === "collection" ? "collections" : "receipts"}/${route.id}`;
    default:
      return `#/${route.name}`;
  }
}

export function useBlobUrl(
  loadUrl: (id: string) => Promise<string | undefined>,
  id: string | undefined,
): string | undefined {
  const [url, setUrl] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    let revoked: string | undefined;
    void loadUrl(id).then((value) => {
      if (cancelled) return;
      revoked = value;
      setUrl(value);
    });
    return () => {
      cancelled = true;
      if (revoked) URL.revokeObjectURL(revoked);
    };
  }, [loadUrl, id]);
  return url;
}

export function useHashRoute(): { route: Route; navigate: (route: Route) => void } {
  const [hash, setHash] = useState<string>(() =>
    typeof window !== "undefined" ? window.location.hash : "",
  );
  useEffect(() => {
    const onChange = () => setHash(window.location.hash);
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  const navigate = (route: Route) => {
    const nextHash = routeToHash(route);
    // Avoid Vinext's RSC popstate navigation on static hosting. The module URL
    // stays shareable, while Back returns to the page visited before NOTE1.
    if (window.location.hash !== nextHash) window.history.replaceState(window.history.state, "", nextHash);
    setHash(nextHash);
  };
  return { route: parseRoute(hash), navigate };
}

export interface Toast {
  message: string;
  action?: { label: string; run: () => void };
}

export function useToast(): {
  toast: Toast | null;
  showToast: (message: string, action?: Toast["action"]) => void;
  dismiss: () => void;
} {
  const [toast, setToast] = useState<Toast | null>(null);
  const timer = useRef<number | null>(null);
  const dismiss = () => {
    if (timer.current) window.clearTimeout(timer.current);
    setToast(null);
  };
  const showToast = (message: string, action?: Toast["action"]) => {
    if (timer.current) window.clearTimeout(timer.current);
    setToast({ message, action });
    timer.current = window.setTimeout(() => setToast(null), action ? 6000 : 2600);
  };
  useEffect(
    () => () => {
      if (timer.current) window.clearTimeout(timer.current);
    },
    [],
  );
  return { toast, showToast, dismiss };
}
