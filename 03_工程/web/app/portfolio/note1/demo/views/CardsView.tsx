"use client";

import {
  useMemo,
  useEffect,
  useRef,
  useState,
  type KeyboardEvent,
  type PointerEvent as ReactPointerEvent,
} from "react";
import type { Inspiration } from "../domain/types";
import type { AssignmentUndoToken } from "../store";
import { useNote1 } from "../Note1Provider";
import { useApp } from "../app-context";
import { EmptyState, Icon } from "../ui";
import { adjacentCardIndex, cardGesture, cardWheel, settleCard } from "../card-gesture";

export function CardsView() {
  const { store, state } = useNote1();
  const { showToast, openEditor } = useApp();
  const entries = useMemo(
    () =>
      state.inspirations.filter((i) => i.collectionId === null && i.cardFlowState === "visible"),
    [state.inspirations],
  );
  const [currentId, setCurrentId] = useState<string | null>(entries[0]?.id ?? null);
  const [assigning, setAssigning] = useState(false);
  const [newName, setNewName] = useState("");
  const rootRef = useRef<HTMLDivElement | null>(null);
  const assignTriggerRef = useRef<HTMLButtonElement | null>(null);
  const assignPanelRef = useRef<HTMLDivElement | null>(null);
  const gesture = useRef<{ x: number; y: number; moved: boolean; axis: "x" | "y" | null; lastX: number; lastY: number; time: number; vx: number; vy: number; localX: number } | null>(null);
  const cancelSettle = useRef<(() => void) | null>(null);
  const wheel = useRef({ total: 0, last: 0, consumed: false });
  const suppressClick = useRef(false);
  const busy = useRef(false);
  const tuckMotion = useRef<Animation | null>(null);
  const [departure, setDeparture] = useState<{ text: string; direction: number; x: number; y: number } | null>(null);

  const foundIndex = entries.findIndex((i) => i.id === currentId);
  const activeIndex = foundIndex >= 0 ? foundIndex : 0;
  const current = entries[activeIndex];

  function go(delta: number) {
    if (entries.length === 0 || busy.current || tuckMotion.current) return;
    const next = adjacentCardIndex(activeIndex, delta, entries.length);
    if (next === activeIndex) return;
    cancelSettle.current?.();
    const card = rootRef.current?.querySelector(".note1-card:not(.note1-card-departure)");
    const matrix = card ? new DOMMatrixReadOnly(getComputedStyle(card).transform) : null;
    setDeparture({ text: current.text, direction: delta, x: matrix?.m41 ?? 0, y: matrix?.m42 ?? 0 });
    setCurrentId(entries[next].id);
  }

  useEffect(() => () => { cancelSettle.current?.(); tuckMotion.current?.cancel(); }, []);
  useEffect(() => {
    if (!assigning) return;
    const panel = assignPanelRef.current;
    const trigger = assignTriggerRef.current;
    panel?.querySelector<HTMLButtonElement>(".note1-icon-btn")?.focus();
    const onDialogKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.isComposing || event.keyCode === 229) return;
      if (event.key === "Escape") {
        event.preventDefault();
        setAssigning(false);
        return;
      }
      if (event.key !== "Tab" || !panel) return;
      const focusable = [...panel.querySelectorAll<HTMLElement>("button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])")]
        .filter((element) => element.getClientRects().length > 0);
      if (focusable.length === 0) {
        event.preventDefault();
        panel.focus();
        return;
      }
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (!panel.contains(document.activeElement) || (event.shiftKey && document.activeElement === first)) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", onDialogKeyDown, true);
    return () => {
      document.removeEventListener("keydown", onDialogKeyDown, true);
      window.requestAnimationFrame(() => trigger?.focus());
    };
  }, [assigning]);


  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const onWheel = (event: WheelEvent) => {
      if (assigning || gesture.current || event.ctrlKey || Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
      if (!(event.target instanceof Element) || !event.target.closest(".note1-cards-stage")) return;
      if (event.target.closest(".note1-card-text") && event.target.closest(".note1-card-text")!.scrollHeight > event.target.closest(".note1-card-text")!.clientHeight) return;
      event.preventDefault();
      const delta = cardWheel(wheel.current, event.deltaY, event.deltaMode, event.timeStamp);
      if (delta) go(delta);
    };
    root.addEventListener("wheel", onWheel, { passive: false });
    return () => root.removeEventListener("wheel", onWheel);
  });

  async function tuck(item: Inspiration) {
    if (busy.current) return;
    busy.current = true;
    const next = entries[activeIndex + 1] ?? entries[activeIndex - 1];
    try {
      await store.tuckAway(item.id);
      setCurrentId(next?.id ?? null);
      showToast("已收起", {
        label: "撤回",
        run: async () => {
          try { await store.returnToCardFlow(item.id); setCurrentId(item.id); }
          catch { showToast("放回没有完成，请重试。"); }
        },
      });
    } catch { showToast("收起没有完成，灵感已保留。"); }
    finally { busy.current = false; }
  }

  async function assignTo(collectionId: string) {
    if (!current) return;
    let token: AssignmentUndoToken | null = null;
    try {
      token = await store.assignToCollection(current.id, collectionId);
      setCurrentId(entries[activeIndex + 1]?.id ?? null);
      setAssigning(false);
      if (token) {
        showToast("已归入构思集。", {
          label: "撤回",
          run: () => void store.undoAssignment(token!),
        });
      }
    } catch {
      showToast("归入没有完成。");
    }
  }

  async function createAndAssign() {
    if (!current) return;
    try {
      const result = await store.createCollectionAndAssign(
        current.id,
        newName.trim() || undefined,
      );
      setCurrentId(entries[activeIndex + 1]?.id ?? null);
      setAssigning(false);
      setNewName("");
      showToast("已归入新构思集。", {
        label: "撤回",
        run: () => void store.undoAssignment(result.undoToken),
      });
    } catch {
      showToast("归入没有完成。");
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (assigning) return;
    if (event.target instanceof HTMLElement && event.target.closest("button, input, textarea")) return;
    if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
      event.preventDefault();
      go(-1);
    } else if (event.key === "ArrowDown" || event.key === "ArrowRight") {
      event.preventDefault();
      go(1);
    }
  }

  function onPointerDown(event: ReactPointerEvent<HTMLDivElement>) {
    if (!event.isPrimary || event.button !== 0 || busy.current || tuckMotion.current) return;
    if (event.pointerType === "mouse" && (event.target as Element).closest(".note1-card-text")) return;
    cancelSettle.current?.();
    const matrix = new DOMMatrixReadOnly(getComputedStyle(event.currentTarget).transform);
    event.currentTarget.style.animation = "none";
    event.currentTarget.style.setProperty("--swipe-dx", `${matrix.m41}px`);
    event.currentTarget.style.setProperty("--swipe-dy", `${matrix.m42}px`);
    gesture.current = { x: event.clientX - matrix.m41, y: event.clientY - matrix.m42, moved: false, axis: null, lastX: event.clientX, lastY: event.clientY, time: event.timeStamp, vx: 0, vy: 0, localX: event.clientX - event.currentTarget.getBoundingClientRect().left };
    suppressClick.current = false;
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: ReactPointerEvent<HTMLDivElement>) {
    const start = gesture.current;
    if (!start) return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    if (Math.max(Math.abs(dx), Math.abs(dy)) < 8) return;
    start.moved = true;
    const dt = Math.max(1, event.timeStamp - start.time) / 1000;
    start.vx = (event.clientX - start.lastX) / dt; start.vy = (event.clientY - start.lastY) / dt;
    start.lastX = event.clientX; start.lastY = event.clientY; start.time = event.timeStamp;
    if (!start.axis && Math.max(Math.abs(dx), Math.abs(dy)) >= 14) {
      if (Math.abs(dy) > Math.abs(dx) * 1.18) start.axis = "y";
      else if (Math.abs(dx) > Math.abs(dy) * 1.35) start.axis = "x";
    }
    const el = event.currentTarget;
    el.classList.add("is-dragging");
    const vertical = start.axis === "y";
    const edge = (dy > 0 && activeIndex === 0) || (dy < 0 && activeIndex === entries.length - 1);
    el.style.setProperty("--swipe-dx", `${start.axis === "x" && start.localX > 24 ? Math.min(0, dx) : 0}px`);
    el.style.setProperty("--swipe-dy", `${vertical ? (edge ? dy * 180 * .55 / (180 + .55 * Math.abs(dy)) : dy) : 0}px`);
    rootRef.current?.style.setProperty("--tuck-progress", String(start.axis === "x" ? Math.min(1, Math.max(0, (-dx - 36) / 88)) : 0));
    rootRef.current?.style.setProperty("--drag-progress", String(Math.min(Math.abs(dy) / 250, 1)));
  }

  function finishPointer(event: ReactPointerEvent<HTMLDivElement>, cancel = false) {
    const start = gesture.current;
    gesture.current = null;
    event.currentTarget.classList.remove("is-dragging");
    rootRef.current?.style.setProperty("--drag-progress", "0");
    rootRef.current?.style.setProperty("--tuck-progress", "0");
    if (!start) return;
    suppressClick.current = start.moved;
    const fresh = event.timeStamp - start.time < 100;
    const vx = fresh ? start.vx : 0, vy = fresh ? start.vy : 0;
    const action = cancel ? "cancel" : cardGesture(start.axis === "y" ? 0 : event.clientX - start.x, start.axis === "x" ? 0 : event.clientY - start.y, vx, vy);
    const atEdge = action === "next" && activeIndex === entries.length - 1 || action === "previous" && activeIndex === 0;
    if (action === "cancel" || atEdge || (action === "tuck" && start.localX <= 24)) cancelSettle.current = settleCard(event.currentTarget, vx, vy);
    if (action === "next") go(1);
    if (action === "previous") go(-1);
    if (action === "tuck" && start.localX > 24 && current) {
      const el = event.currentTarget;
      const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
      const animation = el.animate([{ transform: getComputedStyle(el).transform, opacity: 1 }, { transform: reduced ? getComputedStyle(el).transform : "translateX(-420px) rotate(-6deg)", opacity: 0 }], { duration: reduced ? 100 : 220, easing: "ease-out", fill: "forwards" });
      tuckMotion.current = animation;
      void animation.finished.then(async () => { await tuck(current); animation.cancel(); cancelSettle.current = settleCard(el); }).catch(() => {}).finally(() => { tuckMotion.current = null; });
    }
  }

  if (entries.length === 0) {
    return (
      <div className="note1-page-body note1-page-body-scroll">
        <EmptyState
          icon="cards"
          message="记录灵感后会出现在这里。"
          title="还没有可以预览的灵感"
        />
      </div>
    );
  }

  return (
    <div
      className="note1-page-body note1-cards"
      onKeyDown={onKeyDown}
      ref={rootRef}
      style={{ "--swipe-dx": "0px" } as React.CSSProperties}
      tabIndex={0}
    >
      <div className="note1-cards-stage">
        <span className="note1-tuck-hint" aria-hidden="true">松手收起</span>
        {departure && <div key={`departure-${current.id}`} aria-hidden="true" className="note1-card note1-card-departure" style={{ "--direction": departure.direction, "--swipe-dx": `${departure.x}px`, "--swipe-dy": `${departure.y}px` } as React.CSSProperties} onAnimationEnd={() => setDeparture(null)}><p className="note1-card-text">{departure.text}</p></div>}
        {entries.length > 1 && <div className="note1-card-back" aria-hidden="true" />}
        <div
          key={current.id}
          className={`note1-card ${departure ? "note1-card-arrival" : ""}`}
          style={{ "--direction": departure?.direction ?? 1 } as React.CSSProperties}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={(event) => finishPointer(event)}
          onPointerCancel={(event) => finishPointer(event, true)}
          onLostPointerCapture={(event) => finishPointer(event, true)}
          onClick={() => { if (!suppressClick.current && !tuckMotion.current && current && !window.getSelection()?.toString()) openEditor(current.id); suppressClick.current = false; }}
          onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); if (current) openEditor(current.id); } }}
          role="button"
          tabIndex={0}
          aria-label={`编辑灵感：${current?.text.trim() || "未命名灵感"}`}
        >
          <p className="note1-card-text">{current?.text.trim() || "未命名灵感"}</p>
          {current && current.resourceIds.length > 0 ? (
            <span className="note1-card-attachments">
              <Icon name="paperclip" size={15} />
              {current.resourceIds.length} 个附件
            </span>
          ) : null}
        </div>
      </div>

      <div className="note1-cards-controls">
        <p className="note1-cards-hint">上下滑动或滚轮切换 · 左滑收起</p>
        <p className="note1-cards-counter" aria-live="polite">{activeIndex + 1} / {entries.length}</p>
        <button className="note1-text-btn" onClick={() => setAssigning(true)} ref={assignTriggerRef} type="button"><Icon name="folder" />归入构思集</button>
      <div className="note1-cards-actions">
        <button
          className="note1-text-btn"
          onClick={() => go(-1)}
          disabled={activeIndex === 0}
          type="button"
        >
          <Icon name="chevron-up" /> 上一张
        </button>
        <button
          className="note1-text-btn"
          onClick={() => current && void tuck(current)}
          type="button"
        >
          收起
        </button>
        <button className="note1-text-btn" disabled={activeIndex === entries.length - 1} onClick={() => go(1)} type="button">
          下一张 <Icon name="chevron-down" />
        </button>
      </div>
      </div>

      {assigning ? (
        <div className="note1-overlay">
          <div aria-label="归入构思集" aria-modal="true" className="note1-overlay-panel note1-assign-panel" ref={assignPanelRef} role="dialog" tabIndex={-1}>
            <header className="note1-page-header">
              <div className="note1-header-side">
                <button
                  aria-label="关闭构思集选择面板"
                  className="note1-icon-btn"
                  onClick={() => setAssigning(false)}
                  type="button"
                >
                  <Icon name="close" />
                </button>
              </div>
              <span className="note1-page-title">归入构思集</span>
              <div className="note1-header-side note1-header-side-right" />
            </header>
            <div className="note1-assign-body">
              <p className="note1-assign-current">“{current?.text.trim() || "未命名灵感"}”</p>

              <h3>已有构思集</h3>
              {state.collections.filter((c) => c.currentRoundId !== null).length === 0 ? (
                <p className="note1-muted">还没有进行中的构思集。</p>
              ) : (
                <div className="note1-assign-list">
                  {state.collections
                    .filter((c) => c.currentRoundId !== null)
                    .map((collection) => {
                      const count =
                        state.rounds.find((r) => r.id === collection.currentRoundId)
                          ?.memberIds.length ?? 0;
                      return (
                        <button
                          className="note1-assign-option"
                          key={collection.id}
                          onClick={() => void assignTo(collection.id)}
                          type="button"
                        >
                          <Icon name="folder" />
                          <span>{collection.name}</span>
                          <small>{count} 条灵感</small>
                        </button>
                      );
                    })}
                </div>
              )}

              <h3>新建构思集</h3>
              <div className="note1-assign-new">
                <input
                  aria-label="构思集名称"
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="构思集名称（可选）"
                  value={newName}
                />
                <button
                  className="note1-text-btn is-primary"
                  onClick={() => void createAndAssign()}
                  type="button"
                >
                  创建并归入
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
