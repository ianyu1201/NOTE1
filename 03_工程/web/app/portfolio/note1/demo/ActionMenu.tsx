"use client";

import { useEffect, useId, useRef, useState, type ReactNode } from "react";

/** Anchored menu shared by the title and receipt actions. */
export function ActionMenu({ label, trigger, children, align = "center", className = "", onOpen }: {
  label: string; trigger: ReactNode; children: (close: () => void) => ReactNode;
  align?: "center" | "right"; className?: string;
  onOpen?: () => void;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const id = useId();
  const close = () => { setOpen(false); document.getElementById(`${id}-trigger`)?.focus(); };
  useEffect(() => {
    if (!open) return;
    root.current?.querySelector<HTMLElement>('[role="menu"] button')?.focus();
    const outside = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);
  return <div className={`note1-action-anchor ${className}`} ref={root}
    onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false); }}
    onKeyDown={(event) => {
      if (event.key === "Escape") { event.stopPropagation(); close(); }
      if (!open && event.key === "ArrowDown") { event.preventDefault(); onOpen?.(); setOpen(true); return; }
      if (!open || !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const items = Array.from(root.current?.querySelectorAll<HTMLButtonElement>('[role="menu"] button:not(:disabled)') ?? []);
      const index = items.indexOf(document.activeElement as HTMLButtonElement);
      const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : (index + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items[next]?.focus();
    }}>
    <button id={`${id}-trigger`} ref={button} className={className.includes("title") ? "note1-title-trigger" : "note1-icon-btn"} type="button"
      aria-label={label} aria-haspopup="menu" aria-expanded={open} aria-controls={open ? id : undefined}
      onClick={() => { if (!open) onOpen?.(); setOpen(!open); }}>{trigger}</button>
    {open && <div id={id} role="menu" aria-label={label} className={`note1-action-menu is-${align}`}>{children(close)}</div>}
  </div>;
}
