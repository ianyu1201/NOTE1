"use client";

import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { useNote1 } from "../Note1Provider";
import type { SearchScope } from "../store";
import { useApp } from "../app-context";
import * as engine from "../domain/engine";
import type { TrashEntry } from "../domain/types";
import { EmptyState, Icon, formatBytes, formatDateTime } from "../ui";
import { AccessibleDialog } from "./AccessibleDialog";

function SecondaryPage({
  title,
  onBack,
  children,
  trailing,
}: {
  title: string;
  onBack: () => void;
  children: ReactNode;
  trailing?: ReactNode;
}) {
  return (
    <div className="note1-page">
      <header className="note1-page-header">
        <div className="note1-header-side">
          <button aria-label="返回" className="note1-icon-btn" onClick={onBack} type="button">
            <Icon name="chevron-left" />
          </button>
        </div>
        <span className="note1-page-title">{title}</span>
        <div className="note1-header-side note1-header-side-right">{trailing ?? null}</div>
      </header>
      <div className="note1-scroll note1-secondary-body">{children}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 搜索
// ---------------------------------------------------------------------------

export function SearchView({ onBack }: { onBack: () => void }) {
  const { store } = useNote1();
  const { openEditor, navigate } = useApp();
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<SearchScope>("all");
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => inputRef.current?.focus(), []);

  const results = store.search(query, scope);

  return (
    <SecondaryPage
      onBack={onBack}
      title="搜索"
      trailing={
        <button
          aria-label="清除搜索"
          className="note1-icon-btn"
          onClick={() => setQuery("")}
          type="button"
        >
          <Icon name="close" size={16} />
        </button>
      }
    >
      <div className="note1-search-bar">
        <Icon name="search" />
        <input
          aria-label="搜索灵感、构思集、小票或附件"
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜索你的本机内容"
          ref={inputRef}
          value={query}
        />
      </div>

      <div className="note1-segmented note1-search-scope" role="tablist" aria-label="搜索范围">
        {(
          [
            ["all", "全部"],
            ["inspirations", "灵感"],
            ["collections", "构思集"],
            ["receipts", "小票"],
          ] as const
        ).map(([value, label]) => (
          <button
            aria-selected={scope === value}
            className={scope === value ? "is-active" : ""}
            key={value}
            onClick={() => setScope(value)}
            role="tab"
            type="button"
          >
            {label}
          </button>
        ))}
      </div>

      {query.trim() === "" ? (
        <EmptyState icon="search" message="灵感、构思集、小票和附件都可以查找。" title="搜索你的本机内容" />
      ) : results.length === 0 ? (
        <EmptyState
          icon="search"
          message="可尝试更短的关键词或更换搜索范围。"
          title="没有找到内容"
        />
      ) : (
        <div className="note1-card-list">
          {results.map((result) => {
            if (result.kind === "inspiration") {
              return (
                <button
                  className="note1-search-result"
                  key={result.inspiration.id}
                  onClick={() => openEditor(result.inspiration.id)}
                  type="button"
                >
                  <Icon name="sparkles" />
                  <div>
                    <h3>{result.inspiration.text.trim() || "未命名灵感"}</h3>
                    <small>灵感 · {formatDateTime(result.inspiration.updatedAt)}</small>
                  </div>
                </button>
              );
            }
            if (result.kind === "collection") {
              return (
                <button
                  className="note1-search-result"
                  key={result.collection.id}
                  onClick={() => navigate({ name: "collection", id: result.collection.id })}
                  type="button"
                >
                  <Icon name="folder" />
                  <div>
                    <h3>{result.collection.name}</h3>
                    <small>构思集</small>
                  </div>
                </button>
              );
            }
            return (
              <button
                className="note1-search-result"
                key={result.receipt.id}
                onClick={() => navigate({ name: "receipt", id: result.receipt.id })}
                type="button"
              >
                <Icon name="receipt" />
                <div>
                  <h3>{result.receipt.snapshot.collectionName}</h3>
                  <small>
                    小票 · {engine.roundTitle(engine.receiptStatistics(result.receipt.snapshot).roundNumber)}
                  </small>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </SecondaryPage>
  );
}

// ---------------------------------------------------------------------------
// 历史
// ---------------------------------------------------------------------------

export function HistoryView({ onBack }: { onBack: () => void }) {
  const { state } = useNote1();
  const { openEditor, navigate } = useApp();
  const [scope, setScope] = useState("all");
  const rows = [
    ...state.inspirations.filter((item) => item.cardFlowState === "tuckedAway" && item.collectionId === null).map((item) => ({
      id: item.id, kind: "tucked", title: item.text.trim() || "未命名灵感", date: item.updatedAt,
      detail: "灵感 · 已收起", icon: "sparkles" as const, open: () => openEditor(item.id),
    })),
    ...state.rounds.filter((round) => round.state === "ended").map((round) => ({
      id: round.id, kind: "rounds", title: state.collections.find((item) => item.id === round.collectionId)?.name ?? "构思集",
      date: round.endedAt ?? round.startedAt,
      detail: `构思历程 · ${engine.roundTitle(round.roundNumber)} · ${round.effectiveEditCount} 次有效编辑`,
      icon: "folder" as const, open: () => navigate({ name: "collection", id: round.collectionId }),
    })),
    ...state.receipts.map((receipt) => ({
      id: receipt.id, kind: "receipts", title: receipt.snapshot.collectionName, date: receipt.createdAt,
      detail: `构思小票 · ${engine.roundTitle(receipt.snapshot.roundNumber)}`, icon: "receipt" as const,
      open: () => navigate({ name: "receipt", id: receipt.id }),
    })),
  ].filter((row) => scope === "all" || row.kind === scope).sort((a, b) => b.date.localeCompare(a.date));
  const labels = [["all", "全部"], ["tucked", "已收起"], ["rounds", "构思历程"], ["receipts", "小票"]];
  return <SecondaryPage onBack={onBack} title="历史">
    <p className="note1-context-label">当前范围 · {labels.find(([value]) => value === scope)?.[1]}</p>
    <div className="note1-segmented note1-search-scope" role="tablist" aria-label="历史范围">
      {labels.map(([value, label]) => <button key={value} role="tab" aria-selected={scope === value} className={scope === value ? "is-active" : ""} onClick={() => setScope(value)} type="button">{label}</button>)}
    </div>
    {rows.length === 0 ? <EmptyState icon="history" title="还没有历史内容" message={scope === "tucked" ? "独立灵感收起后会出现在这里。" : scope === "rounds" ? "结束一轮构思后会在这里留存。" : scope === "receipts" ? "生成的构思小票会出现在这里。" : "收起灵感或结束构思后，会在这里留存。"} /> :
      <div className="note1-card-list">{rows.map((row) => <button className="note1-search-result" key={`${row.kind}-${row.id}`} onClick={row.open} type="button">
        <Icon name={row.icon} /><div><h3>{row.title}</h3><small>{row.detail} · {formatDateTime(row.date)}</small></div>
      </button>)}</div>}
  </SecondaryPage>;
}

// ---------------------------------------------------------------------------
// 回收站
// ---------------------------------------------------------------------------

export function TrashView({ onBack }: { onBack: () => void }) {
  const { store, state } = useNote1();
  const { showToast } = useApp();
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState("");
  const deleteTrigger = useRef<HTMLButtonElement>(null);
  const deleteTitleId = useId();

  useEffect(() => {
    void store.purgeExpiredTrash().catch(() => setDeleteError("过期内容清理未完成，数据已保留。"));
  }, [store]);

  function trashLabel(entry: TrashEntry): { title: string; detail: string; icon: "sparkles" | "receipt" } {
    if (entry.object.kind === "inspiration") {
      return {
        title: entry.object.inspiration.text.trim() || "未命名灵感",
        detail: "灵感",
        icon: "sparkles",
      };
    }
    const receipt = entry.object.receipt;
    return {
      title: receipt.snapshot.collectionName,
      detail: `构思小票 · ${engine.roundTitle(engine.receiptStatistics(receipt.snapshot).roundNumber)}`,
      icon: "receipt",
    };
  }

  async function restore(id: string) {
    try {
      await store.restoreTrash([id]);
      showToast("已恢复。");
    } catch {
      showToast("恢复没有完成。");
    }
  }

  async function removePermanently() {
    if (!pendingDelete || deleting) return;
    setDeleting(true);
    setDeleteError("");
    try {
      if (pendingDelete === "all") await store.emptyTrash();
      else await store.permanentlyDeleteTrash([pendingDelete]);
      showToast(pendingDelete === "all" ? "回收站已清空。" : "已永久删除。");
      setPendingDelete(null);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : "删除没有完成，内容已保留。");
    } finally { setDeleting(false); }
  }

  return (
    <SecondaryPage
      onBack={onBack}
      title="回收站"
      trailing={
        state.trash.length > 0 ? (
          <button
            className="note1-text-btn"
            onClick={(event) => { deleteTrigger.current = event.currentTarget; setDeleteError(""); setPendingDelete("all"); }}
            type="button"
          >
            清空
          </button>
        ) : undefined
      }
    >
      <p className="note1-muted note1-trash-notice">
        删除的灵感和构思小票会保留 30 天，之后自动清理。
      </p>
      {deleteError && !pendingDelete && <p role="alert" className="note1-form-error">{deleteError}</p>}
      {state.trash.length === 0 ? (
        <EmptyState icon="trash" message="删除的内容会先出现在这里。" title="回收站为空" />
      ) : (
        <div className="note1-card-list">
          {state.trash.map((entry) => {
            const { title, detail, icon } = trashLabel(entry);
            return (
              <div className="note1-trash-row" key={entry.id}>
                <div className="note1-trash-row-main">
                  <Icon name={icon} />
                  <div>
                    <h3>{title}</h3>
                    <small>
                      {detail} · 删除于 {formatDateTime(entry.deletedAt)}
                    </small>
                  </div>
                </div>
                <div className="note1-trash-row-actions">
                  <button className="note1-text-btn" onClick={() => void restore(entry.id)} type="button">
                    恢复
                  </button>
                  <button
                    className="note1-icon-btn"
                    aria-label="永久删除"
                    onClick={(event) => { deleteTrigger.current = event.currentTarget; setDeleteError(""); setPendingDelete(entry.id); }}
                    type="button"
                  >
                    <Icon name="trash" size={16} />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
      {pendingDelete && <div className="note1-overlay">
        <AccessibleDialog className="note1-overlay-panel note1-confirm-panel" onClose={() => { if (!deleting) setPendingDelete(null); }} returnFocusRef={deleteTrigger} titleId={deleteTitleId}>
          <h2 id={deleteTitleId}>{pendingDelete === "all" ? "清空回收站？" : "永久删除？"}</h2>
          <p className="note1-muted">此操作不能撤销，仍被其他灵感或小票引用的附件会保留。</p>
          {deleteError && <p className="note1-form-error" role="alert">{deleteError}</p>}
          <div className="note1-overlay-actions">
            <button className="note1-text-btn" disabled={deleting} onClick={() => setPendingDelete(null)} type="button">取消</button>
            <button className="note1-text-btn is-danger" disabled={deleting} onClick={() => void removePermanently()} type="button">{deleting ? "正在删除…" : pendingDelete === "all" ? "清空" : "永久删除"}</button>
          </div>
        </AccessibleDialog>
      </div>}
    </SecondaryPage>
  );
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

export function SettingsView({ onBack }: { onBack: () => void }) {
  const { store, storageEstimate } = useNote1();
  const { showToast } = useApp();
  const importRef = useRef<HTMLInputElement | null>(null);
  const importButtonRef = useRef<HTMLButtonElement>(null);
  const clearButtonRef = useRef<HTMLButtonElement>(null);
  const importTitleId = useId();
  const clearTitleId = useId();
  const [pendingBackup, setPendingBackup] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function downloadBackup() {
    try {
      const { filename, blob } = await store.exportBackup();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = filename;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
      showToast("已导出本机备份。");
    } catch (err) {
      showToast(err instanceof Error ? err.message : "导出失败。");
    }
  }

  async function handleImportFile(file: File) {
    setError(null);
    try {
      const text = await file.text();
      await store.validateBackup(text);
      setPendingBackup(text);
    } catch (err) {
      setError(err instanceof Error ? err.message : "备份文件无法使用。");
    }
  }

  async function confirmImport() {
    if (!pendingBackup) return;
    try {
      await store.importBackup(pendingBackup);
      setPendingBackup(null);
      showToast("已从备份恢复。");
    } catch (err) {
      setError(err instanceof Error ? err.message : "恢复失败，当前数据保持不变。");
      setPendingBackup(null);
    }
  }

  return (
    <SecondaryPage onBack={onBack} title="设置">
      <input
        accept=".json,application/json,.note1-web-backup.json"
        className="note1-hidden-input"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void handleImportFile(file);
          e.target.value = "";
        }}
        ref={importRef}
        type="file"
      />

      <section className="note1-settings-section">
        <h2>本机数据</h2>
        <button className="note1-settings-row" onClick={() => void downloadBackup()} type="button">
          <Icon name="download" />
          <span>导出本机备份</span>
        </button>
        <button className="note1-settings-row" onClick={() => importRef.current?.click()} ref={importButtonRef} type="button">
          <Icon name="upload" />
          <span>从备份恢复</span>
        </button>
        <button className="note1-settings-row is-danger" onClick={() => setConfirmClear(true)} ref={clearButtonRef} type="button">
          <Icon name="trash" />
          <span>清除本机数据</span>
        </button>
        <p className="note1-muted note1-settings-foot">
          备份包含灵感、构思集、构思轮次、小票、回收站和仍被引用的附件。恢复会替换当前本机数据。
        </p>
      </section>

      <section className="note1-settings-section">
        <h2>隐私</h2>
        <div className="note1-privacy-box">
          <p>
            NOTE1 的灵感、构思集、构思轮次、构思小票、回收站内容和附件，默认只保存在当前设备的当前浏览器中。
          </p>
          <p>
            NOTE1 不提供登录、后端、云同步、AI 分析或静默上传。换设备、换浏览器、使用无痕模式或清除网站数据后，内容可能无法找回；请定期导出备份。
          </p>
        </div>
      </section>

      <section className="note1-settings-section">
        <h2>关于 NOTE1</h2>
        <div className="note1-about-box">
          <p>简单记，快速看。NOTE1 只在本机保存你的灵感与构思成果。</p>
          <p className="note1-muted">
            版本 0.1.0 · 本地保存
            {storageEstimate
              ? ` · 已用 ${formatBytes(storageEstimate.usage)}`
              : ""}
          </p>
        </div>
      </section>

      {error ? (
        <p className="note1-form-error" role="alert">
          {error}
        </p>
      ) : null}

      {pendingBackup ? (
        <div className="note1-overlay">
          <AccessibleDialog
            className="note1-overlay-panel note1-confirm-panel"
            onClose={() => setPendingBackup(null)}
            returnFocusRef={importButtonRef}
            titleId={importTitleId}
          >
            <h2 id={importTitleId}>恢复本机备份？</h2>
            <p className="note1-muted">恢复会用备份内容替换当前本机数据。</p>
            <div className="note1-overlay-actions">
              <button className="note1-text-btn" onClick={() => setPendingBackup(null)} type="button">
                取消
              </button>
              <button className="note1-text-btn is-primary" onClick={() => void confirmImport()} type="button">
                恢复并替换当前数据
              </button>
            </div>
          </AccessibleDialog>
        </div>
      ) : null}

      {confirmClear ? (
        <div className="note1-overlay">
          <AccessibleDialog
            className="note1-overlay-panel note1-confirm-panel"
            onClose={() => setConfirmClear(false)}
            returnFocusRef={clearButtonRef}
            titleId={clearTitleId}
          >
            <h2 id={clearTitleId}>清除本机数据？</h2>
            <p className="note1-muted">
              将删除当前浏览器内 NOTE1 的全部灵感、构思集、小票、回收站和附件。此操作不能撤销，且不会删除个人网站或其他作品的数据。
            </p>
            <div className="note1-overlay-actions">
              <button className="note1-text-btn" onClick={() => setConfirmClear(false)} type="button">
                取消
              </button>
              <button
                className="note1-text-btn is-danger"
                onClick={async () => {
                  await store.clearAllData();
                  setConfirmClear(false);
                  showToast("本机数据已清除。");
                }}
                type="button"
              >
                清除
              </button>
            </div>
          </AccessibleDialog>
        </div>
      ) : null}
    </SecondaryPage>
  );
}
