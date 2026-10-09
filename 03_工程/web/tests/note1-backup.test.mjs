import test, { after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import ts from "typescript";
import { emptyState } from "../app/portfolio/note1/demo/domain/types.ts";
import * as E from "../app/portfolio/note1/demo/domain/engine.ts";

// Exercise the production validator without mocking its imports or logic.
const directory = await mkdtemp(join(tmpdir(), "note1-backup-tests-"));
for (const file of ["domain/types", "storage/db", "storage/backup"]) {
  const source = await readFile(new URL(`../app/portfolio/note1/demo/${file}.ts`, import.meta.url), "utf8");
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText
    .replace(/from "(\.[^"]+)"/g, 'from "$1.mjs"');
  await mkdir(join(directory, file.split("/")[0]), { recursive: true });
  await writeFile(join(directory, `${file}.mjs`), compiled);
}
const { validateBackup } = await import(pathToFileURL(join(directory, "storage/backup.mjs")));
after(() => rm(directory, { recursive: true, force: true }));

function receiptFixture() {
  const state = emptyState();
  const now = E.nowISO();
  state.resources.push({ id: "attachment", source: "importedAttachment", filename: "evidence.txt", mimeType: "text/plain", size: 3, createdAt: now });
  const collection = E.createCollection(state, "历史附件", now);
  const round = E.startRound(state, collection.id, [], now);
  const inspiration = E.createInspiration(state, "冻结正文", ["attachment"], now);
  E.assign(state, inspiration.id, collection.id, now);
  const receipt = E.endRound(state, round.id, now);
  return { state, collection, receipt };
}
async function backupText(data, withBlob = true) {
  const blobs = withBlob ? [{ resourceId: "attachment", mimeType: "text/plain", base64: btoa("abc") }] : [];
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify({ data, blobs })));
  return JSON.stringify({ format: "note1-web-backup", version: 1, data, blobs, integrity: { algorithm: "SHA-256", digest: Buffer.from(digest).toString("hex") } });
}

test("构思集删除后，小票快照及附件仍可通过备份校验", async () => {
  const { state, collection, receipt } = receiptFixture();
  const snapshot = structuredClone(receipt.snapshot);
  E.deleteCollection(state, collection.id, E.nowISO());
  const backup = await validateBackup(await backupText(state));
  assert.deepEqual(backup.data.receipts[0].snapshot, snapshot);
  assert.equal(backup.data.collections.length, 0);
});

test("原构思集已删除的回收站小票仍可恢复备份", async () => {
  const { state, collection, receipt } = receiptFixture();
  E.deleteCollection(state, collection.id, E.nowISO());
  E.deleteReceipt(state, receipt.id, E.nowISO());
  assert.equal((await validateBackup(await backupText(state))).data.trash.some((entry) => entry.object.kind === "receipt"), true);
});

test("回收站小票引用的附件缺失时拒绝备份", async () => {
  const { state, collection, receipt } = receiptFixture();
  E.deleteCollection(state, collection.id, E.nowISO());
  E.deleteReceipt(state, receipt.id, E.nowISO());
  state.trash = state.trash.filter((entry) => entry.object.kind === "receipt");
  await assert.rejects(validateBackup(await backupText(state, false)), /回收站小票引用的附件/);
});

test("当前构思集对不存在轮次的引用仍被拒绝", async () => {
  const { state, collection } = receiptFixture();
  collection.currentRoundId = "missing-round";
  await assert.rejects(validateBackup(await backupText(state)), /构思集引用了不存在的轮次/);
});
