// NOTE1 Web 备份导出 / 校验 / 恢复。备份格式带 schema 版本、导出时间与
// SHA-256 完整性摘要；恢复前完整校验，失败不改变当前数据。

import type { DomainState } from "../domain/types";
import { DOMAIN_VERSION } from "../domain/types";
import type { BlobEntry } from "./db";
import {
  getAllBlobs,
  readBackupData,
  replaceAllData,
} from "./db";

const BACKUP_FORMAT = "note1-web-backup";
const BACKUP_VERSION = 1;
const APP_VERSION = "0.1.0";
// 单文件与总大小上限（待目标移动浏览器实测后冻结，见转换手册 §12/§18）。
export const MAX_BACKUP_FILE_BYTES = 64 * 1024 * 1024;
export const MAX_BACKUP_TOTAL_BYTES = 60 * 1024 * 1024;

export interface BackupAttachmentBlob {
  resourceId: string;
  mimeType: string;
  base64: string;
}

export interface WebBackup {
  format: typeof BACKUP_FORMAT;
  version: number;
  exportedAt: string;
  appVersion: string;
  data: DomainState;
  blobs: BackupAttachmentBlob[];
  integrity: { algorithm: "SHA-256"; digest: string };
}

export interface BackupFile {
  filename: string;
  blob: Blob;
}

function backupFileName(): string {
  const stamp = new Date().toISOString().slice(0, 10);
  return `note1-web-backup-${stamp}.json`;
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function decodeBase64(base64: string): Uint8Array<ArrayBuffer> {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function blobToBase64(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  return encodeBase64(new Uint8Array(buffer));
}

async function sha256Hex(text: string): Promise<string> {
  if (typeof crypto === "undefined" || !crypto.subtle) {
    throw new Error("当前环境不支持完整性校验，无法生成或导入备份。");
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function canonicalContent(data: DomainState, blobs: BackupAttachmentBlob[]): string {
  return JSON.stringify({ data, blobs });
}

// ---------------------------------------------------------------------------
// 导出
// ---------------------------------------------------------------------------

export async function exportBackup(
  db: IDBDatabase,
): Promise<BackupFile> {
  const { state, blobs: storedBlobs } = await readBackupData(db);
  const referenced = new Set<string>();
  for (const i of state.inspirations) i.resourceIds.forEach((id) => referenced.add(id));
  for (const r of state.receipts)
    r.snapshot.members.forEach((m) => m.resourceIds.forEach((id) => referenced.add(id)));
  for (const t of state.trash) {
    if (t.object.kind === "inspiration") {
      t.object.inspiration.resourceIds.forEach((id) => referenced.add(id));
    } else {
      t.object.receipt.snapshot.members.forEach((m) =>
        m.resourceIds.forEach((id) => referenced.add(id)),
      );
    }
  }

  // 只导出仍被引用的资源；缺少任一被引用附件时整个备份失败。
  const resources = state.resources.filter((r) => referenced.has(r.id));
  const blobs: BackupAttachmentBlob[] = [];
  let totalBytes = 0;
  for (const resource of resources) {
    const blob = storedBlobs.find((entry) => entry.id === resource.id)?.blob;
    if (!blob) {
      throw new Error(`附件「${resource.filename}」缺失，无法完成备份。`);
    }
    totalBytes += blob.size;
    if (totalBytes > MAX_BACKUP_TOTAL_BYTES) {
      throw new Error("备份内容超过总大小上限，请先清理附件。");
    }
    blobs.push({
      resourceId: resource.id,
      mimeType: resource.mimeType,
      base64: await blobToBase64(blob),
    });
  }

  const backup: WebBackup = {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt: new Date().toISOString(),
    appVersion: APP_VERSION,
    data: { ...state, version: DOMAIN_VERSION, resources },
    blobs,
    integrity: {
      algorithm: "SHA-256",
      digest: await sha256Hex(
        canonicalContent({ ...state, resources }, blobs),
      ),
    },
  };
  const json = JSON.stringify(backup);
  if (json.length > MAX_BACKUP_FILE_BYTES) {
    throw new Error("备份文件超过大小上限，请先清理附件或导出为纯文本。");
  }
  return {
    filename: backupFileName(),
    blob: new Blob([json], { type: "application/json" }),
  };
}

// ---------------------------------------------------------------------------
// 校验
// ---------------------------------------------------------------------------

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertUniqueIds(ids: string[], label: string): void {
  if (new Set(ids).size !== ids.length) {
    throw new Error(`备份中包含重复的 ${label} 编号。`);
  }
}

export async function parseBackup(text: string): Promise<WebBackup> {
  if (text.length > MAX_BACKUP_FILE_BYTES * 2) {
    throw new Error("备份文件过大，已拒绝导入。");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("备份文件不是有效的 JSON。");
  }
  if (!isPlainObject(parsed)) throw new Error("备份结构无效。");
  if (parsed.format !== BACKUP_FORMAT) throw new Error("这不是 NOTE1 Web 备份文件。");
  if (typeof parsed.version !== "number" || parsed.version > BACKUP_VERSION) {
    throw new Error("备份版本过新，请更新 NOTE1 后再导入。");
  }
  if (!isPlainObject(parsed.data)) throw new Error("备份缺少数据内容。");
  if (!Array.isArray(parsed.blobs)) throw new Error("备份缺少附件内容。");
  if (!isPlainObject(parsed.integrity) || parsed.integrity.algorithm !== "SHA-256") {
    throw new Error("备份缺少完整性信息。");
  }
  return parsed as unknown as WebBackup;
}

export async function verifyIntegrity(backup: WebBackup): Promise<boolean> {
  const digest = await sha256Hex(
    canonicalContent(backup.data, backup.blobs),
  );
  return digest === backup.integrity.digest;
}

export async function validateBackup(text: string): Promise<WebBackup> {
  const backup = await parseBackup(text);
  if (!(await verifyIntegrity(backup))) {
    throw new Error("备份完整性校验失败，文件可能已被修改或损坏。");
  }

  const data = backup.data;
  const inspirations = Array.isArray(data.inspirations) ? data.inspirations : [];
  const collections = Array.isArray(data.collections) ? data.collections : [];
  const rounds = Array.isArray(data.rounds) ? data.rounds : [];
  const resources = Array.isArray(data.resources) ? data.resources : [];
  const receipts = Array.isArray(data.receipts) ? data.receipts : [];
  const trash = Array.isArray(data.trash) ? data.trash : [];

  assertUniqueIds(inspirations.map((i) => i.id), "灵感");
  assertUniqueIds(collections.map((c) => c.id), "构思集");
  assertUniqueIds(rounds.map((r) => r.id), "构思轮次");
  assertUniqueIds(resources.map((r) => r.id), "附件");
  assertUniqueIds(receipts.map((r) => r.id), "小票");
  assertUniqueIds(trash.map((t) => t.id), "回收站");
  assertUniqueIds(backup.blobs.map((b) => b.resourceId), "附件内容");

  const resourceIds = new Set(resources.map((r) => r.id));
  const blobIds = new Set(backup.blobs.map((b) => b.resourceId));

  // 每个被引用的资源都必须在 resources 与 blobs 中同时存在。
  const collectionIds = new Set(collections.map((c) => c.id));
  const roundIds = new Set(rounds.map((r) => r.id));
  const inspirationIds = new Set(inspirations.map((i) => i.id));

  const checkCollection = (id: unknown) =>
    typeof id === "string" && collectionIds.has(id);
  const checkRound = (id: unknown) =>
    typeof id === "string" && roundIds.has(id);
  const checkInspiration = (id: unknown) =>
    typeof id === "string" && inspirationIds.has(id);

  for (const c of collections) {
    if (c.currentRoundId !== null && !checkRound(c.currentRoundId)) {
      throw new Error("构思集引用了不存在的轮次。");
    }
  }
  for (const r of rounds) {
    if (!checkCollection(r.collectionId)) throw new Error("轮次引用了不存在的构思集。");
    for (const memberId of r.memberIds) {
      if (!checkInspiration(memberId)) throw new Error("构思轮次引用了不存在的灵感。");
    }
  }
  for (const i of inspirations) {
    if (i.collectionId !== null && !checkCollection(i.collectionId)) {
      throw new Error("灵感引用了不存在的构思集。");
    }
    for (const rid of i.resourceIds) {
      if (!resourceIds.has(rid) || !blobIds.has(rid)) {
        throw new Error(`灵感引用的附件「${rid}」缺少内容。`);
      }
    }
  }
  for (const receipt of receipts) {
    // A receipt owns a frozen snapshot and survives deletion of its source.
    for (const member of receipt.snapshot.members) {
      for (const rid of member.resourceIds) {
        if (!resourceIds.has(rid) || !blobIds.has(rid)) {
          throw new Error(`小票引用的附件「${rid}」缺少内容。`);
        }
      }
    }
  }
  for (const entry of trash) {
    const object = entry.object;
    if (object && object.kind === "inspiration") {
      for (const rid of object.inspiration.resourceIds) {
        if (!resourceIds.has(rid) || !blobIds.has(rid)) {
          throw new Error(`回收站引用的附件「${rid}」缺少内容。`);
        }
      }
    } else if (object && object.kind === "receipt") {
      for (const member of object.receipt.snapshot.members) {
        for (const rid of member.resourceIds) {
          if (!resourceIds.has(rid) || !blobIds.has(rid)) {
            throw new Error(`回收站小票引用的附件「${rid}」缺少内容。`);
          }
        }
      }
    }
  }

  // 附件编码校验：base64 可解码且大小在限制内。
  let totalBlobBytes = 0;
  for (const blobEntry of backup.blobs) {
    if (typeof blobEntry.base64 !== "string" || blobEntry.base64.length === 0) {
      throw new Error("附件内容为空。");
    }
    let bytes: Uint8Array;
    try {
      bytes = decodeBase64(blobEntry.base64);
    } catch {
      throw new Error("附件内容编码无效。");
    }
    totalBlobBytes += bytes.byteLength;
    if (totalBlobBytes > MAX_BACKUP_TOTAL_BYTES) {
      throw new Error("备份附件总大小超过上限。");
    }
  }

  return backup;
}

// ---------------------------------------------------------------------------
// 恢复
// ---------------------------------------------------------------------------

export async function importBackup(
  db: IDBDatabase,
  text: string,
): Promise<void> {
  const backup = await validateBackup(text);
  const entries: BlobEntry[] = backup.blobs.map((b) => ({
    id: b.resourceId,
    blob: new Blob([decodeBase64(b.base64)], { type: b.mimeType }),
  }));
  const state: DomainState = { ...backup.data, version: DOMAIN_VERSION };
  await replaceAllData(db, state, entries);
  const verify = await getAllBlobs(db);
  if (verify.length !== entries.length) {
    throw new Error("恢复写入校验失败，请重试。");
  }
}
