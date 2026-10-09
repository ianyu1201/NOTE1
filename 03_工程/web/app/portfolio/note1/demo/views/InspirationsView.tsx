"use client";

import { useMemo, useState } from "react";
import type { Inspiration } from "../domain/types";
import { useNote1 } from "../Note1Provider";
import { useApp } from "../app-context";
import { EmptyState, Icon, formatGroup, formatTime } from "../ui";
import type { InspirationOptions } from "../InspirationMenu";
import { inspirationIsArchived } from "../domain/engine";

export function InspirationsView({ options, onChange }: { options: InspirationOptions; onChange: (value: InspirationOptions) => void }) {
  const { store, state } = useNote1();
  const { openEditor, showToast } = useApp();
  const { scope, sort, selecting } = options;
  const setSelecting = (value: boolean) => onChange({ ...options, selecting: value });
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [selectionMode, setSelectionMode] = useState({ scope, selecting });
  if (selectionMode.scope !== scope || selectionMode.selecting !== selecting) {
    setSelectionMode({ scope, selecting });
    setSelected(new Set());
  }

  const items = useMemo(() => {
    const list = state.inspirations.filter((i) =>
      scope === "all" || inspirationIsArchived(state, i) === (scope === "tucked"),
    );
    return list.sort((a, b) => sort === "updated" ? b.updatedAt.localeCompare(a.updatedAt) : sort === "oldest" ? a.createdAt.localeCompare(b.createdAt) : b.createdAt.localeCompare(a.createdAt));
  }, [state, scope, sort]);

  const groups = useMemo(() => {
    const map = new Map<string, Inspiration[]>();
    for (const item of items) {
      const key = formatGroup(sort === "updated" ? item.updatedAt : item.createdAt);
      const bucket = map.get(key) ?? [];
      bucket.push(item);
      map.set(key, bucket);
    }
    return [...map.entries()];
  }, [items, sort]);

  function toggleSelect(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function run(
    action: (ids: string[]) => Promise<unknown>,
    okMessage: string,
  ) {
    const ids = [...selected];
    try {
      await action(ids);
      setSelecting(false);
      setSelected(new Set());
      showToast(okMessage);
    } catch {
      showToast("操作没有完成。");
    }
  }

  return (
    <div className="note1-page-body note1-page-body-scroll">
      {selecting ? <div className="note1-list-context is-selecting"><span>已选 {selected.size} 条</span><button type="button" onClick={() => { setSelecting(false); setSelected(new Set()); }}>完成</button></div> : null}
      {items.length === 0 && (
        <div className="note1-empty-entry">
          <EmptyState
            icon="sparkles"
            message={scope === "tucked" ? "收起的灵感会出现在这里。" : "记下一条想法，再到「卡片预览」回看。"}
            title={scope === "tucked" ? "还没有已收起灵感" : "这里还没有灵感"}
          />
        </div>
      )}

      {groups.map(([date, bucket]) => (
        <section className="note1-date-group" key={date}>
          <h2 className="note1-date-heading">{date}</h2>
          <div className="note1-card-list">
            {bucket.map((item) => {
              const isSelected = selected.has(item.id);
              return (
                <article className="note1-inspiration-card" key={item.id}>
                  {selecting ? (
                    <button
                      aria-label={isSelected ? `取消选择 ${item.text}` : `选择 ${item.text}`}
                      aria-pressed={isSelected}
                      className={`note1-check ${isSelected ? "is-on" : ""}`}
                      onClick={() => toggleSelect(item.id)}
                      type="button"
                    >
                      {isSelected ? <Icon name="check" size={16} /> : null}
                    </button>
                  ) : null}
                  <button
                    className="note1-inspiration-card-main"
                    onClick={() => selecting ? toggleSelect(item.id) : openEditor(item.id)}
                    type="button"
                  >
                    <p className="note1-inspiration-text">
                      {item.text.trim() || "未命名灵感"}
                    </p>
                    <div className="note1-inspiration-meta">
                      <span>{formatTime(item.updatedAt)}</span>
                      {item.resourceIds.length > 0 ? (
                        <span className="note1-inspiration-attachments">
                          <Icon name="paperclip" size={13} />
                          {item.resourceIds.length}
                        </span>
                      ) : null}

                    </div>
                  </button>
                </article>
              );
            })}
          </div>
        </section>
      ))}

      {selecting ? (
        <div className="note1-batch-bar">
          <button className="note1-text-btn" type="button" onClick={() => setSelected(selected.size === items.length ? new Set() : new Set(items.map((item) => item.id)))}>{selected.size === items.length && items.length > 0 ? "取消全选" : "全选"}</button>
          <button
            className="note1-text-btn"
            disabled={selected.size === 0}
            onClick={() =>
              run(
                scope === "tucked"
                  ? (ids) => store.batchReturnToCardFlow(ids)
                  : (ids) => store.batchDeleteInspirations(ids),
                scope === "tucked" ? "已放回卡片流。" : "已移入回收站。",
              )
            }
            type="button"
          >
            {scope === "tucked" ? "放回卡片流" : "删除"}
          </button>
          <span className="note1-batch-count">已选 {selected.size} 条</span>
        </div>
      ) : null}
    </div>
  );
}
