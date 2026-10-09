// NOTE1 Web 的 IndexedDB 仓储。业务元数据与附件 Blob 分仓：列表与搜索只读
// 元数据，Blob 仅在预览、下载或备份时读取。整个领域状态作为单个记录原子写入，
// 保证批量操作"全成或全败"，不会出现只保存一半的状态。

import type { DomainState } from "../domain/types";
import { DOMAIN_VERSION, emptyState } from "../domain/types";

export const DB_NAME = "ianyu-note1-web";
export const DB_VERSION = 1;

const META_KEY = "root";
const STATE_KEY = "data";

interface MetaRecord {
  schemaVersion: number;
  initializedAt: string;
}

export interface BlobEntry {
  id: string;
  blob: Blob;
}

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed"));
  });
}

function transactionDone(tx: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error("IndexedDB transaction failed"));
    tx.onabort = () => reject(tx.error ?? new Error("IndexedDB transaction aborted"));
  });
}

export function isIndexedDBAvailable(): boolean {
  return typeof indexedDB !== "undefined" && indexedDB !== null;
}

export async function openDB(): Promise<IDBDatabase> {
  if (!isIndexedDBAvailable()) {
    throw new Error("IndexedDB 在当前浏览器不可用");
  }
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("meta")) {
        db.createObjectStore("meta");
      }
      if (!db.objectStoreNames.contains("state")) {
        db.createObjectStore("state");
      }
      if (!db.objectStoreNames.contains("resourceBlobs")) {
        db.createObjectStore("resourceBlobs");
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("无法打开 IndexedDB"));
    request.onblocked = () =>
      reject(new Error("IndexedDB 被其他页面占用，请关闭其他 NOTE1 标签页后重试"));
  });
}

// ---------------------------------------------------------------------------
// 元信息（schema 版本 + 初始化标记）
// ---------------------------------------------------------------------------

export async function readMeta(db: IDBDatabase): Promise<MetaRecord | null> {
  const tx = db.transaction("meta", "readonly");
  const record = await requestToPromise(tx.objectStore("meta").get(META_KEY));
  await transactionDone(tx);
  return (record as MetaRecord | undefined) ?? null;
}

export async function writeMeta(db: IDBDatabase, meta: MetaRecord): Promise<void> {
  const tx = db.transaction("meta", "readwrite");
  tx.objectStore("meta").put(meta, META_KEY);
  await transactionDone(tx);
}

// ---------------------------------------------------------------------------
// 领域状态读写
// ---------------------------------------------------------------------------

export async function loadState(db: IDBDatabase): Promise<DomainState> {
  const tx = db.transaction("state", "readonly");
  const record = await requestToPromise(tx.objectStore("state").get(STATE_KEY));
  await transactionDone(tx);
  if (!record) return emptyState();
  return record as DomainState;
}

export async function saveState(db: IDBDatabase, state: DomainState): Promise<void> {
  const tx = db.transaction("state", "readwrite");
  tx.objectStore("state").put(state, STATE_KEY);
  await transactionDone(tx);
}

// Read and mutate within the same write transaction. IndexedDB serializes this
// transaction across connections, so another tab cannot overwrite newer data.
export function mutateState<T>(
  db: IDBDatabase,
  mutate: (state: DomainState) => T,
): Promise<{ state: DomainState; result: T }> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction("state", "readwrite");
    const store = tx.objectStore("state");
    let candidate: DomainState;
    let result: T;
    let failure: unknown;
    const read = store.get(STATE_KEY);
    read.onsuccess = () => {
      try {
        candidate = (read.result as DomainState | undefined) ?? emptyState();
        result = mutate(candidate);
        store.put(candidate, STATE_KEY);
      } catch (error) {
        failure = error;
        tx.abort();
      }
    };
    tx.oncomplete = () => resolve({ state: candidate, result });
    tx.onabort = tx.onerror = () => reject(failure ?? tx.error ?? new Error("本机数据保存失败。"));
  });
}

export async function readBackupData(db: IDBDatabase): Promise<{ state: DomainState; blobs: BlobEntry[] }> {
  const tx = db.transaction(["state", "resourceBlobs"], "readonly");
  const done = transactionDone(tx);
  const stateRequest = requestToPromise(tx.objectStore("state").get(STATE_KEY));
  const blobStore = tx.objectStore("resourceBlobs");
  const keysRequest = requestToPromise(blobStore.getAllKeys());
  const blobsRequest = requestToPromise(blobStore.getAll());
  const [state, keys, blobs] = await Promise.all([stateRequest, keysRequest, blobsRequest]);
  await done;
  return {
    state: (state as DomainState | undefined) ?? emptyState(),
    blobs: (blobs as Blob[]).map((blob, index) => ({ id: String(keys[index]), blob })),
  };
}

export function deleteUnreferencedBlobs(db: IDBDatabase, ids: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(["state", "resourceBlobs"], "readwrite");
    const read = tx.objectStore("state").get(STATE_KEY);
    read.onsuccess = () => {
      const state = (read.result as DomainState | undefined) ?? emptyState();
      const retained = new Set(state.resources.map((resource) => resource.id));
      for (const id of ids) if (!retained.has(id)) tx.objectStore("resourceBlobs").delete(id);
    };
    tx.oncomplete = () => resolve();
    tx.onabort = tx.onerror = () => reject(tx.error ?? new Error("附件清理失败。"));
  });
}

// ---------------------------------------------------------------------------
// 附件 Blob 读写
// ---------------------------------------------------------------------------

export async function putBlob(db: IDBDatabase, id: string, blob: Blob): Promise<void> {
  const tx = db.transaction("resourceBlobs", "readwrite");
  tx.objectStore("resourceBlobs").put(blob, id);
  await transactionDone(tx);
}

export async function getBlob(db: IDBDatabase, id: string): Promise<Blob | undefined> {
  const tx = db.transaction("resourceBlobs", "readonly");
  const record = await requestToPromise(tx.objectStore("resourceBlobs").get(id));
  await transactionDone(tx);
  return (record as Blob | undefined) ?? undefined;
}

export async function deleteBlob(db: IDBDatabase, id: string): Promise<void> {
  const tx = db.transaction("resourceBlobs", "readwrite");
  tx.objectStore("resourceBlobs").delete(id);
  await transactionDone(tx);
}

export async function getAllBlobs(db: IDBDatabase): Promise<BlobEntry[]> {
  const tx = db.transaction("resourceBlobs", "readonly");
  const records = await requestToPromise(tx.objectStore("resourceBlobs").getAll());
  const keys = await requestToPromise(tx.objectStore("resourceBlobs").getAllKeys());
  await transactionDone(tx);
  const blobs = records as Blob[];
  const ids = keys as IDBValidKey[];
  return blobs.map((blob, index) => ({ id: String(ids[index]), blob }));
}

export async function writeBlobs(
  db: IDBDatabase,
  entries: BlobEntry[],
): Promise<void> {
  const tx = db.transaction("resourceBlobs", "readwrite");
  const store = tx.objectStore("resourceBlobs");
  for (const entry of entries) store.put(entry.blob, entry.id);
  await transactionDone(tx);
}

export async function clearAllData(db: IDBDatabase): Promise<void> {
  const tx = db.transaction(["state", "resourceBlobs"], "readwrite");
  tx.objectStore("state").clear();
  tx.objectStore("resourceBlobs").clear();
  await transactionDone(tx);
}

export async function replaceAllData(
  db: IDBDatabase,
  state: DomainState,
  blobs: BlobEntry[],
): Promise<void> {
  // 单事务整体替换：先清空再写入，任一步失败整个事务回滚，旧数据保持不变。
  const tx = db.transaction(["state", "resourceBlobs"], "readwrite");
  const stateStore = tx.objectStore("state");
  const blobStore = tx.objectStore("resourceBlobs");
  stateStore.clear();
  blobStore.clear();
  stateStore.put(state, STATE_KEY);
  for (const entry of blobs) blobStore.put(entry.blob, entry.id);
  await transactionDone(tx);
}

export async function schemaVersionOk(meta: MetaRecord | null): Promise<boolean> {
  return (meta?.schemaVersion ?? DOMAIN_VERSION) <= DOMAIN_VERSION;
}
