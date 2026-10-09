"use client";

import { useId, useMemo, useRef, useState } from "react";
import { useNote1 } from "../Note1Provider";
import { useApp } from "../app-context";
import { EmptyState, Icon, formatDisplay, formatDuration } from "../ui";
import { WorkbenchEditor, type EditorHandle } from "../WorkbenchEditor";
import { ReceiptGeneration } from "../ReceiptGeneration";
import { AccessibleDialog } from "./AccessibleDialog";
import type { Receipt } from "../domain/types";

export function CollectionsView() {
  const { state } = useNote1();
  const { navigate } = useApp();
  const active = state.collections.filter((c) => c.currentRoundId !== null);

  if (active.length === 0) {
    return (
      <div className="note1-page-body note1-page-body-scroll">
        <EmptyState
          icon="folder"
          message="在卡片预览中把灵感归入构思集后，会在这里继续整理。"
          title="当前没有构思中的构思集"
        />
      </div>
    );
  }

  return (
    <div className="note1-page-body note1-page-body-scroll">
      <p className="note1-context-label">当前范围 · 构思中</p>
      <div className="note1-card-list">
        {active.map((collection) => {
          const round = state.rounds.find((r) => r.id === collection.currentRoundId);
          const count = round?.memberIds.length ?? 0;
          const updatedAt = round?.memberIds
            .map((id) => state.inspirations.find((item) => item.id === id)?.updatedAt)
            .filter((value): value is string => Boolean(value))
            .sort()
            .at(-1) ?? collection.createdAt;
          return (
            <button
              className="note1-collection-card"
              key={collection.id}
              onClick={() => navigate({ name: "collection", id: collection.id })}
              type="button"
            >
              <span className="note1-collection-icon">
                <Icon name="folder" size={22} />
              </span>
              <div className="note1-collection-meta">
                <h3>{collection.name}</h3>
                <p>{count} 条灵感 · 更新于 {formatDisplay(updatedAt)}</p>
              </div>
              <Icon name="chevron-right" />
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function CollectionWorkbench({ collectionId }: { collectionId: string }) {
  const { store, state } = useNote1();
  const { navigate, openEditor, openJoin, showToast } = useApp();
  const [renaming, setRenaming] = useState(false);
  const [nameDraft, setNameDraft] = useState("");
  const [confirmEnd, setConfirmEnd] = useState(false);
  const [overview, setOverview] = useState(false);
  const [more, setMore] = useState(false);
  const [currentId, setCurrentId] = useState<string | null>(null);
  const [generated, setGenerated] = useState<Receipt | null>(null);
  const [ending, setEnding] = useState(false);
  const [endError, setEndError] = useState("");
  const [confirmedAt, setConfirmedAt] = useState(0);
  const endingRef = useRef(false);
  const editor = useRef<EditorHandle>(null);
  const moreButtonRef = useRef<HTMLButtonElement>(null);
  const renameInputRef = useRef<HTMLInputElement>(null);
  const renameTitleId = useId();

  const collection = state.collections.find((c) => c.id === collectionId);
  const round = collection
    ? state.rounds.find((r) => r.id === collection.currentRoundId && r.state === "thinking")
    : undefined;

  const members = useMemo(() => {
    if (!round) return [];
    return round.memberIds
      .map((id) => state.inspirations.find((i) => i.id === id))
      .filter((i): i is NonNullable<typeof i> => Boolean(i));
  }, [round, state.inspirations]);
  const activeIndex = Math.max(0, members.findIndex((member) => member.id === currentId));
  const activeMember = members[activeIndex];

  async function afterSave(action: () => void) {
    if (editor.current && !await editor.current.flush()) return;
    action();
  }

  function switchMember(delta: number) {
    const next = members[activeIndex + delta];
    if (next) void afterSave(() => setCurrentId(next.id));
  }

  if (!collection) {
    return (
      <SecondaryMissing
        onBack={() => navigate({ name: "collections" })}
        title="构思集详情"
      />
    );
  }

  function roundLabel() {
    if (!round) return "构思集已结束";
    return `第 ${round.roundNumber} 轮构思 · ${members.length} 条灵感`;
  }

  async function move(index: number, delta: number) {
    if (!round) return;
    const target = index + delta;
    if (target < 0 || target >= members.length) return;
    const reordered = [...round.memberIds];
    const [item] = reordered.splice(index, 1);
    reordered.splice(target, 0, item);
    try {
      await store.reorderMembers(round.id, reordered);
    } catch {
      showToast("排序没有保存成功。");
    }
  }

  async function doEndRound() {
    if (!round || endingRef.current) return;
    endingRef.current = true;
    setEnding(true);
    setEndError("");
    try {
      const receipt = await store.endRound(round.id);
      setConfirmEnd(false);
      setGenerated(receipt);
    } catch (err) {
      setEndError(err instanceof Error ? err.message : "生成小票失败，请重试。");
    } finally { endingRef.current = false; setEnding(false); }
  }

  async function rename() {
    const trimmed = nameDraft.trim();
    if (!trimmed) return;
    await store.renameCollection(collectionId, trimmed);
    setRenaming(false);
  }

  return (
    <div className="note1-page note1-collection-workbench">
      <header className="note1-page-header">
        <div className="note1-header-side">
          <button
            aria-label="返回构思集"
            disabled={ending}
            className="note1-icon-btn"
            onClick={() => void afterSave(() => navigate({ name: "collections" }))}
            type="button"
          >
            <Icon name="chevron-left" />
          </button>
        </div>
        <div className="note1-workbench-title">{confirmEnd || generated ? "NOTE1" : <>{collection.name}<small>{members.length} 条灵感</small></>}</div>
        <div className="note1-header-side note1-header-side-right">
          <button
            aria-label="构思集更多操作"
            disabled={ending || confirmEnd || Boolean(generated)}
            ref={moreButtonRef}
            className="note1-icon-btn"
            onClick={() => void afterSave(() => setMore(!more))}
            type="button"
          >
            <Icon name="menu" size={17} />
          </button>
        </div>
      </header>

      {more && <div className="note1-workbench-menu">
        <button className="note1-text-btn" disabled={!round} onClick={() => { setOverview(true); setMore(false); }} type="button">概览与排序</button>
        <button className="note1-text-btn" onClick={() => { setNameDraft(collection.name); setRenaming(true); setMore(false); }} type="button">改名</button>
        <button className="note1-text-btn is-danger" onClick={async () => {
          if (!window.confirm("删除构思集？成员灵感将移入回收站。")) return;
          try { await store.deleteCollection(collectionId); navigate({ name: "collections" }); }
          catch { showToast("删除未完成，内容已保留。"); }
        }} type="button">删除构思集</button>
      </div>}

      {generated ? <ReceiptGeneration receipt={generated} /> : confirmEnd ? (
        <div className="note1-end-confirm">
          <h2>已结束本轮构思</h2>
          <dl><div><dt>构思时间</dt><dd>{round ? formatDuration(confirmedAt - new Date(round.startedAt).getTime()) : "—"}</dd></div>
            <div><dt>灵感数量</dt><dd>{members.length} 条</dd></div>
            <div><dt>附件数量</dt><dd>{members.reduce((sum, member) => sum + member.resourceIds.length, 0)} 个</dd></div></dl>
          {endError && <p role="alert" className="note1-form-error">{endError}</p>}
          <button className="note1-text-btn is-primary" disabled={ending} onClick={() => void doEndRound()} type="button">{ending ? "正在保存…" : "生成小票"}</button>
          <button className="note1-text-btn" disabled={ending} onClick={() => setConfirmEnd(false)} type="button">取消</button>
        </div>
      ) : <>

      <div className="note1-scroll note1-workbench-body">
        <p className="note1-context-label">{roundLabel()}</p>

        {round ? <>
        {overview && <button className="note1-text-btn" onClick={() => setOverview(false)} type="button">完成排序</button>}
        {!overview && activeMember && <>
          <WorkbenchEditor key={activeMember.id} member={activeMember} ref={editor} />
          <div className="note1-workbench-pagination">
            <button className="note1-icon-btn" aria-label="上一条灵感" disabled={activeIndex === 0} onClick={() => switchMember(-1)} type="button"><Icon name="chevron-up" /></button>
            <span aria-live="polite">{activeIndex + 1} / {members.length}</span>
            <button className="note1-icon-btn" aria-label="下一条灵感" disabled={activeIndex === members.length - 1} onClick={() => switchMember(1)} type="button"><Icon name="chevron-down" /></button>
          </div>
          <div className="note1-workbench-tools">
            <button className="note1-text-btn" onClick={() => void afterSave(() => openEditor(activeMember.id))} type="button">附件{activeMember.resourceIds.length ? ` · ${activeMember.resourceIds.length}` : ""}</button>
            <button className="note1-text-btn" onClick={() => void afterSave(async () => {
              try { await store.removeFromCollection(activeMember.id); showToast("已移出构思集，放回卡片流。"); }
              catch { showToast("移出未完成。"); }
            })} type="button">移出</button>
          </div>
        </>}
        <div className="note1-workbench-members" hidden={!overview && members.length > 0}>
          {members.length === 0 ? (
            <EmptyState
              icon="folder"
              message="加入灵感后，可以在这里整理顺序并结束本轮。"
              title="本轮没有可显示的灵感。"
            />
          ) : (
            members.map((member, index) => (
              <div className="note1-member-row" key={member.id}>
                <button
                  className="note1-member-main"
                  onClick={() => openEditor(member.id)}
                  type="button"
                >
                  <p>{member.text.trim() || "未命名灵感"}</p>
                  <small>
                    {member.resourceIds.length > 0 ? `${member.resourceIds.length} 个附件 · ` : ""}
                    {formatDisplay(member.updatedAt)}
                  </small>
                </button>
                <div className="note1-member-controls">
                  <button
                    aria-label="上移"
                    className="note1-icon-btn"
                    disabled={index === 0}
                    onClick={() => void move(index, -1)}
                    type="button"
                  >
                    <Icon name="chevron-up" size={16} />
                  </button>
                  <button
                    aria-label="下移"
                    className="note1-icon-btn"
                    disabled={index === members.length - 1}
                    onClick={() => void move(index, 1)}
                    type="button"
                  >
                    <Icon name="chevron-down" size={16} />
                  </button>
                  <button
                    aria-label="移出构思集"
                    className="note1-icon-btn"
                    onClick={async () => {
                      await store.removeFromCollection(member.id);
                      showToast("已移出构思集，放回卡片流。");
                    }}
                    type="button"
                  >
                    <Icon name="return" size={16} />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="note1-workbench-actions">
          <button
            className="note1-text-btn"
            onClick={() => void afterSave(() => openJoin(collectionId))}
            type="button"
          >
            <Icon name="plus" /> 加入灵感
          </button>
          <button
            className="note1-text-btn is-primary"
            disabled={!round || members.length === 0}
            onClick={() => void afterSave(() => { setConfirmedAt(Date.now()); setConfirmEnd(true); })}
            type="button"
          >
            结束本轮构思
          </button>
        </div>
        </> : <>
          <div className="note1-card-list">
            {[...state.rounds].filter((item) => item.collectionId === collectionId && item.state === "ended").sort((a, b) => b.roundNumber - a.roundNumber).map((item) => <section className="note1-history-section" key={item.id}>
              <h3>第 {item.roundNumber} 轮构思</h3>
              <p className="note1-muted">{formatDisplay(item.startedAt)} – {item.endedAt ? formatDisplay(item.endedAt) : "—"} · {item.effectiveEditCount} 次有效编辑</p>
              <ol className="note1-history-timeline">{item.events.map((event) => <li key={event.id}>{formatDisplay(event.occurredAt)} · {({ started: "开始构思", memberAdded: "加入灵感", memberRemoved: "移出灵感", inspirationEdited: "编辑灵感", ended: "结束本轮构思" })[event.kind]}</li>)}</ol>
              {state.receipts.filter((receipt) => receipt.roundId === item.id).map((receipt) => <button className="note1-text-btn" key={receipt.id} onClick={() => navigate({ name: "receipt", id: receipt.id })} type="button">查看构思小票</button>)}
            </section>)}
          </div>
          <div className="note1-workbench-actions"><button className="note1-text-btn is-primary" disabled={ending} onClick={async () => {
            if (endingRef.current) return;
            endingRef.current = true; setEnding(true);
            try { await store.continueThinking(collectionId); }
            catch (error) { showToast(error instanceof Error ? error.message : "继续构思未完成。"); }
            finally { endingRef.current = false; setEnding(false); }
          }} type="button">继续构思</button></div>
        </>}
      </div>
      </>}

      {renaming ? (
        <div className="note1-overlay">
          <AccessibleDialog
            className="note1-overlay-panel note1-rename-panel"
            initialFocusRef={renameInputRef}
            onClose={() => setRenaming(false)}
            returnFocusRef={moreButtonRef}
            titleId={renameTitleId}
          >
            <h2 id={renameTitleId}>改名</h2>
            <p className="note1-muted">名称只影响当前构思集，不改变既有构思小票快照。</p>
            <input
              aria-label="构思集名称"
              onChange={(e) => setNameDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.nativeEvent.isComposing && e.keyCode !== 229) void rename();
              }}
              ref={renameInputRef}
              value={nameDraft}
            />
            <div className="note1-overlay-actions">
              <button className="note1-text-btn" onClick={() => setRenaming(false)} type="button">
                取消
              </button>
              <button className="note1-text-btn is-primary" onClick={() => void rename()} type="button">
                保存
              </button>
            </div>
          </AccessibleDialog>
        </div>
      ) : null}

      {(confirmEnd || generated) && <nav aria-label="一级导航" className="note1-primary-nav">
        {([ ["inspirations", "灵感", "sparkles"], ["cards", "卡片预览", "cards"], ["collections", "构思集", "folder"], ["receipts", "小票册", "receipt"] ] as const).map(([name, label, icon]) => <button className={`note1-nav-tab ${name === "collections" ? "is-active" : ""}`} aria-current={name === "collections" ? "page" : undefined} key={name} disabled={ending} onClick={() => navigate({ name })} type="button"><Icon name={icon} /><span>{label}</span></button>)}
      </nav>}
    </div>
  );
}

export function SecondaryMissing({
  onBack,
  title,
}: {
  onBack: () => void;
  title: string;
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
        <div className="note1-header-side note1-header-side-right" />
      </header>
      <EmptyState icon="folder" message="它可能已被删除。" title="没有找到内容" />
    </div>
  );
}
