import test from "node:test";
import assert from "node:assert/strict";
import { emptyState } from "../app/portfolio/note1/demo/domain/types.ts";
import * as E from "../app/portfolio/note1/demo/domain/engine.ts";

function inspiration(state, text = "灵感 A", now = new Date(1700000000000).toISOString()) {
  return E.createInspiration(state, text, [], now);
}

test("小票成员归入已收起，兼容旧记录；继续构思恢复且不改小票", () => {
  const state = emptyState();
  const c = E.createCollection(state, "归档验证", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state);
  E.assign(state, item.id, c.id, E.nowISO());
  assert.equal(E.inspirationIsArchived(state, item), false);
  const receipt = E.endRound(state, round.id, E.nowISO());
  const snapshot = JSON.stringify(receipt.snapshot);
  assert.equal(item.cardFlowState, "tuckedAway");
  assert.equal(E.inspirationIsArchived(state, item), true);
  item.cardFlowState = "visible";
  assert.equal(E.inspirationIsArchived(state, item), true);
  E.continueRound(state, c.id, E.nowISO());
  assert.equal(E.inspirationIsArchived(state, item), false);
  assert.equal(JSON.stringify(receipt.snapshot), snapshot);
});

test("已结束成员放回卡片流，只解除当前关联，不修改历史小票", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state);
  E.assign(state, item.id, c.id, E.nowISO());
  const receipt = E.endRound(state, round.id, E.nowISO());
  E.returnToCardFlow(state, item.id, E.nowISO());
  assert.equal(item.collectionId, null);
  assert.equal(E.inspirationIsArchived(state, item), false);
  assert.equal(receipt.snapshot.members[0].inspirationId, item.id);
});

test("创建灵感：空文字且无附件时拒绝", () => {
  const state = emptyState();
  assert.throws(() => E.createInspiration(state, "   ", [], E.nowISO()), /文字或附件/);
});

test("创建优点：有效内容入库并默认进入卡片流", () => {
  const state = emptyState();
  const item = inspiration(state, "记下此刻");
  assert.equal(state.inspirations.length, 1);
  assert.equal(item.cardFlowState, "visible");
  assert.equal(item.collectionId, null);
});

test("构思集与轮次：首轮为 1 且活动轮次不能再开新轮", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const r1 = E.startRound(state, c.id, [], E.nowISO());
  assert.equal(r1.roundNumber, 1);
  assert.equal(c.nextRoundNumber, 2);
  assert.throws(() => E.startRound(state, c.id, [], E.nowISO()), /轮次/);
});

test("归入构思集：同一灵感只属于一个构思集，移动会从旧轮次移除", () => {
  const state = emptyState();
  const a = E.createCollection(state, "A", E.nowISO());
  const b = E.createCollection(state, "B", E.nowISO());
  E.startRound(state, a.id, [], E.nowISO());
  const roundB = E.startRound(state, b.id, [], E.nowISO());
  const item = inspiration(state, "漂流的灵感");

  E.assign(state, item.id, a.id, E.nowISO());
  assert.equal(item.collectionId, a.id);
  E.assign(state, item.id, b.id, E.nowISO());
  assert.equal(item.collectionId, b.id);
  assert.ok(roundB.memberIds.includes(item.id));
  assert.ok(!state.rounds.find((r) => r.collectionId === a.id).memberIds.includes(item.id));
});

test("归入没有进行中轮次的构思集会失败", () => {
  const state = emptyState();
  const c = E.createCollection(state, undefined, E.nowISO());
  const item = inspiration(state, "无处可去");
  assert.throws(() => E.assign(state, item.id, c.id, E.nowISO()), /轮次/);
});

test("结束轮次：空轮次拒绝，生成不可变小票，重复结束拒绝", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  assert.throws(() => E.endRound(state, round.id, E.nowISO()), /至少一条灵感/);

  const item = inspiration(state, "一条灵感");
  E.assign(state, item.id, c.id, E.nowISO());
  const receipt = E.endRound(state, round.id, E.nowISO());
  assert.equal(state.receipts.length, 1);
  assert.equal(round.state, "ended");
  assert.equal(c.currentRoundId, null);
  assert.equal(receipt.snapshot.members.length, 1);
  assert.throws(() => E.endRound(state, round.id, E.nowISO()), /已经生成/);
});

test("小票不可变：结束后编辑灵感不改变快照", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state, "原始正文");
  E.assign(state, item.id, c.id, E.nowISO());
  const receipt = E.endRound(state, round.id, E.nowISO());
  const frozen = receipt.snapshot.members[0].text;

  E.updateInspiration(state, item.id, "修改后的正文", E.nowISO(), false);
  assert.equal(receipt.snapshot.members[0].text, frozen);
});

test("有效编辑只在活动轮次内计数一次（编辑会话）", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state, "初稿");
  E.assign(state, item.id, c.id, E.nowISO());
  E.finishInspirationEditSession(state, item.id, "初稿", "定稿", E.nowISO());
  assert.equal(round.effectiveEditCount, 1);
  E.finishInspirationEditSession(state, item.id, "定稿", "定稿", E.nowISO());
  assert.equal(round.effectiveEditCount, 1); // 会话内没有真正改动不计
});

test("删除灵感进回收站，删除构思集把成员移入回收站", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state, "会离开");
  E.assign(state, item.id, c.id, E.nowISO());
  E.deleteCollection(state, c.id, E.nowISO());
  assert.equal(state.collections.length, 0);
  assert.equal(state.inspirations.length, 0);
  assert.equal(state.trash.length, 1);
  assert.equal(state.trash[0].object.kind, "inspiration");
});

test("恢复回收站与永久删除", () => {
  const state = emptyState();
  const item = inspiration(state, "可恢复");
  E.deleteInspiration(state, item.id, E.nowISO());
  const entry = state.trash[0];
  E.restoreTrash(state, entry.id, E.nowISO());
  assert.equal(state.inspirations.length, 1);
  E.deleteInspiration(state, item.id, E.nowISO());
  const entry2 = state.trash[0];
  E.permanentlyDeleteTrash(state, new Set([entry2.id]));
  assert.equal(state.trash.length, 0);
});

test("排序：成员顺序不符时拒绝", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], E.nowISO());
  const a = inspiration(state, "一");
  const b = inspiration(state, "二");
  E.assign(state, a.id, c.id, E.nowISO());
  E.assign(state, b.id, c.id, E.nowISO());
  assert.throws(() => E.reorderMembers(state, round.id, [a.id]), /顺序无效/);
  E.reorderMembers(state, round.id, [b.id, a.id]);
  assert.deepEqual(round.memberIds, [b.id, a.id]);
});

test("继续构思：从最近结束轮次复制成员且轮次号递增", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round1 = E.startRound(state, c.id, [], E.nowISO());
  const item = inspiration(state, "延续");
  E.assign(state, item.id, c.id, E.nowISO());
  E.endRound(state, round1.id, E.nowISO());

  const round2 = E.continueRound(state, c.id, E.nowISO());
  assert.equal(round2.roundNumber, 2);
  assert.ok(round2.memberIds.includes(item.id));
  assert.equal(item.collectionId, c.id);
});

test("过期回收站清理按 30 天执行", () => {
  const state = emptyState();
  const item = inspiration(state, "会过期");
  const old = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
  E.deleteInspiration(state, item.id, old);
  assert.equal(state.trash.length, 1);
  E.purgeExpiredTrash(state, E.nowISO());
  assert.equal(state.trash.length, 0);
});

test("小票统计口径正确", () => {
  const state = emptyState();
  const c = E.createCollection(state, "构思", E.nowISO());
  const round = E.startRound(state, c.id, [], new Date(1700000000000).toISOString());
  const item = inspiration(state, "四个字正好", new Date(1700000000005).toISOString());
  E.assign(state, item.id, c.id, new Date(1700000000010).toISOString());
  const receipt = E.endRound(state, round.id, new Date(1700000060010).toISOString());
  const stats = E.receiptStatistics(receipt.snapshot);
  assert.equal(stats.inspirationCount, 1);
  assert.equal(stats.finalTextCount, "四个字正好".length);
  assert.ok(stats.durationMs > 0);
  assert.equal(E.roundTitle(stats.roundNumber), "第 1 轮构思");
});

test("附件引用完整性：未引用资源才被清理", () => {
  const state = emptyState();
  const rid = E.newID();
  state.resources.push({
    id: rid,
    source: "importedAttachment",
    filename: "a.png",
    mimeType: "image/png",
    size: 10,
    createdAt: E.nowISO(),
  });
  const item = inspiration(state, "带附件", E.nowISO());
  item.resourceIds.push(rid);
  assert.equal(E.removeUnreferencedResources(state).length, 0);

  item.resourceIds = [];
  const removed = E.removeUnreferencedResources(state);
  assert.deepEqual(removed.map((r) => r.id), [rid]);
});


test("继续构思取回已移至其他活动集的成员，保留原顺序与旧小票", () => {
  const state = emptyState(), now = E.nowISO();
  const a = E.createCollection(state, "原构思集", now);
  const first = E.startRound(state, a.id, [], now);
  const one = inspiration(state, "成员一"), two = inspiration(state, "成员二");
  E.assign(state, one.id, a.id, now); E.assign(state, two.id, a.id, now);
  const receipt = E.endRound(state, first.id, now), snapshot = structuredClone(receipt.snapshot);
  const b = E.createCollection(state, "另一构思集", now), other = E.startRound(state, b.id, [], now);
  E.assign(state, one.id, b.id, now);
  const continued = E.continueRound(state, a.id, now);
  assert.deepEqual(continued.memberIds, [one.id, two.id]);
  assert.equal(continued.roundNumber, 2);
  assert.deepEqual(other.memberIds, []);
  assert.equal(other.events.at(-1).kind, "memberRemoved");
  assert.equal(one.collectionId, a.id);
  assert.equal(state.rounds.filter((round) => round.state === "thinking" && round.memberIds.includes(one.id)).length, 1);
  assert.deepEqual(receipt.snapshot, snapshot);
});
