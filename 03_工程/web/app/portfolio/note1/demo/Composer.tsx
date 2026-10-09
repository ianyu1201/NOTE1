"use client";

import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type DragEvent,
} from "react";
import type { InputFile } from "./store";
import { useNote1 } from "./Note1Provider";
import type { AttachmentResource } from "./domain/types";
import { Icon, formatBytes, useBlobUrl } from "./ui";

const dialogFocusableSelector = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "textarea:not([disabled])",
  "select:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(", ");

function focusableIn(dialog: HTMLElement) {
  return Array.from(dialog.querySelectorAll<HTMLElement>(dialogFocusableSelector)).filter(
    (element) => element.tabIndex >= 0 && element.getClientRects().length > 0,
  );
}

function useComposerDialog(onEscape: () => void) {
  const panelRef = useRef<HTMLDivElement | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const composingRef = useRef(false);
  const lastCompositionEndRef = useRef(0);
  const onEscapeRef = useRef(onEscape);

  useEffect(() => {
    onEscapeRef.current = onEscape;
  }, [onEscape]);

  useEffect(() => {
    const panel = panelRef.current;
    if (!panel) return;

    const previousFocus = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
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
        onEscapeRef.current();
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
    (textareaRef.current ?? firstFocus()).focus({ preventScroll: true });

    return () => {
      document.removeEventListener("focusin", onFocusIn, true);
      document.removeEventListener("keydown", onKeyDown, true);
      if (previousFocus?.isConnected && previousFocus !== document.body) {
        previousFocus.focus({ preventScroll: true });
      }
    };
  }, []);

  return {
    panelRef,
    textareaRef,
    onCompositionStart: () => { composingRef.current = true; },
    onCompositionEnd: () => {
      composingRef.current = false;
      lastCompositionEndRef.current = performance.now();
    },
  };
}

function fileToInput(file: File): InputFile {
  return {
    name: file.name,
    mimeType: file.type || "application/octet-stream",
    data: file,
  };
}

function ImageThumb({
  src,
  alt,
}: {
  src: string | undefined;
  alt: string;
}) {
  if (!src) return <span className="note1-attach-thumb is-pending" aria-hidden="true" />;
  return <img alt={alt} className="note1-attach-thumb" src={src} />;
}

function AttachmentChip({
  resource,
  url,
  onRemove,
}: {
  resource: AttachmentResource;
  url?: string;
  onRemove: () => void;
}) {
  const isImage = resource.mimeType.startsWith("image/");
  return (
    <div className="note1-attach-chip">
      {isImage ? (
        <ImageThumb alt={resource.filename} src={url} />
      ) : (
        <span className="note1-attach-chip-icon">
          <Icon name="doc" size={20} />
        </span>
      )}
      <div className="note1-attach-chip-meta">
        <span className="note1-attach-name">{resource.filename}</span>
        <span className="note1-attach-size">{formatBytes(resource.size)}</span>
      </div>
      <button
        aria-label={`移除附件 ${resource.filename}`}
        className="note1-icon-btn"
        onClick={onRemove}
        type="button"
      >
        <Icon name="close" size={16} />
      </button>
    </div>
  );
}

function useFilePicker(onFiles: (files: InputFile[]) => void) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const open = () => inputRef.current?.click();
  const handleChange = () => {
    const input = inputRef.current;
    if (!input || !input.files) return;
    onFiles(Array.from(input.files).map(fileToInput));
    input.value = "";
  };
  const onDrop = (event: DragEvent) => {
    event.preventDefault();
    setDragOver(false);
    const files = Array.from(event.dataTransfer.files).map(fileToInput);
    if (files.length) onFiles(files);
  };
  const input = (
    <input
      className="note1-hidden-input"
      multiple
      onChange={handleChange}
      ref={inputRef}
      type="file"
    />
  );
  return { open, dragOver, setDragOver, onDrop, input };
}

export function Composer({
  onClose,
  collectionId,
}: {
  onClose: () => void;
  collectionId?: string;
}) {
  const { store } = useNote1();
  const [text, setText] = useState("");
  const [pendingFiles, setPendingFiles] = useState<InputFile[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const titleId = useId();
  const { panelRef, textareaRef, onCompositionStart, onCompositionEnd } = useComposerDialog(onClose);

  const picker = useFilePicker((files) => setPendingFiles((prev) => [...prev, ...files]));
  const canSave = text.trim().length > 0 || pendingFiles.length > 0;

  async function save() {
    if (!canSave || saving) return;
    setSaving(true);
    setError(null);
    try {
      await store.createInspiration(text, pendingFiles);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "没有保存成功。");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="note1-overlay"
      onDragEnter={() => picker.setDragOver(true)}
      onDragLeave={() => picker.setDragOver(false)}
      onDragOver={(e) => e.preventDefault()}
      onDrop={picker.onDrop}
    >
      {picker.input}
      <div
        aria-labelledby={titleId}
        aria-modal="true"
        className="note1-overlay-panel note1-composer"
        ref={panelRef}
        role="dialog"
        tabIndex={-1}
      >
        <header className="note1-page-header">
          <div className="note1-header-side">
            <button
              aria-label="放弃本次记录"
              className="note1-icon-btn"
              onClick={onClose}
              type="button"
            >
              <Icon name="close" />
            </button>
          </div>
          <span className="note1-page-title" id={titleId}>{collectionId ? "加入灵感" : "记录灵感"}</span>
          <div className="note1-header-side note1-header-side-right">
            <button
              className="note1-save-btn"
              disabled={!canSave || saving}
              onClick={save}
              type="button"
            >
              {saving ? "保存中…" : "保存"}
            </button>
          </div>
        </header>

        <div className="note1-composer-body">
          <textarea
            aria-label="灵感内容"
            className="note1-composer-textarea"
            onChange={(e) => setText(e.target.value)}
            onCompositionEnd={onCompositionEnd}
            onCompositionStart={onCompositionStart}
            placeholder="记下此刻的灵感…"
            ref={textareaRef}
            value={text}
          />

          <div className="note1-composer-attachments">
            {pendingFiles.map((file, index) => (
              <PendingAttachmentChip
                file={file}
                key={`${file.name}-${index}`}
                onRemove={() =>
                  setPendingFiles((prev) => prev.filter((_, i) => i !== index))
                }
              />
            ))}
          </div>

          {error ? (
            <p className="note1-form-error" role="alert">
              {error}
            </p>
          ) : null}
        </div>

        <footer className="note1-composer-footer">
          <button className="note1-toolbar-btn" onClick={picker.open} type="button">
            <Icon name="paperclip" />
            <span>添加附件</span>
          </button>
          {picker.dragOver ? (
            <span className="note1-drop-hint">松开以添加文件</span>
          ) : null}
        </footer>
      </div>
    </div>
  );
}

export function InspirationEditor({
  inspirationId,
  onClose,
}: {
  inspirationId: string;
  onClose: () => void;
}) {
  const { store, state } = useNote1();
  const inspiration = state.inspirations.find((i) => i.id === inspirationId);
  const [text, setText] = useState(inspiration?.text ?? "");
  const [saveState, setSaveState] = useState<"saved" | "saving" | "dirty">("saved");
  const [error, setError] = useState<string | null>(null);
  const originalRef = useRef(inspiration?.text ?? "");
  const finishingRef = useRef(false);
  const titleId = useId();

  const picker = useFilePicker((files) => {
    void store.attachFiles(inspirationId, files).catch((err) => {
      setError(err instanceof Error ? err.message : "附件没有添加成功。");
    });
  });

  useEffect(() => {
    if (text === originalRef.current) return;
    const handle = window.setTimeout(async () => {
      setSaveState("saving");
      try {
        await store.updateInspiration(inspirationId, text);
        setSaveState("saved");
      } catch (err) {
        setSaveState("dirty");
        setError(err instanceof Error ? err.message : "没有保存成功。");
      }
    }, 600);
    return () => window.clearTimeout(handle);
  }, [text, inspirationId, store]);

  async function finish() {
    if (finishingRef.current) return;
    finishingRef.current = true;
    try {
      await store.finishInspirationEditSession(
        inspirationId,
        originalRef.current,
        text,
      );
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "没有保存成功。");
    } finally {
      finishingRef.current = false;
    }
  }

  const { panelRef, textareaRef, onCompositionStart, onCompositionEnd } = useComposerDialog(
    inspiration ? () => { void finish(); } : onClose,
  );

  if (!inspiration) {
    return (
      <div className="note1-overlay">
        <div
          aria-labelledby={titleId}
          aria-modal="true"
          className="note1-overlay-panel"
          ref={panelRef}
          role="dialog"
          tabIndex={-1}
        >
          <EmptyStateMissing onClose={onClose} titleId={titleId} />
        </div>
      </div>
    );
  }

  const resources = inspiration.resourceIds
    .map((id) => state.resources.find((r) => r.id === id))
    .filter((r): r is AttachmentResource => Boolean(r));

  return (
    <div
      className="note1-overlay"
      onDragEnter={() => picker.setDragOver(true)}
      onDragLeave={() => picker.setDragOver(false)}
      onDragOver={(e) => e.preventDefault()}
      onDrop={picker.onDrop}
    >
      {picker.input}
      <div
        aria-labelledby={titleId}
        aria-modal="true"
        className="note1-overlay-panel note1-composer"
        ref={panelRef}
        role="dialog"
        tabIndex={-1}
      >
        <header className="note1-page-header">
          <div className="note1-header-side">
            <button
              aria-label="完成编辑并返回"
              className="note1-icon-btn"
              onClick={finish}
              type="button"
            >
              <Icon name="chevron-left" />
            </button>
          </div>
          <span className="note1-page-title" id={titleId}>编辑灵感</span>
          <div className="note1-header-side note1-header-side-right">
            <span className="note1-save-status">
              {saveState === "saving" ? "保存中…" : saveState === "dirty" ? "未保存" : "已保存"}
            </span>
          </div>
        </header>

        <div className="note1-composer-body">
          <textarea
            aria-label="灵感内容"
            className="note1-composer-textarea"
            onChange={(e) => {
              setText(e.target.value);
              setSaveState("dirty");
            }}
            onCompositionEnd={onCompositionEnd}
            onCompositionStart={onCompositionStart}
            ref={textareaRef}
            value={text}
          />

          <div className="note1-composer-attachments">
            {resources.map((resource) => (
              <ExistingAttachment
                key={resource.id}
                inspirationId={inspirationId}
                resource={resource}
              />
            ))}
          </div>

          {error ? (
            <p className="note1-form-error" role="alert">
              {error}
            </p>
          ) : null}
        </div>

        <footer className="note1-composer-footer">
          <button className="note1-toolbar-btn" onClick={picker.open} type="button">
            <Icon name="paperclip" />
            <span>添加附件</span>
          </button>
        </footer>
      </div>
    </div>
  );
}

function PendingAttachmentChip({
  file,
  onRemove,
}: {
  file: InputFile;
  onRemove: () => void;
}) {
  const [url] = useState(() =>
    file.mimeType.startsWith("image/") ? URL.createObjectURL(file.data) : undefined,
  );
  useEffect(
    () => () => {
      if (url) URL.revokeObjectURL(url);
    },
    [url],
  );
  const resource: AttachmentResource = {
    id: "pending",
    source: "importedAttachment" as const,
    filename: file.name,
    mimeType: file.mimeType,
    size: file.data.size,
    createdAt: new Date().toISOString(),
  };
  return <AttachmentChip onRemove={onRemove} resource={resource} url={url} />;
}

function ExistingAttachment({
  inspirationId,
  resource,
}: {
  inspirationId: string;
  resource: AttachmentResource;
}) {
  const { store } = useNote1();
  const loadUrl = useCallback((id: string) => store.getAttachmentUrl(id), [store]);
  const url = useBlobUrl(
    loadUrl,
    resource.mimeType.startsWith("image/") ? resource.id : undefined,
  );

  return (
    <AttachmentChip
      onRemove={() => {
        void store.removeResource(inspirationId, resource.id).catch(() => {});
      }}
      resource={resource}
      url={url}
    />
  );
}

function EmptyStateMissing({ onClose, titleId }: { onClose: () => void; titleId: string }) {
  return (
    <div className="note1-empty">
      <h2 id={titleId}>没有找到内容</h2>
      <p>它可能已被删除或移入回收站。</p>
      <button className="note1-text-btn" onClick={onClose} type="button">
        返回
      </button>
    </div>
  );
}