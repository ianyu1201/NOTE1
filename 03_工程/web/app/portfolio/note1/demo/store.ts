// NOTE1 状态容器：把领域引擎与 IndexedDB 仓储桥接成可订阅的外部 store。
// 命令遵循"克隆 → 领域操作 → 原子持久化 → 提交"：写入失败保留原状态，绝不
// 用空数据或半成品覆盖有效数据。本文件不依赖 React。

import * as engine from "./domain/engine";
import type {
  CardFlowState,
  DomainState,
  ID,
  Inspiration,
  Receipt,
  ThinkingCollection,
  ThinkingRound,
} from "./domain/types";
import { DOMAIN_VERSION, emptyState } from "./domain/types";
import { DomainError, StoreError } from "./domain/engine";
import type { BackupFile } from "./storage/backup";
import {
  exportBackup,
  importBackup,
  validateBackup,
} from "./storage/backup";
import {
  clearAllData,
  deleteUnreferencedBlobs,
  deleteBlob,
  getBlob,
  isIndexedDBAvailable,
  loadState,
  openDB,
  putBlob,
  readMeta,
  mutateState,
  writeMeta,
} from "./storage/db";

export type LoadStatus = "loading" | "ready" | "unavailable";

export interface Note1Snapshot {
  status: LoadStatus;
  state: DomainState;
  error: string | null;
  storageEstimate: { usage: number; quota: number } | null;
}

export interface InputFile {
  name: string;
  mimeType: string;
  data: Blob;
}

export interface AssignmentUndoToken {
  inspirationId: ID;
  originalCollectionId: ID | null;
  targetCollectionId: ID;
  originalRoundId: ID | null;
  originalMemberIndex: number | null;
  originalCardFlowState: CardFlowState;
  targetWasCreated: boolean;
}

export type SearchScope = "all" | "inspirations" | "collections" | "receipts";
export type SearchResult =
  | { kind: "inspiration"; inspiration: Inspiration }
  | { kind: "collection"; collection: ThinkingCollection }
  | { kind: "receipt"; receipt: Receipt };

type Listener = () => void;

export class Note1Store {
  private state: DomainState = emptyState();
  private status: LoadStatus = "loading";
  private error: string | null = null;
  private storageEstimate: Note1Snapshot["storageEstimate"] = null;
  private db: IDBDatabase | null = null;
  private listeners = new Set<Listener>();
  private snapshot: Note1Snapshot;
  private channel: BroadcastChannel | null = null;
  private refreshGeneration = 0;
  private refreshOnFocus = () => { void this.refreshFromDisk(); };

  constructor() {
    this.snapshot = this.buildSnapshot();
  }

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getSnapshot = (): Note1Snapshot => this.snapshot;

  get isReady(): boolean {
    return this.status === "ready";
  }

  async load(): Promise<void> {
    try {
      if (!isIndexedDBAvailable()) {
        this.status = "unavailable";
        this.error = "当前浏览器不支持本地存储，NOTE1 无法可靠保存数据。";
        this.commit();
        return;
      }
      this.db = await openDB();
      const meta = await readMeta(this.db);
      if (meta && meta.schemaVersion > DOMAIN_VERSION) {
        this.status = "unavailable";
        this.error = "本地数据版本过新，请更新页面。";
        this.commit();
        return;
      }
      this.state = await loadState(this.db);
      if (!meta) {
        await writeMeta(this.db, {
          schemaVersion: DOMAIN_VERSION,
          initializedAt: new Date().toISOString(),
        });
      }
      this.status = "ready";
      this.error = null;
      if (typeof BroadcastChannel !== "undefined" && !this.channel) {
        this.channel = new BroadcastChannel("note1-local-changes");
        this.channel.onmessage = this.refreshOnFocus;
      }
      if (typeof window !== "undefined") window.addEventListener("focus", this.refreshOnFocus);
      await this.refreshStorageEstimate();
    } catch (err) {
      this.status = "unavailable";
      this.error = err instanceof Error ? err.message : "本机数据读取失败。";
    }
    this.commit();
  }

  // -------------------------------------------------------------------------
  // 内部：事务与提交
  // -------------------------------------------------------------------------

  private buildSnapshot(): Note1Snapshot {
    return {
      status: this.status,
      state: this.state,
      error: this.error,
      storageEstimate: this.storageEstimate,
    };
  }

  private commit(): void {
    this.snapshot = this.buildSnapshot();
    for (const listener of this.listeners) listener();
  }

  private requireWritable(): IDBDatabase {
    if (this.status !== "ready" || !this.db) {
      throw new StoreError("persistenceUnavailable");
    }
    return this.db;
  }

  private async transact<T>(mutate: (state: DomainState) => T): Promise<T> {
    const db = this.requireWritable();
    this.refreshGeneration++;
    const { state, result } = await mutateState(db, mutate);
    this.refreshGeneration++;
    this.state = state;
    this.error = null;
    this.commit();
    this.channel?.postMessage("changed");
    return result;
  }

  private async refreshFromDisk(): Promise<void> {
    if (!this.db || this.status !== "ready") return;
    const generation = ++this.refreshGeneration;
    try {
      const state = await loadState(this.db);
      if (generation !== this.refreshGeneration) return;
      this.state = state;
      this.error = null;
      this.commit();
    } catch (error) {
      this.error = error instanceof Error ? error.message : "本机数据读取失败。";
      this.commit();
    }
  }

  dispose(): void {
    this.channel?.close();
    this.channel = null;
    if (typeof window !== "undefined") window.removeEventListener("focus", this.refreshOnFocus);
  }

  private async refreshStorageEstimate(): Promise<void> {
    try {
      if (typeof navigator !== "undefined" && navigator.storage?.estimate) {
        const estimate = await navigator.storage.estimate();
        this.storageEstimate = {
          usage: estimate.usage ?? 0,
          quota: estimate.quota ?? 0,
        };
      }
    } catch {
      this.storageEstimate = null;
    }
  }

  // -------------------------------------------------------------------------
  // 附件资源
  // -------------------------------------------------------------------------

  private async createResources(files: InputFile[]): Promise<ID[]> {
    const db = this.requireWritable();
    const now = engine.nowISO();
    const createdIds: ID[] = [];
    try {
      for (const file of files) {
        if (file.data.size > 100 * 1024 * 1024) {
          throw new StoreError("attachmentTooLarge", `附件「${file.name}」超过 100 MB。`);
        }
        const id = engine.newID();
        await putBlob(db, id, file.data);
        createdIds.push(id);
      }
      await this.transact((state) => {
        const seen = new Set(state.resources.map((r) => r.id));
        for (let i = 0; i < files.length; i++) {
          const id = createdIds[i];
          if (seen.has(id)) continue;
          state.resources.push({
            id,
            source: "importedAttachment",
            filename: files[i].name,
            mimeType: files[i].mimeType || "application/octet-stream",
            size: files[i].data.size,
            createdAt: now,
          });
        }
      });
    } catch (err) {
      await Promise.all(createdIds.map((id) => deleteBlob(db, id).catch(() => {})));
      throw err;
    }
    return createdIds;
  }

  private async removeOrphanedBlobs(resourceIds: ID[]): Promise<void> {
    if (!this.db) return;
    // Failed garbage collection only leaves unused bytes; the business write
    // has already committed and must not be reported as a rolled-back command.
    await deleteUnreferencedBlobs(this.db, resourceIds).catch(() => {});
  }

  // -------------------------------------------------------------------------
  // 灵感命令
  // -------------------------------------------------------------------------

  async createInspiration(text: string, files: InputFile[]): Promise<Inspiration> {
    const resourceIds = files.length ? await this.createResources(files) : [];
    let created: Inspiration | null = null;
    await this.transact((state) => {
      created = engine.createInspiration(state, text, resourceIds, engine.nowISO());
    });
    if (!created) throw new StoreError("invalidOperation", "灵感创建未完成。");
    return created;
  }

  async createInspirationInCollection(
    collectionId: ID,
    text: string,
    files: InputFile[],
  ): Promise<Inspiration> {
    const resourceIds = files.length ? await this.createResources(files) : [];
    let created: Inspiration | null = null;
    await this.transact((state) => {
      const collection = state.collections.find((c) => c.id === collectionId);
      if (!collection) throw new DomainError("collectionNotFound");
      const roundId = collection.currentRoundId;
      const round = roundId
        ? state.rounds.find((r) => r.id === roundId && r.state === "thinking")
        : undefined;
      if (!round) throw new DomainError("activeRoundRequired");
      if (!text.trim() && resourceIds.length === 0) throw new StoreError("emptyIdea");
      const inspiration: Inspiration = {
        id: engine.newID(),
        text,
        cardFlowState: "visible",
        collectionId,
        createdAt: engine.nowISO(),
        updatedAt: engine.nowISO(),
        resourceIds,
      };
      state.inspirations.push(inspiration);
      round.memberIds.push(inspiration.id);
      round.events.push({
        id: engine.newID(),
        kind: "memberAdded",
        occurredAt: engine.nowISO(),
        inspirationId: inspiration.id,
      });
      created = inspiration;
    });
    if (!created) throw new StoreError("invalidOperation", "灵感创建未完成。");
    return created;
  }

  async updateInspiration(id: ID, text: string): Promise<void> {
    await this.transact((state) => {
      engine.updateInspiration(state, id, text, engine.nowISO(), false);
    });
  }

  async finishInspirationEditSession(
    id: ID,
    originalText: string,
    finalText: string,
  ): Promise<void> {
    await this.transact((state) => {
      engine.finishInspirationEditSession(state, id, originalText, finalText, engine.nowISO());
    });
  }

  async attachFiles(inspirationId: ID, files: InputFile[]): Promise<void> {
    const resourceIds = await this.createResources(files);
    try {
      await this.transact((state) => {
        const inspiration = state.inspirations.find((i) => i.id === inspirationId);
        if (!inspiration) throw new DomainError("inspirationNotFound");
        inspiration.resourceIds.push(...resourceIds);
        inspiration.updatedAt = engine.nowISO();
      });
    } catch (err) {
      await this.removeOrphanedBlobs(resourceIds);
      throw err;
    }
  }

  async removeResource(inspirationId: ID, resourceId: ID): Promise<void> {
    let removed: ID[] = [];
    await this.transact((state) => {
      const inspiration = state.inspirations.find((i) => i.id === inspirationId);
      if (!inspiration || !inspiration.resourceIds.includes(resourceId)) {
        throw new DomainError("resourceNotFound");
      }
      if (inspiration.resourceIds.length <= 1 && !inspiration.text.trim()) {
        throw new StoreError("emptyIdea");
      }
      inspiration.resourceIds = inspiration.resourceIds.filter((id) => id !== resourceId);
      inspiration.updatedAt = engine.nowISO();
      // 仅删除不再被灵感、小票或回收站引用的附件，避免破坏小票快照。
      removed = engine.removeUnreferencedResources(state).map((r) => r.id);
    });
    await this.removeOrphanedBlobs(removed);
  }

  async tuckAway(id: ID): Promise<void> {
    await this.transact((state) => engine.tuckAway(state, id, engine.nowISO()));
  }

  async returnToCardFlow(id: ID): Promise<void> {
    await this.transact((state) => engine.returnToCardFlow(state, id, engine.nowISO()));
  }

  async batchReturnToCardFlow(ids: ID[]): Promise<void> {
    await this.transact((state) => {
      const now = engine.nowISO();
      for (const id of ids) {
        const inspiration = state.inspirations.find((i) => i.id === id);
        if (!inspiration || !engine.inspirationIsArchived(state, inspiration)) {
          throw new DomainError("inspirationNotFound");
        }
        engine.returnToCardFlow(state, id, now);
      }
    });
  }

  // -------------------------------------------------------------------------
  // 构思集命令
  // -------------------------------------------------------------------------

  async createCollection(name?: string): Promise<ThinkingCollection> {
    let created: ThinkingCollection | null = null;
    await this.transact((state) => {
      const collection = engine.createCollection(state, name, engine.nowISO());
      engine.startRound(state, collection.id, [], engine.nowISO());
      created = collection;
    });
    if (!created) throw new StoreError("invalidOperation", "构思集创建未完成。");
    return created;
  }

  async createCollectionAndAssign(
    inspirationId: ID,
    name?: string,
  ): Promise<{ collection: ThinkingCollection; undoToken: AssignmentUndoToken }> {
    return this.transact((state) => {
      const token = this.buildUndoToken(state, inspirationId, "");
      const collection = engine.createCollection(state, name, engine.nowISO());
      engine.startRound(state, collection.id, [], engine.nowISO());
      engine.assign(state, inspirationId, collection.id, engine.nowISO());
      return { collection, undoToken: { ...token, targetCollectionId: collection.id, targetWasCreated: true } };
    });
  }

  async assignToCollection(
    inspirationId: ID,
    collectionId: ID,
  ): Promise<AssignmentUndoToken> {
    return this.transact((state) => {
      const token = this.buildUndoToken(state, inspirationId, collectionId);
      engine.assign(state, inspirationId, collectionId, engine.nowISO());
      return token;
    });
  }

  async undoAssignment(token: AssignmentUndoToken): Promise<void> {
    await this.transact((state) => {
      const inspirationIndex = state.inspirations.findIndex(
        (i) => i.id === token.inspirationId,
      );
      if (inspirationIndex < 0) throw new DomainError("inspirationNotFound");
      const inspiration = state.inspirations[inspirationIndex];
      if (inspiration.collectionId !== token.targetCollectionId) {
        throw new StoreError("invalidOperation", "这次归入已经发生变化，无法撤回。");
      }
      const targetRound = this.activeRoundFor(state, token.targetCollectionId);
      if (!targetRound) {
        throw new StoreError("invalidOperation", "这次归入已经结束，无法撤回。");
      }
      targetRound.memberIds = targetRound.memberIds.filter(
        (id) => id !== token.inspirationId,
      );
      targetRound.events.push({
        id: engine.newID(),
        kind: "memberRemoved",
        occurredAt: engine.nowISO(),
        inspirationId: token.inspirationId,
      });

      if (token.originalCollectionId) {
        const originalCollection = state.collections.find(
          (c) => c.id === token.originalCollectionId,
        );
        if (!originalCollection) {
          throw new StoreError("invalidOperation", "原构思集已不存在，无法撤回这次归入。");
        }
        const originalRoundId = token.originalRoundId ?? originalCollection.currentRoundId;
        if (originalRoundId) {
          const originalRound = state.rounds.find(
            (r) => r.id === originalRoundId && r.state === "thinking",
          );
          if (!originalRound) {
            throw new StoreError("invalidOperation", "原构思集已结束，无法撤回这次归入。");
          }
          const insertionIndex = Math.min(
            Math.max(token.originalMemberIndex ?? originalRound.memberIds.length, 0),
            originalRound.memberIds.length,
          );
          originalRound.memberIds.splice(insertionIndex, 0, token.inspirationId);
          originalRound.events.push({
            id: engine.newID(),
            kind: "memberAdded",
            occurredAt: engine.nowISO(),
            inspirationId: token.inspirationId,
          });
        }
        inspiration.collectionId = token.originalCollectionId;
      } else {
        inspiration.collectionId = null;
      }
      inspiration.cardFlowState = token.originalCardFlowState;
      inspiration.updatedAt = engine.nowISO();

      if (
        token.targetWasCreated &&
        targetRound.memberIds.length === 0
      ) {
        const targetIndex = state.rounds.findIndex((r) => r.id === targetRound.id);
        if (targetIndex >= 0) state.rounds.splice(targetIndex, 1);
        state.collections = state.collections.filter(
          (c) => c.id !== token.targetCollectionId,
        );
      }
    });
  }

  private buildUndoToken(
    state: DomainState,
    inspirationId: ID,
    providedTarget: ID,
  ): AssignmentUndoToken {
    const inspiration = state.inspirations.find((i) => i.id === inspirationId);
    if (!inspiration) throw new DomainError("inspirationNotFound");
    const originalRoundId = inspiration.collectionId
      ? state.collections.find((c) => c.id === inspiration.collectionId)?.currentRoundId ??
        null
      : null;
    const originalMemberIndex = originalRoundId
      ? state.rounds.find((r) => r.id === originalRoundId)?.memberIds.indexOf(inspirationId) ??
        null
      : null;
    return {
      inspirationId,
      originalCollectionId: inspiration.collectionId,
      targetCollectionId: providedTarget,
      originalRoundId,
      originalMemberIndex: originalMemberIndex === undefined ? null : originalMemberIndex,
      originalCardFlowState: inspiration.cardFlowState,
      targetWasCreated: false,
    };
  }

  private activeRoundFor(
    state: DomainState,
    collectionId: ID,
  ): ThinkingRound | undefined {
    const roundId = state.collections.find((c) => c.id === collectionId)?.currentRoundId;
    return roundId
      ? state.rounds.find((r) => r.id === roundId && r.state === "thinking")
      : undefined;
  }

  async renameCollection(id: ID, name: string): Promise<void> {
    const trimmed = name.trim();
    if (!trimmed) throw new StoreError("invalidOperation", "构思集名称不能为空。");
    await this.transact((state) => {
      const collection = state.collections.find((c) => c.id === id);
      if (!collection) throw new DomainError("collectionNotFound");
      collection.name = trimmed;
    });
  }

  async removeFromCollection(inspirationId: ID): Promise<void> {
    await this.transact((state) => engine.removeFromCollection(state, inspirationId, engine.nowISO()));
  }

  async reorderMembers(roundId: ID, memberIds: ID[]): Promise<void> {
    await this.transact((state) => engine.reorderMembers(state, roundId, memberIds));
  }

  async continueThinking(collectionId: ID): Promise<ThinkingRound> {
    let round: ThinkingRound | null = null;
    await this.transact((state) => {
      round = engine.continueRound(state, collectionId, engine.nowISO());
    });
    if (!round) throw new StoreError("invalidOperation", "继续构思未完成。");
    return round;
  }

  async endRound(roundId: ID): Promise<Receipt> {
    let receipt: Receipt | null = null;
    await this.transact((state) => {
      receipt = engine.endRound(state, roundId, engine.nowISO());
    });
    if (!receipt) throw new StoreError("invalidOperation", "构思小票生成未完成。");
    return receipt;
  }

  async undoEndRound(receiptId: ID): Promise<void> {
    await this.transact((state) => engine.undoEndRound(state, receiptId, engine.nowISO()));
  }

  // -------------------------------------------------------------------------
  // 删除与回收站
  // -------------------------------------------------------------------------

  async deleteInspiration(id: ID): Promise<string[]> {
    return this.batchDeleteInspirations([id]);
  }

  async batchDeleteInspirations(ids: ID[]): Promise<string[]> {
    let created: string[] = [];
    await this.transact((state) => {
      const before = new Set(state.trash.map((t) => t.id));
      const now = engine.nowISO();
      for (const id of ids) engine.deleteInspiration(state, id, now);
      created = state.trash.filter((t) => !before.has(t.id)).map((t) => t.id);
    });
    return created;
  }

  async deleteReceipt(id: ID): Promise<string[]> {
    return this.batchDeleteReceipts([id]);
  }

  async batchDeleteReceipts(ids: ID[]): Promise<string[]> {
    let created: string[] = [];
    await this.transact((state) => {
      const before = new Set(state.trash.map((t) => t.id));
      const now = engine.nowISO();
      for (const id of ids) engine.deleteReceipt(state, id, now);
      created = state.trash.filter((t) => !before.has(t.id)).map((t) => t.id);
    });
    return created;
  }

  async deleteCollection(id: ID): Promise<void> {
    await this.transact((state) => engine.deleteCollection(state, id, engine.nowISO()));
  }

  async restoreTrash(ids: ID[]): Promise<void> {
    await this.transact((state) => {
      const now = engine.nowISO();
      for (const id of ids) engine.restoreTrash(state, id, now);
    });
  }

  async permanentlyDeleteTrash(ids: ID[]): Promise<void> {
    let removed: ID[] = [];
    await this.transact((state) => {
      engine.permanentlyDeleteTrash(state, new Set(ids));
      removed = engine.removeUnreferencedResources(state).map((r) => r.id);
    });
    await this.removeOrphanedBlobs(removed);
  }

  async emptyTrash(): Promise<void> {
    let removed: ID[] = [];
    await this.transact((state) => {
      engine.permanentlyDeleteTrash(state, new Set(state.trash.map((t) => t.id)));
      removed = engine.removeUnreferencedResources(state).map((r) => r.id);
    });
    await this.removeOrphanedBlobs(removed);
  }

  async purgeExpiredTrash(): Promise<void> {
    const before = new Set(this.state.trash.map((t) => t.id));
    let removed: ID[] = [];
    await this.transact((state) => {
      engine.purgeExpiredTrash(state, engine.nowISO());
      removed = engine.removeUnreferencedResources(state).map((r) => r.id);
    });
    const after = new Set(this.state.trash.map((t) => t.id));
    // 仅在上一步真的移除了回收站条目后才返回资源，避免误删。
    if ([...before].some((id) => !after.has(id))) {
      await this.removeOrphanedBlobs(removed);
    }
  }

  // -------------------------------------------------------------------------
  // 附件读取（预览 / 播放 / 下载）
  // -------------------------------------------------------------------------

  async getAttachmentBlob(resourceId: ID): Promise<Blob | undefined> {
    if (!this.db) return undefined;
    return getBlob(this.db, resourceId);
  }

  async getAttachmentUrl(resourceId: ID): Promise<string | undefined> {
    const blob = await this.getAttachmentBlob(resourceId);
    return blob ? URL.createObjectURL(blob) : undefined;
  }

  // -------------------------------------------------------------------------
  // 备份与清理
  // -------------------------------------------------------------------------

  async exportBackup(): Promise<BackupFile> {
    const db = this.requireWritable();
    return exportBackup(db);
  }

  async validateBackup(text: string): Promise<void> {
    await validateBackup(text);
  }

  async importBackup(text: string): Promise<void> {
    const db = this.requireWritable();
    this.refreshGeneration++;
    await importBackup(db, text);
    this.state = await loadState(db);
    this.error = null;
    await this.refreshStorageEstimate();
    this.commit();
    this.channel?.postMessage("changed");
  }

  async clearAllData(): Promise<void> {
    const db = this.requireWritable();
    this.refreshGeneration++;
    await clearAllData(db);
    this.state = emptyState();
    this.error = null;
    await this.refreshStorageEstimate();
    this.commit();
    this.channel?.postMessage("changed");
  }

  // -------------------------------------------------------------------------
  // 搜索
  // -------------------------------------------------------------------------

  search(query: string, scope: SearchScope = "all"): SearchResult[] {
    const q = query.trim();
    if (!q) return [];
    const results: SearchResult[] = [];
    const matchesResource = (resourceIds: ID[]) =>
      resourceIds.some((rid) => {
        const r = this.state.resources.find((res) => res.id === rid);
        return r ? r.filename.toLowerCase().includes(q.toLowerCase()) : false;
      });
    const matchesText = (text: string) => text.toLowerCase().includes(q.toLowerCase());

    if (scope === "all" || scope === "inspirations") {
      for (const i of this.state.inspirations) {
        if (matchesText(i.text) || matchesResource(i.resourceIds)) {
          results.push({ kind: "inspiration", inspiration: i });
        }
      }
    }
    if (scope === "all" || scope === "collections") {
      for (const c of this.state.collections) {
        if (matchesText(c.name)) results.push({ kind: "collection", collection: c });
      }
    }
    if (scope === "all" || scope === "receipts") {
      for (const r of this.state.receipts) {
        if (
          matchesText(r.snapshot.collectionName) ||
          r.snapshot.members.some(
            (m) => matchesText(m.text) || matchesResource(m.resourceIds),
          )
        ) {
          results.push({ kind: "receipt", receipt: r });
        }
      }
    }
    return results;
  }
}
