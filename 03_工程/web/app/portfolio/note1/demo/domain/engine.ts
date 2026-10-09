// NOTE1 Web 纯领域引擎。逐条移植 V02DomainEngine / V02Store 的业务规则，
// 不依赖 React、DOM 或 IndexedDB。所有函数就地修改传入的 DomainState。

import type {
  AttachmentResource,
  DomainState,
  ID,
  Inspiration,
  ISODateTime,
  Receipt,
  ReceiptSnapshot,
  ReceiptSnapshotAttachment,
  ReceiptSnapshotMember,
  RoundEvent,
  RoundEventKind,
  ThinkingCollection,
  ThinkingRound,
} from "./types";
export type DomainErrorCode =
  | "inspirationNotFound"
  | "collectionNotFound"
  | "roundNotFound"
  | "activeRoundRequired"
  | "duplicateReceipt"
  | "emptyRound"
  | "invalidMemberOrder"
  | "trashEntryNotFound"
  | "resourceNotFound";

const DOMAIN_ERROR_MESSAGES: Record<DomainErrorCode, string> = {
  inspirationNotFound: "没有找到对应内容。",
  collectionNotFound: "没有找到对应内容。",
  roundNotFound: "没有找到对应内容。",
  activeRoundRequired: "当前构思集没有可操作的构思轮次。",
  duplicateReceipt: "本轮构思已经生成构思小票。",
  emptyRound: "请先在构思集中保留至少一条灵感，再结束本轮构思。",
  invalidMemberOrder: "构思集内的灵感顺序无效。",
  trashEntryNotFound: "回收站中没有找到对应内容。",
  resourceNotFound: "没有找到对应附件资源。",
};

export class DomainError extends Error {
  readonly code: DomainErrorCode;
  constructor(code: DomainErrorCode) {
    super(DOMAIN_ERROR_MESSAGES[code]);
    this.name = "DomainError";
    this.code = code;
  }
}

export type StoreErrorCode =
  | "emptyIdea"
  | "attachmentTooLarge"
  | "invalidOperation"
  | "persistenceUnavailable"
  | "persistenceWriteFailed"
  | "backupInvalid";

export class StoreError extends Error {
  readonly code: StoreErrorCode;
  constructor(code: StoreErrorCode, message?: string) {
    super(message ?? STORE_ERROR_MESSAGES[code]);
    this.name = "StoreError";
    this.code = code;
  }
}

const STORE_ERROR_MESSAGES: Record<StoreErrorCode, string> = {
  emptyIdea: "灵感需要包含文字或附件。",
  attachmentTooLarge: "附件超过单文件大小上限。",
  invalidOperation: "操作无法完成。",
  persistenceUnavailable: "本机数据暂时无法读取。为保护原记录，NOTE1 已暂停写入。",
  persistenceWriteFailed: "本机数据没有保存成功。",
  backupInvalid: "备份文件无法使用。",
};

export const TRASH_RETENTION_DAYS = 30;
export const TRASH_RETENTION_MS = TRASH_RETENTION_DAYS * 24 * 60 * 60 * 1000;

export function nowISO(): ISODateTime {
  return new Date().toISOString();
}

export function newID(): ID {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  // 极少数环境回退；仅用于对象身份，不用于安全。
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function trimmed(value: string): string {
  return value.trim();
}

// ---------------------------------------------------------------------------
// 查询辅助（供 UI 与引擎复用，保持对象身份与顺序稳定）
// ---------------------------------------------------------------------------

export function visibleInspirations(state: DomainState): Inspiration[] {
  return state.inspirations
    .filter((i) => !inspirationIsArchived(state, i))
    .sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0));
}

export function cardPreviewEntries(state: DomainState): Inspiration[] {
  return state.inspirations.filter(
    (i) => i.collectionId === null && i.cardFlowState === "visible",
  );
}

export function activeCollections(state: DomainState): ThinkingCollection[] {
  return state.collections.filter((c) => c.currentRoundId !== null);
}

// ---------------------------------------------------------------------------
// 构思集与轮次
// ---------------------------------------------------------------------------

export function createCollection(
  state: DomainState,
  name: string | undefined,
  now: ISODateTime,
): ThinkingCollection {
  const defaultName = `构思集（${state.nextCollectionNumber}）`;
  state.nextCollectionNumber += 1;
  const withName = name ? trimmed(name) : "";
  const collectionName = withName || defaultName;
  const collection: ThinkingCollection = {
    id: newID(),
    name: collectionName,
    createdAt: now,
    currentRoundId: null,
    nextRoundNumber: 1,
  };
  state.collections.push(collection);
  return collection;
}

export function startRound(
  state: DomainState,
  collectionId: ID,
  memberIds: ID[],
  now: ISODateTime,
): ThinkingRound {
  const collection = state.collections.find((c) => c.id === collectionId);
  if (!collection) throw new DomainError("collectionNotFound");
  if (collection.currentRoundId !== null) throw new DomainError("activeRoundRequired");
  const previousMax =
    state.rounds
      .filter((r) => r.collectionId === collectionId)
      .reduce((max, r) => Math.max(max, r.roundNumber), 0);
  const roundNumber = Math.max(collection.nextRoundNumber, previousMax + 1, 1);
  const events: RoundEvent[] = [
    { id: newID(), kind: "started", occurredAt: now, inspirationId: null },
    ...memberIds.map((id) => ({
      id: newID(),
      kind: "memberAdded" as RoundEventKind,
      occurredAt: now,
      inspirationId: id,
    })),
  ];
  const round: ThinkingRound = {
    id: newID(),
    collectionId,
    state: "thinking",
    startedAt: now,
    endedAt: null,
    memberIds: [...memberIds],
    effectiveEditCount: 0,
    roundNumber,
    events,
  };
  state.rounds.push(round);
  collection.currentRoundId = round.id;
  collection.nextRoundNumber = roundNumber + 1;
  return round;
}

export function assign(
  state: DomainState,
  inspirationId: ID,
  toCollectionId: ID,
  now: ISODateTime,
): void {
  const inspiration = state.inspirations.find((i) => i.id === inspirationId);
  if (!inspiration) throw new DomainError("inspirationNotFound");
  const collection = state.collections.find((c) => c.id === toCollectionId);
  const roundId = collection?.currentRoundId;
  if (!roundId) throw new DomainError("activeRoundRequired");
  const round = state.rounds.find((r) => r.id === roundId && r.state === "thinking");
  if (!round) throw new DomainError("activeRoundRequired");

  if (inspiration.collectionId) {
    const oldRoundId = state.collections.find(
      (c) => c.id === inspiration.collectionId,
    )?.currentRoundId;
    const oldRound = oldRoundId
      ? state.rounds.find((r) => r.id === oldRoundId)
      : undefined;
    if (oldRound) {
      oldRound.memberIds = oldRound.memberIds.filter((id) => id !== inspirationId);
      oldRound.events.push({
        id: newID(),
        kind: "memberRemoved",
        occurredAt: now,
        inspirationId,
      });
    }
  }

  if (!round.memberIds.includes(inspirationId)) {
    round.memberIds.push(inspirationId);
    round.events.push({
      id: newID(),
      kind: "memberAdded",
      occurredAt: now,
      inspirationId,
    });
  }
  inspiration.collectionId = toCollectionId;
  inspiration.updatedAt = now;
}

export function removeFromCollection(
  state: DomainState,
  inspirationId: ID,
  now: ISODateTime,
): void {
  const inspiration = state.inspirations.find((i) => i.id === inspirationId);
  if (!inspiration || !inspiration.collectionId) {
    throw new DomainError("inspirationNotFound");
  }
  const roundId = state.collections.find(
    (c) => c.id === inspiration.collectionId,
  )?.currentRoundId;
  const round = roundId
    ? state.rounds.find((r) => r.id === roundId && r.state === "thinking")
    : undefined;
  if (!round) throw new DomainError("inspirationNotFound");
  round.memberIds = round.memberIds.filter((id) => id !== inspirationId);
  round.events.push({
    id: newID(),
    kind: "memberRemoved",
    occurredAt: now,
    inspirationId,
  });
  inspiration.collectionId = null;
  inspiration.cardFlowState = "visible";
  inspiration.updatedAt = now;
}

export function reorderMembers(
  state: DomainState,
  roundId: ID,
  memberIds: ID[],
): void {
  const round = state.rounds.find((r) => r.id === roundId && r.state === "thinking");
  if (!round) throw new DomainError("roundNotFound");
  if (
    memberIds.length !== round.memberIds.length ||
    new Set(memberIds).size !== round.memberIds.length ||
    !memberIds.every((id) => round.memberIds.includes(id))
  ) {
    throw new DomainError("invalidMemberOrder");
  }
  round.memberIds = [...memberIds];
}

// ---------------------------------------------------------------------------
// 灵感：创建、编辑、收起、放回
// ---------------------------------------------------------------------------

export function createInspiration(
  state: DomainState,
  text: string,
  resourceIds: ID[],
  now: ISODateTime,
): Inspiration {
  if (!trimmed(text) && resourceIds.length === 0) throw new StoreError("emptyIdea");
  if (
    new Set(resourceIds).size !== resourceIds.length ||
    !resourceIds.every((id) => state.resources.some((r) => r.id === id))
  ) {
    throw new DomainError("resourceNotFound");
  }
  const inspiration: Inspiration = {
    id: newID(),
    text,
    cardFlowState: "visible",
    collectionId: null,
    createdAt: now,
    updatedAt: now,
    resourceIds: [...resourceIds],
  };
  state.inspirations.push(inspiration);
  return inspiration;
}

export function updateInspiration(
  state: DomainState,
  id: ID,
  text: string,
  now: ISODateTime,
  recordsEffectiveEdit: boolean,
): void {
  const inspiration = state.inspirations.find((i) => i.id === id);
  if (!inspiration) throw new DomainError("inspirationNotFound");
  if (!trimmed(text) && inspiration.resourceIds.length === 0) {
    throw new StoreError("emptyIdea");
  }
  if (
    recordsEffectiveEdit &&
    inspiration.text !== text &&
    inspiration.collectionId
  ) {
    const round = activeRoundForCollection(state, inspiration.collectionId);
    if (round) {
      round.effectiveEditCount += 1;
      round.events.push({
        id: newID(),
        kind: "inspirationEdited",
        occurredAt: now,
        inspirationId: id,
      });
    }
  }
  inspiration.text = text;
  inspiration.updatedAt = now;
}

export function finishInspirationEditSession(
  state: DomainState,
  id: ID,
  originalText: string,
  finalText: string,
  now: ISODateTime,
): void {
  const inspiration = state.inspirations.find((i) => i.id === id);
  if (!inspiration) throw new DomainError("inspirationNotFound");
  if (!trimmed(finalText) && inspiration.resourceIds.length === 0) {
    throw new StoreError("emptyIdea");
  }
  if (originalText === finalText) return;
  inspiration.text = finalText;
  inspiration.updatedAt = now;
  if (inspiration.collectionId) {
    const round = activeRoundForCollection(state, inspiration.collectionId);
    if (round) {
      round.effectiveEditCount += 1;
      round.events.push({
        id: newID(),
        kind: "inspirationEdited",
        occurredAt: now,
        inspirationId: id,
      });
    }
  }
}

function activeRoundForCollection(
  state: DomainState,
  collectionId: ID,
): ThinkingRound | undefined {
  const roundId = state.collections.find((c) => c.id === collectionId)?.currentRoundId;
  return roundId
    ? state.rounds.find((r) => r.id === roundId && r.state === "thinking")
    : undefined;
}

export function tuckAway(state: DomainState, id: ID, now: ISODateTime): void {
  const inspiration = state.inspirations.find((i) => i.id === id);
  if (!inspiration) throw new DomainError("inspirationNotFound");
  inspiration.cardFlowState = "tuckedAway";
  inspiration.updatedAt = now;
}

export function returnToCardFlow(state: DomainState, id: ID, now: ISODateTime): void {
  const inspiration = state.inspirations.find((i) => i.id === id);
  if (!inspiration) throw new DomainError("inspirationNotFound");
  // Returning a completed member detaches the live inspiration, never the receipt snapshot.
  if (inspiration.collectionId && !activeRoundForInspiration(state, inspiration)) inspiration.collectionId = null;
  inspiration.cardFlowState = "visible";
  inspiration.updatedAt = now;
}

function activeRoundForInspiration(state: DomainState, item: Inspiration): ThinkingRound | undefined {
  const collection = state.collections.find((c) => c.id === item.collectionId);
  return state.rounds.find((r) => r.id === collection?.currentRoundId && r.state === "thinking" && r.memberIds.includes(item.id));
}

/** Also recognizes receipts generated before completed members were explicitly tucked. */
export function inspirationIsArchived(state: DomainState, item: Inspiration): boolean {
  if (activeRoundForInspiration(state, item)) return item.cardFlowState === "tuckedAway";
  return item.cardFlowState === "tuckedAway" || (item.collectionId !== null && state.receipts.some((r) => r.collectionId === item.collectionId && r.snapshot.members.some((m) => m.inspirationId === item.id)));
}

// ---------------------------------------------------------------------------
// 结束轮次、继续构思、撤回结束
// ---------------------------------------------------------------------------

export function endRound(
  state: DomainState,
  roundId: ID,
  now: ISODateTime,
): Receipt {
  const roundIndex = state.rounds.findIndex((r) => r.id === roundId);
  if (roundIndex < 0) throw new DomainError("roundNotFound");
  const round = state.rounds[roundIndex];
  if (round.state !== "thinking") throw new DomainError("duplicateReceipt");
  if (round.memberIds.length === 0) throw new DomainError("emptyRound");
  const collection = state.collections.find((c) => c.id === round.collectionId);
  if (!collection) throw new DomainError("collectionNotFound");
  if (collection.currentRoundId !== roundId) throw new DomainError("activeRoundRequired");

  const members: ReceiptSnapshotMember[] = round.memberIds.map((id) => {
    const item = state.inspirations.find((i) => i.id === id);
    if (!item) throw new DomainError("inspirationNotFound");
    const attachments: ReceiptSnapshotAttachment[] = item.resourceIds
      .map((resourceId) => state.resources.find((r) => r.id === resourceId))
      .filter((r): r is AttachmentResource => Boolean(r))
      .map((r) => ({
        id: r.id,
        source: r.source,
        filename: r.filename,
        mimeType: r.mimeType,
        size: r.size,
        createdAt: r.createdAt,
      }));
    return {
      inspirationId: item.id,
      text: item.text,
      resourceIds: [...item.resourceIds],
      attachments,
    };
  });

  round.events.push({ id: newID(), kind: "ended", occurredAt: now, inspirationId: null });
  const snapshot: ReceiptSnapshot = {
    collectionName: collection.name,
    startedAt: round.startedAt,
    endedAt: now,
    roundNumber: round.roundNumber,
    effectiveEditCount: round.effectiveEditCount,
    members,
    events: [...round.events],
  };
  const receipt: Receipt = {
    id: newID(),
    roundId: round.id,
    collectionId: round.collectionId,
    createdAt: now,
    snapshot,
  };
  round.state = "ended";
  round.endedAt = now;
  collection.currentRoundId = null;
  for (const id of round.memberIds) {
    const item = state.inspirations.find((i) => i.id === id);
    if (item?.collectionId === collection.id) item.cardFlowState = "tuckedAway";
  }
  state.receipts.push(receipt);
  return receipt;
}

export function undoEndRound(state: DomainState, receiptId: ID, now: ISODateTime): void {
  const receiptIndex = state.receipts.findIndex((r) => r.id === receiptId);
  if (receiptIndex < 0) throw new DomainError("roundNotFound");
  const receipt = state.receipts[receiptIndex];

  const latestForCollection = state.receipts
    .filter((r) => r.collectionId === receipt.collectionId)
    .reduce<Receipt | null>(
      (max, r) => (max === null || r.createdAt > max.createdAt ? r : max),
      null,
    );
  if (latestForCollection?.id !== receiptId) throw new DomainError("roundNotFound");

  const round = state.rounds.find(
    (r) => r.id === receipt.roundId && r.state === "ended",
  );
  const collection = state.collections.find((c) => c.id === receipt.collectionId);
  if (!round || !collection || collection.currentRoundId !== null) {
    throw new DomainError("roundNotFound");
  }

  state.receipts.splice(receiptIndex, 1);
  round.state = "thinking";
  round.endedAt = null;
  if (round.events.length && round.events[round.events.length - 1].kind === "ended") {
    round.events.pop();
  }
  collection.currentRoundId = round.id;
  for (const memberId of round.memberIds) {
    const inspiration = state.inspirations.find((i) => i.id === memberId);
    if (inspiration) {
      inspiration.collectionId = receipt.collectionId;
      inspiration.cardFlowState = "visible";
      inspiration.updatedAt = now;
    }
  }
}

export function continueRound(
  state: DomainState,
  collectionId: ID,
  now: ISODateTime,
): ThinkingRound {
  const collection = state.collections.find((c) => c.id === collectionId);
  if (!collection) throw new DomainError("collectionNotFound");
  if (collection.currentRoundId !== null) throw new DomainError("activeRoundRequired");
  const previous = state.rounds
    .filter((r) => r.collectionId === collectionId && r.state === "ended")
    .sort((a, b) =>
      (a.endedAt ?? "") > (b.endedAt ?? "") ? -1 : (a.endedAt ?? "") < (b.endedAt ?? "") ? 1 : 0,
    )[0];
  if (!previous) throw new DomainError("roundNotFound");
  if (
    !previous.memberIds.every((id) => state.inspirations.some((i) => i.id === id))
  ) {
    throw new DomainError("inspirationNotFound");
  }

  const round = startRound(state, collectionId, previous.memberIds, now);
  for (const index of state.inspirations.keys()) {
    const inspiration = state.inspirations[index];
    if (previous.memberIds.includes(inspiration.id)) {
      // Continuing takes the member back into this round. Historical rounds
      // and receipt snapshots remain intact; other active rounds relinquish it.
      for (const other of state.rounds) {
        if (other.id === round.id || other.state !== "thinking" || !other.memberIds.includes(inspiration.id)) continue;
        other.memberIds = other.memberIds.filter((id) => id !== inspiration.id);
        other.events.push({ id: newID(), kind: "memberRemoved", occurredAt: now, inspirationId: inspiration.id });
      }
      inspiration.collectionId = collectionId;
      inspiration.cardFlowState = "visible";
      inspiration.updatedAt = now;
    }
  }
  return round;
}

// ---------------------------------------------------------------------------
// 删除、回收站、清理
// ---------------------------------------------------------------------------

export function deleteInspiration(
  state: DomainState,
  inspirationId: ID,
  now: ISODateTime,
): ID {
  const index = state.inspirations.findIndex((i) => i.id === inspirationId);
  if (index < 0) throw new DomainError("inspirationNotFound");
  const inspiration = state.inspirations[index];
  const ownedCollectionId = inspiration.collectionId;
  state.inspirations.splice(index, 1);
  const deleted: Inspiration = { ...inspiration, collectionId: null, cardFlowState: "visible" };
  state.trash.push({
    id: newID(),
    object: { kind: "inspiration", inspiration: deleted },
    deletedAt: now,
  });
  for (const round of state.rounds) {
    round.memberIds = round.memberIds.filter((id) => id !== inspirationId);
  }
  if (
    ownedCollectionId &&
    !state.inspirations.some((i) => i.collectionId === ownedCollectionId)
  ) {
    state.rounds = state.rounds.filter((r) => r.collectionId !== ownedCollectionId);
    state.collections = state.collections.filter((c) => c.id !== ownedCollectionId);
  }
  return inspirationId;
}

export function deleteReceipt(
  state: DomainState,
  receiptId: ID,
  now: ISODateTime,
): ID {
  const index = state.receipts.findIndex((r) => r.id === receiptId);
  if (index < 0) throw new DomainError("roundNotFound");
  const receipt = state.receipts.splice(index, 1)[0];
  state.trash.push({
    id: newID(),
    object: { kind: "receipt", receipt },
    deletedAt: now,
  });
  return receiptId;
}

export function deleteCollection(
  state: DomainState,
  collectionId: ID,
  now: ISODateTime,
): void {
  if (!state.collections.some((c) => c.id === collectionId)) {
    throw new DomainError("collectionNotFound");
  }
  const deletedInspirations = state.inspirations
    .filter((i) => i.collectionId === collectionId)
    .map((i) => ({ ...i, collectionId: null, cardFlowState: "visible" as const }));
  state.inspirations = state.inspirations.filter(
    (i) => i.collectionId !== collectionId,
  );
  for (const inspiration of deletedInspirations) {
    state.trash.push({
      id: newID(),
      object: { kind: "inspiration", inspiration },
      deletedAt: now,
    });
  }
  state.rounds = state.rounds.filter((r) => r.collectionId !== collectionId);
  state.collections = state.collections.filter((c) => c.id !== collectionId);
}

export function restoreTrash(state: DomainState, entryId: ID, now: ISODateTime): void {
  const index = state.trash.findIndex((t) => t.id === entryId);
  if (index < 0) throw new DomainError("trashEntryNotFound");
  const entry = state.trash.splice(index, 1)[0];
  if (entry.object.kind === "inspiration") {
    const inspiration = entry.object.inspiration;
    if (state.inspirations.some((i) => i.id === inspiration.id)) {
      throw new DomainError("inspirationNotFound");
    }
    state.inspirations.push({
      ...inspiration,
      collectionId: null,
      cardFlowState: "visible",
      updatedAt: now,
    });
  } else {
    const receipt = entry.object.receipt;
    if (state.receipts.some((r) => r.id === receipt.id)) {
      throw new DomainError("roundNotFound");
    }
    state.receipts.push(receipt);
  }
}

export function permanentlyDeleteTrash(
  state: DomainState,
  entryIds: Set<ID>,
): void {
  if (
    ![...entryIds].every((id) => state.trash.some((t) => t.id === id))
  ) {
    throw new DomainError("trashEntryNotFound");
  }
  state.trash = state.trash.filter((t) => !entryIds.has(t.id));
}

export function purgeExpiredTrash(state: DomainState, now: ISODateTime): void {
  const cutoff = new Date(now).getTime();
  state.trash = state.trash.filter(
    (t) => cutoff - new Date(t.deletedAt).getTime() < TRASH_RETENTION_MS,
  );
}

// ---------------------------------------------------------------------------
// 附件引用完整性
// ---------------------------------------------------------------------------

export function referencedResourceIds(state: DomainState): Set<ID> {
  const ids = new Set<ID>();
  for (const i of state.inspirations) i.resourceIds.forEach((id) => ids.add(id));
  for (const r of state.receipts)
    r.snapshot.members.forEach((m) => m.resourceIds.forEach((id) => ids.add(id)));
  for (const t of state.trash) {
    if (t.object.kind === "inspiration") {
      t.object.inspiration.resourceIds.forEach((id) => ids.add(id));
    } else {
      t.object.receipt.snapshot.members.forEach((m) =>
        m.resourceIds.forEach((id) => ids.add(id)),
      );
    }
  }
  return ids;
}

export function removeUnreferencedResources(state: DomainState): AttachmentResource[] {
  const kept = referencedResourceIds(state);
  const toRemove = state.resources.filter((r) => !kept.has(r.id));
  state.resources = state.resources.filter((r) => kept.has(r.id));
  return toRemove;
}

// ---------------------------------------------------------------------------
// 小票统计
// ---------------------------------------------------------------------------

export interface ReceiptStatistics {
  roundNumber: number;
  inspirationCount: number;
  attachmentCount: number;
  finalTextCount: number;
  effectiveEditCount: number;
  durationMs: number;
}

export function receiptStatistics(snapshot: ReceiptSnapshot): ReceiptStatistics {
  const attachmentCount = snapshot.members.reduce((total, member) => {
    const union = new Set<ID>([...member.resourceIds]);
    member.attachments.forEach((a) => union.add(a.id));
    return total + union.size;
  }, 0);
  const finalTextCount = snapshot.members.reduce((n, m) => n + m.text.length, 0);
  const durationMs = Math.max(
    0,
    new Date(snapshot.endedAt).getTime() - new Date(snapshot.startedAt).getTime(),
  );
  return {
    roundNumber: Math.max(snapshot.roundNumber, 1),
    inspirationCount: snapshot.members.length,
    attachmentCount,
    finalTextCount,
    effectiveEditCount: Math.max(snapshot.effectiveEditCount, 0),
    durationMs,
  };
}

export function roundTitle(number: number): string {
  return `第 ${Math.max(number, 1)} 轮构思`;
}

export function formatDuration(ms: number): string {
  const totalMinutes = Math.max(0, Math.round(ms / 60000));
  if (totalMinutes < 60) return `${totalMinutes} 分钟`;
  return `${Math.floor(totalMinutes / 60)} 小时 ${totalMinutes % 60} 分`;
}

export function formatBytes(size: number): string {
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}

// ---------------------------------------------------------------------------
// 小票导出文本 / Markdown —— 复用同一不可变快照
// ---------------------------------------------------------------------------

function eventAction(kind: RoundEventKind): string {
  switch (kind) {
    case "started":
      return "开始构思";
    case "memberAdded":
      return "加入灵感";
    case "memberRemoved":
      return "移出灵感";
    case "inspirationEdited":
      return "编辑灵感";
    case "ended":
      return "结束本轮构思";
  }
}

function timeline(events: RoundEvent[]): string {
  return events.map((e) => `${e.occurredAt} ${eventAction(e.kind)}`).join("\n");
}

function memberBody(member: ReceiptSnapshotMember): string {
  const body = member.text.trim();
  return body || "未命名灵感";
}

export function receiptPlainText(receipt: Receipt): string {
  const stats = receiptStatistics(receipt.snapshot);
  const header = `NOTE1 · ${receipt.id.slice(0, 8)}\n${receipt.snapshot.collectionName}\n${receipt.snapshot.startedAt} – ${receipt.snapshot.endedAt}`;
  const statLine = `第 ${stats.roundNumber} 轮构思 · ${stats.inspirationCount} 条灵感 · 附件 ${stats.attachmentCount} 个 · 文字 ${stats.finalTextCount} 字 · 有效编辑 ${stats.effectiveEditCount} 次`;
  const content = receipt.snapshot.members
    .map((m, index) => {
      const attachments = m.attachments.length
        ? m.attachments
            .map((a) => `附件：${a.filename} · ${a.mimeType} · ${formatBytes(a.size)}`)
            .join("\n")
        : m.resourceIds.length
          ? `附件：${m.resourceIds.length} 个（旧小票未保留附件元数据）`
          : "无附件";
      return `${index + 1}. ${memberBody(m)}\n${attachments}`;
    })
    .join("\n\n");
  return [header, statLine, "时间路线", timeline(receipt.snapshot.events), content].join(
    "\n",
  );
}

export function receiptMarkdown(receipt: Receipt): string {
  const stats = receiptStatistics(receipt.snapshot);
  const header = [
    `# ${receipt.snapshot.collectionName}`,
    ``,
    `- 编号：NOTE1-${receipt.id.slice(0, 8)}`,
    `- 第 ${stats.roundNumber} 轮构思 · ${stats.inspirationCount} 条灵感 · 附件 ${stats.attachmentCount} 个 · 文字 ${stats.finalTextCount} 字 · 有效编辑 ${stats.effectiveEditCount} 次 · 持续 ${formatDuration(stats.durationMs)}`,
    `- 开始：${receipt.snapshot.startedAt}`,
    `- 结束：${receipt.snapshot.endedAt}`,
  ].join("\n");
  const content = receipt.snapshot.members
    .map((m, index) => {
      const attachments = m.attachments.length
        ? m.attachments
            .map((a) => `- 附件：${a.filename} · \`${a.mimeType}\` · ${formatBytes(a.size)}`)
            .join("\n")
        : m.resourceIds.length
          ? `- 附件：${m.resourceIds.length} 个（旧小票未保留附件元数据）`
          : `- 无附件`;
      return `## ${index + 1}\n\n${memberBody(m)}\n\n${attachments}`;
    })
    .join("\n\n");
  return [header, "## 时间路线", "", timeline(receipt.snapshot.events), "", content].join(
    "\n",
  );
}
