"use client";

import { useCallback, useId, useRef, useState, type PointerEvent } from "react";
import { useApp } from "./app-context";
import { ActionMenu } from "./ActionMenu";
import { AccessibleDialog } from "./views/AccessibleDialog";
import type {
  Receipt,
  ReceiptSnapshotAttachment,
  ReceiptSnapshotMember,
} from "./domain/types";
import * as engine from "./domain/engine";
import { useNote1 } from "./Note1Provider";
import {
  Icon,
  formatDateTime,
  formatDuration,
  formatTime,
  useBlobUrl,
} from "./ui";

export type ReceiptTemplate = "classic" | "film";

function imageAttachments(
  members: ReceiptSnapshotMember[],
): ReceiptSnapshotAttachment[] {
  return members.flatMap((m) =>
    m.attachments.filter((a) => a.mimeType.startsWith("image/")),
  );
}

function AttachmentImage({ resourceId, alt }: { resourceId: string; alt: string }) {
  const { store } = useNote1();
  const loadUrl = useCallback((id: string) => store.getAttachmentUrl(id), [store]);
  const url = useBlobUrl(loadUrl, resourceId);
  if (!url) return <span className="note1-photo-placeholder" aria-hidden="true" />;
  return <img alt={alt} loading="lazy" src={url} />;
}

export function ReceiptPaper({
  receipt,
  template = "classic",
  dense = false,
}: {
  receipt: Receipt;
  template?: ReceiptTemplate;
  dense?: boolean;
}) {
  const stats = engine.receiptStatistics(receipt.snapshot);
  const snapshot = receipt.snapshot;
  const photos = imageAttachments(snapshot.members);
  const resolvedTemplate: ReceiptTemplate =
    template === "film" && photos.length === 0 ? "classic" : template;

  return (
    <div className={`note1-receipt-paper is-${dense ? "dense" : "full"}`}>
      <header className="note1-receipt-header">
        <strong className="note1-receipt-brand">NOTE1</strong>
        <span className="note1-receipt-sub">构 思 小 票</span>
        <h3>{snapshot.collectionName}</h3>
        <span className="note1-receipt-meta">
          {engine.roundTitle(stats.roundNumber)} ·{" "}
          {resolvedTemplate === "film" ? "胶卷票" : "经典票"}
        </span>
        <span className="note1-receipt-meta">{formatDateTime(snapshot.endedAt)}</span>
      </header>

      <div className="note1-receipt-rule is-double" />

      {resolvedTemplate === "film" ? (
        <div className="note1-film-strip">
          {photos.slice(0, dense ? 3 : 6).map((a) => (
            <AttachmentImage
              alt={`${snapshot.collectionName} 的图片附件 ${a.filename}`}
              key={a.id}
              resourceId={a.id}
            />
          ))}
        </div>
      ) : null}

      <div className="note1-receipt-summary">
        <div className="note1-receipt-stat">
          <strong>本轮构思</strong>
          <strong>{formatDuration(stats.durationMs)}</strong>
        </div>
        <span className="note1-receipt-meta">
          {formatTime(snapshot.startedAt)} – {formatTime(snapshot.endedAt)}
        </span>
      </div>

      <div className="note1-receipt-rule" />

      <div className="note1-receipt-section">
        <div className="note1-receipt-section-head">
          <strong>灵感时间线</strong>
          <span className="note1-receipt-meta">共 {snapshot.members.length} 条</span>
        </div>
        {snapshot.members.length === 0 ? (
          <p className="note1-receipt-empty-line">这一轮构思留下了一张可以带走的存根。</p>
        ) : (
          <ol className="note1-receipt-timeline">
            {snapshot.members.map((member, index) => {
              const body = member.text.trim();
              return (
                <li key={member.inspirationId}>
                  <span className="note1-receipt-number">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <p>{body || "未命名灵感"}</p>
                    {member.attachments.length > 0 ? (
                      <span className="note1-receipt-meta">
                        {member.attachments.length} 个附件
                      </span>
                    ) : null}
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </div>

      {snapshot.members.some((m) => m.attachments.length > 0) ? (
        <div className="note1-receipt-section">
          <div className="note1-receipt-section-head">
            <strong>附件</strong>
            <span className="note1-receipt-meta">
              共 {stats.attachmentCount} 个
            </span>
          </div>
          <div className="note1-receipt-attachments">
            {snapshot.members
              .flatMap((m) => m.attachments)
              .slice(0, 4)
              .map((a) => (
                <span className="note1-receipt-attachment-chip" key={a.id}>
                  <Icon
                    name={
                      a.mimeType.startsWith("image/")
                        ? "image"
                        : a.mimeType.startsWith("audio/")
                          ? "paperclip"
                          : "doc"
                    }
                    size={14}
                  />
                </span>
              ))}
          </div>
        </div>
      ) : null}

      <div className="note1-receipt-rule" />

      <div className="note1-receipt-metrics">
        <div className="note1-receipt-stat">
          <span>灵感</span>
          <strong>{stats.inspirationCount} 条</strong>
        </div>
        <div className="note1-receipt-stat">
          <span>附件</span>
          <strong>{stats.attachmentCount} 个</strong>
        </div>
        <div className="note1-receipt-stat">
          <span>最终文字</span>
          <strong>{stats.finalTextCount} 字</strong>
        </div>
        <div className="note1-receipt-stat">
          <span>有效编辑</span>
          <strong>{stats.effectiveEditCount} 次</strong>
        </div>
      </div>

      <div className="note1-receipt-rule is-double" />

      <footer className="note1-receipt-footer">
        <span>构思小票 · 本机快照</span>
        <span>本轮构思已结束 · {snapshot.members.length} 条灵感</span>
      </footer>
    </div>
  );
}

function downloadText(filename: string, text: string, mime: string) {
  const blob = new Blob([text], { type: mime });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

export function ReceiptDetailView({
  receipt,
  onBack,
}: {
  receipt: Receipt;
  onBack: () => void;
}) {
  const { store, state } = useNote1();
  const { navigate, showToast } = useApp();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const deleteTitleId = useId();
  const deleteTrigger = useRef<HTMLElement>(null);
  const collection = state.collections.find((item) => item.id === receipt.collectionId);
  async function continueThinking() {
    if (!collection || busy) return;
    setBusy(true);
    try {
      if (!collection.currentRoundId) await store.continueThinking(collection.id);
      navigate({ name: "collection", id: collection.id });
    } catch (error) { showToast(error instanceof Error ? error.message : "继续构思未完成。"); }
    finally { setBusy(false); }
  }
  async function deleteReceipt() {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const ids = await store.deleteReceipt(receipt.id);
      setConfirmDelete(false);
      showToast("小票已移入回收站。", { label: "撤回", run: () => { void store.restoreTrash(ids).catch(() => showToast("恢复未完成。")); } });
      onBack();
    } catch (error) { setError(error instanceof Error ? error.message : "删除没有完成。"); }
    finally { setBusy(false); }
  }
  const start = useRef<{ x: number; y: number } | null>(null);
  const receipts = [...state.receipts].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  const index = receipts.findIndex((item) => item.id === receipt.id);
  function turn(delta: number) {
    const next = receipts[index + delta];
    if (next) navigate({ name: "receipt", id: next.id });
  }
  function finishSwipe(event: PointerEvent<HTMLDivElement>) {
    const origin = start.current;
    start.current = null;
    if (!origin) return;
    const dx = event.clientX - origin.x;
    const dy = event.clientY - origin.y;
    if (Math.abs(dx) >= 72 && Math.abs(dx) > Math.abs(dy) * 1.25) turn(dx < 0 ? 1 : -1);
  }

  return (
    <div className="note1-page note1-receipt-detail">
      <header className="note1-page-header">
        <div className="note1-header-side">
          <button
            aria-label="返回小票册"
            className="note1-icon-btn"
            onClick={onBack}
            type="button"
          >
            <Icon name="chevron-left" />
          </button>
        </div>
        <span className="note1-page-title">构思小票</span>
        <div className="note1-header-side note1-header-side-right">
          <ActionMenu key={receipt.id} label="小票导出选项" align="right" trigger={<Icon name="menu" />}>
            {(close) => <>
              <button role="menuitem" disabled={!collection || busy} onClick={() => { close(); void continueThinking(); }}><Icon name="folder" /><span>{collection?.currentRoundId ? "返回当前构思" : "继续构思"}</span></button>
              <button role="menuitem" onClick={() => { downloadText(`note1-${receipt.id.slice(0, 8)}.md`, engine.receiptMarkdown(receipt), "text/markdown"); close(); }}><Icon name="doc" /><span>导出 Markdown</span></button>
              <button role="menuitem" onClick={() => { downloadText(`note1-${receipt.id.slice(0, 8)}.txt`, engine.receiptPlainText(receipt), "text/plain"); close(); }}><Icon name="doc" /><span>导出纯文本</span></button>
              <button role="menuitem" onClick={() => { close(); window.setTimeout(() => window.print(), 0); }}><Icon name="receipt" /><span>打印 / 存为 PDF</span></button>
              <button role="menuitem" disabled={busy} className="is-danger" onClick={() => { close(); deleteTrigger.current = document.activeElement as HTMLElement; setError(""); setConfirmDelete(true); }}><Icon name="trash" /><span>删除小票</span></button>
            </>}
          </ActionMenu>
        </div>
      </header>

      <div className="note1-scroll note1-receipt-detail-body" key={receipt.id} style={{ touchAction: "pan-y" }} onPointerDown={(event) => { if (event.isPrimary && event.button === 0) start.current = { x: event.clientX, y: event.clientY }; }} onPointerUp={finishSwipe} onPointerCancel={() => { start.current = null; }}>
        <ReceiptPaper receipt={receipt} />
      </div>
      <div className="note1-reader-navigation"><button className="note1-text-btn" disabled={index <= 0} onClick={() => turn(-1)} type="button">上一张</button><span>{index + 1} / {receipts.length}</span><button className="note1-text-btn" disabled={index >= receipts.length - 1} onClick={() => turn(1)} type="button">下一张</button></div>
      {confirmDelete && <div className="note1-overlay"><AccessibleDialog className="note1-overlay-panel note1-confirm-panel" onClose={() => { if (!busy) setConfirmDelete(false); }} returnFocusRef={deleteTrigger} titleId={deleteTitleId}>
        <h2 id={deleteTitleId}>删除这张小票？</h2><p className="note1-muted">小票将移入回收站，30 天内可以恢复。</p>
        {error && <p className="note1-form-error" role="alert">{error}</p>}
        <div className="note1-overlay-actions"><button className="note1-text-btn" disabled={busy} onClick={() => setConfirmDelete(false)} type="button">取消</button><button className="note1-text-btn is-danger" disabled={busy} onClick={() => void deleteReceipt()} type="button">{busy ? "正在删除…" : "删除"}</button></div>
      </AccessibleDialog></div>}
    </div>
  );
}
