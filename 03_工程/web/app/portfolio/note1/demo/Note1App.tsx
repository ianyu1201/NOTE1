"use client";

/* eslint-disable @next/next/no-html-link-for-pages -- Static export has no RSC endpoint for client navigation. */

import "./note1.css";
import "./interaction.css";
import { useEffect, useRef, useState } from "react";
import { AppContext } from "./app-context";
import { Composer, InspirationEditor } from "./Composer";
import { Note1Provider, useNote1 } from "./Note1Provider";
import { Icon, useHashRoute, useToast, type Route } from "./ui";
import { ReceiptDetailView } from "./ReceiptPaper";
import { CardsView } from "./views/CardsView";
import { CollectionsView, CollectionWorkbench } from "./views/CollectionsView";
import { InspirationsView } from "./views/InspirationsView";
import { InspirationMenu, initialInspirationOptions } from "./InspirationMenu";
import { ReceiptsView } from "./views/ReceiptsView";
import { HistoryView, SearchView, SettingsView, TrashView } from "./views/Secondary";

const PRIMARY_ORDER: Route[] = [
  { name: "inspirations" },
  { name: "cards" },
  { name: "collections" },
  { name: "receipts" },
];

const PRIMARY_LABELS: Record<string, { label: string; icon: "sparkles" | "cards" | "folder" | "receipt" }> = {
  inspirations: { label: "灵感", icon: "sparkles" },
  cards: { label: "卡片预览", icon: "cards" },
  collections: { label: "构思集", icon: "folder" },
  receipts: { label: "小票册", icon: "receipt" },
};

export function Note1App() {
  return (
    <Note1Provider>
      <Note1Shell />
    </Note1Provider>
  );
}

function Note1Shell() {
  const appRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const viewportMeta = document.querySelector<HTMLMetaElement>('meta[name="viewport"]');
    const previousViewportContent = viewportMeta?.content;
    viewportMeta?.setAttribute("content", "width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content");
    const viewport = window.visualViewport;
    const updateViewportHeight = () => {
      const height = Math.min(window.innerHeight, viewport?.height ?? window.innerHeight);
      appRef.current?.style.setProperty("--note1-viewport-height", `${Math.round(height)}px`);
    };
    updateViewportHeight();
    window.addEventListener("resize", updateViewportHeight);
    viewport?.addEventListener("resize", updateViewportHeight);
    return () => {
      window.removeEventListener("resize", updateViewportHeight);
      viewport?.removeEventListener("resize", updateViewportHeight);
      if (previousViewportContent) viewportMeta?.setAttribute("content", previousViewportContent);
    };
  }, []);

  return (
    <div className="note1-app" ref={appRef}>
      <nav aria-label="个人网站导航" className="note1-return-bar">
        <a href="/#portfolio">← 个人主页</a>
        <a href="/portfolio/note1">项目说明 →</a>
      </nav>
      <div className="note1-device">
        <div className="note1-device-screen"><ShellBody /></div>
      </div>
    </div>
  );
}

function ShellBody() {
  const { status, error } = useNote1();
  if (status === "loading") {
    return (
      <div className="note1-status-screen">
        <p className="note1-loading" role="status">
          正在读取本机数据…
        </p>
      </div>
    );
  }
  if (status === "unavailable") {
    return (
      <div className="note1-status-screen">
        <div className="note1-unavailable">
          <h1>本机数据暂时无法读取</h1>
          <p>{error ?? "为保护原记录，NOTE1 已暂停写入。"}</p>
          <p>请确认浏览器允许本站点存储数据，或尝试刷新页面。</p>
        </div>
      </div>
    );
  }
  return <Note1Router />;
}

function Note1Router() {
  const { state } = useNote1();
  const { route, navigate } = useHashRoute();
  const { toast, showToast } = useToast();
  const [overlay, setOverlay] = useState<
    null | { type: "composer" } | { type: "editor"; id: string } | { type: "join"; collectionId: string }
  >(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuTriggerRef = useRef<HTMLButtonElement | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (!menuOpen) return;
    menuRef.current?.querySelector<HTMLButtonElement>("button")?.focus();
    const onPointerDown = (event: PointerEvent) => {
      if (menuRef.current?.contains(event.target as Node) || menuTriggerRef.current?.contains(event.target as Node)) return;
      setMenuOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        setMenuOpen(false);
        menuTriggerRef.current?.focus();
      }
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      const items = [...(menuRef.current?.querySelectorAll<HTMLButtonElement>("button") ?? [])];
      const index = items.indexOf(document.activeElement as HTMLButtonElement);
      if (index < 0 || items.length === 0) return;
      event.preventDefault();
      items[(index + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length].focus();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [menuOpen]);
  const [inspirationOptions, setInspirationOptions] = useState(initialInspirationOptions);

  const isPrimary =
    route.name === "inspirations" ||
    route.name === "cards" ||
    route.name === "collections" ||
    route.name === "receipts";

  const go = (r: Route) => {
    setMenuOpen(false);
    navigate(r);
  };

  const actions = {
    navigate: go,
    openComposer: () => setOverlay({ type: "composer" }),
    openEditor: (id: string) => setOverlay({ type: "editor", id }),
    openJoin: (collectionId: string) => setOverlay({ type: "join", collectionId }),
    showToast,
  };

  function renderRoute() {
    switch (route.name) {
      case "inspirations":
        return <InspirationsView options={inspirationOptions} onChange={setInspirationOptions} />;
      case "cards":
        return <CardsView />;
      case "collections":
        return <CollectionsView />;
      case "receipts":
        return <ReceiptsView />;
      case "collection":
        return route.id ? <CollectionWorkbench key={route.id} collectionId={route.id} /> : null;
      case "receipt": {
        const receipt = route.id ? state.receipts.find((r) => r.id === route.id) : undefined;
        return receipt ? (
          <ReceiptDetailView
            onBack={() => navigate({ name: "receipts" })}
            receipt={receipt}
          />
        ) : (
          <MissingReceipt onBack={() => navigate({ name: "receipts" })} />
        );
      }
      case "search":
        return <SearchView onBack={() => navigate({ name: "inspirations" })} />;
      case "history":
        return <HistoryView onBack={() => navigate({ name: "inspirations" })} />;
      case "trash":
        return <TrashView onBack={() => navigate({ name: "inspirations" })} />;
      case "settings":
        return <SettingsView onBack={() => navigate({ name: "inspirations" })} />;
    }
  }

  return (
    <AppContext.Provider value={actions}>
      <div className="note1-shell">
        {isPrimary ? (
          <header className="note1-primary-header">
            <div className="note1-primary-header-left">
              <button
                aria-label="本机功能与设置"
                aria-expanded={menuOpen}
                aria-haspopup="menu"
                aria-controls={menuOpen ? "note1-local-menu" : undefined}
                className="note1-icon-btn"
                onClick={() => setMenuOpen((v) => !v)}
                ref={menuTriggerRef}
                type="button"
              >
                <Icon name="menu" />
              </button>
            </div>
            <h1 className="note1-primary-header-title">{route.name === "inspirations" ? <InspirationMenu options={inspirationOptions} onChange={setInspirationOptions} /> : "NOTE1"}</h1>
            <div className="note1-primary-header-right">
              <button
                aria-label="历史记录"
                className="note1-icon-btn"
                onClick={() => go({ name: "history" })}
                type="button"
              >
                <Icon name="history" />
              </button>
              <button
                aria-label="搜索"
                className="note1-icon-btn"
                onClick={() => go({ name: "search" })}
                type="button"
              >
                <Icon name="search" />
              </button>
            </div>
          </header>
        ) : null}

        {menuOpen ? (
          <div aria-label="本机功能与设置" className="note1-menu-popover" id="note1-local-menu" onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) setMenuOpen(false); }} ref={menuRef} role="menu">
            <button
              className="note1-menu-item"
              role="menuitem"
              onClick={() => {
                setMenuOpen(false);
                navigate({ name: "trash" });
              }}
              type="button"
            >
              <Icon name="trash" /> 回收站
            </button>
            <button
              className="note1-menu-item"
              role="menuitem"
              onClick={() => {
                setMenuOpen(false);
                navigate({ name: "settings" });
              }}
              type="button"
            >
              <Icon name="settings" /> 设置
            </button>
          </div>
        ) : null}

        <div className="note1-shell-content" key={route.name}>{renderRoute()}</div>

        {isPrimary ? (
          <>
            <nav aria-label="一级导航" className="note1-primary-nav">
              {PRIMARY_ORDER.map((item) => {
                const { label, icon } = PRIMARY_LABELS[item.name];
                const active =
                  route.name === item.name ||
                  (item.name === "receipts" && route.name === "receipt");
                return (
                  <button
                    aria-current={active ? "page" : undefined}
                    className={`note1-nav-tab ${active ? "is-active" : ""}`}
                    key={item.name}
                    onClick={() => go(item)}
                    type="button"
                  >
                    <Icon name={icon} size={20} />
                    <span>{label}</span>
                  </button>
                );
              })}
            </nav>
            <button
              aria-label="记录灵感"
              className="note1-floating-composer"
              onClick={() => setOverlay({ type: "composer" })}
              type="button"
            >
              <Icon name="plus" size={22} />
            </button>
          </>
        ) : null}

        {overlay?.type === "composer" ? (
          <Composer onClose={() => setOverlay(null)} />
        ) : null}
        {overlay?.type === "editor" ? (
          <InspirationEditor inspirationId={overlay.id} onClose={() => setOverlay(null)} />
        ) : null}
        {overlay?.type === "join" ? (
          <Composer collectionId={overlay.collectionId} onClose={() => setOverlay(null)} />
        ) : null}

        {toast ? (
          <div className="note1-toast" role="status">
            <span>{toast.message}</span>
            {toast.action ? (
              <button onClick={toast.action.run} type="button">
                {toast.action.label}
              </button>
            ) : null}
          </div>
        ) : null}
      </div>
    </AppContext.Provider>
  );
}

function MissingReceipt({ onBack }: { onBack: () => void }) {
  return (
    <div className="note1-page">
      <header className="note1-page-header">
        <div className="note1-header-side">
          <button aria-label="返回" className="note1-icon-btn" onClick={onBack} type="button">
            <Icon name="chevron-left" />
          </button>
        </div>
        <span className="note1-page-title">构思小票</span>
        <div className="note1-header-side note1-header-side-right" />
      </header>
      <div className="note1-empty">
        <h2>没有找到内容</h2>
        <p>它可能已被删除或移入回收站。</p>
      </div>
    </div>
  );
}
