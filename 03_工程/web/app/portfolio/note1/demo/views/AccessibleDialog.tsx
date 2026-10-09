"use client";

import { useEffect, useRef, type ReactNode, type RefObject } from "react";

const focusableSelector = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "textarea:not([disabled])",
  "select:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(", ");

function focusableIn(panel: HTMLElement) {
  return Array.from(panel.querySelectorAll<HTMLElement>(focusableSelector)).filter(
    (element) => element.tabIndex >= 0 && element.getClientRects().length > 0,
  );
}

export function AccessibleDialog({
  children,
  className,
  initialFocusRef,
  onClose,
  returnFocusRef,
  titleId,
}: {
  children: ReactNode;
  className: string;
  initialFocusRef?: RefObject<HTMLElement | null>;
  onClose: () => void;
  returnFocusRef: RefObject<HTMLElement | null>;
  titleId: string;
}) {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const composingRef = useRef(false);
  const lastCompositionEndRef = useRef(-Infinity);
  const onCloseRef = useRef(onClose);

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;

    const previousFocus = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
    const returnFocus = returnFocusRef.current;
    let lastFocus: HTMLElement | null = null;
    const firstFocus = () => focusableIn(panel)[0] ?? panel;

    function onFocusIn(event: FocusEvent) {
      const target = event.target;
      if (target instanceof HTMLElement && panel!.contains(target)) {
        lastFocus = target;
        return;
      }
      (lastFocus?.isConnected ? lastFocus : firstFocus()).focus({ preventScroll: true });
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        if (
          event.isComposing ||
          event.keyCode === 229 ||
          composingRef.current ||
          performance.now() - lastCompositionEndRef.current < 100
        ) return;
        event.preventDefault();
        event.stopPropagation();
        onCloseRef.current();
        return;
      }

      if (event.key !== "Tab" || event.altKey || event.ctrlKey || event.metaKey) return;
      const focusable = focusableIn(panel!);
      const first = focusable[0] ?? panel!;
      const last = focusable[focusable.length - 1] ?? panel!;
      const active = document.activeElement;
      if (!panel!.contains(active) || active === panel) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      } else if (event.shiftKey && active === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("focusin", onFocusIn, true);
    document.addEventListener("keydown", onKeyDown, true);
    (initialFocusRef?.current ?? firstFocus()).focus({ preventScroll: true });

    return () => {
      document.removeEventListener("focusin", onFocusIn, true);
      document.removeEventListener("keydown", onKeyDown, true);
      const target = returnFocus?.isConnected && !returnFocus.hasAttribute("disabled")
        ? returnFocus
        : previousFocus?.isConnected && previousFocus !== document.body
          ? previousFocus
          : null;
      target?.focus({ preventScroll: true });
    };
  }, [initialFocusRef, returnFocusRef]);

  return (
    <div
      aria-labelledby={titleId}
      aria-modal="true"
      className={className}
      onCompositionEnd={() => {
        composingRef.current = false;
        lastCompositionEndRef.current = performance.now();
      }}
      onCompositionStart={() => { composingRef.current = true; }}
      ref={panelRef}
      role="dialog"
      tabIndex={-1}
    >
      {children}
    </div>
  );
}
