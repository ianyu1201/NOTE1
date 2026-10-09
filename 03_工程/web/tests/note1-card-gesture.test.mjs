import test from "node:test";
import assert from "node:assert/strict";
import { cardGesture, adjacentCardIndex, cardWheel } from "../app/portfolio/note1/demo/card-gesture.ts";

test("上下切卡，左滑收起；右滑和短拖不写入", () => {
  assert.equal(cardGesture(8, -100), "next");
  assert.equal(cardGesture(8, 100), "previous");
  assert.equal(cardGesture(-120, 8), "tuck");
  assert.equal(cardGesture(100, 8), "cancel");
  assert.equal(cardGesture(-60, 2), "cancel");
  assert.equal(cardGesture(-90, -90), "cancel");
});

test("短距离快速甩动使用预测位移，轻触和反向滑动不收起", () => {
  assert.equal(cardGesture(0, -30, 0, -600), "next");
  assert.equal(cardGesture(-30, 0, -1000, 0), "tuck");
  assert.equal(cardGesture(-4, 0, -2000, 0), "cancel");
  assert.equal(cardGesture(40, 0, 1200, 0), "cancel");
});
test("滚轮归一化、惯性尾流与间歇后的下一次切卡", () => {
  const state = { total: 0, last: 0, consumed: false };
  assert.equal(cardWheel(state, 20, 0, 1000), 0);
  assert.equal(cardWheel(state, 30, 0, 1020), 1);
  assert.equal(cardWheel(state, 100, 0, 1100), 0);
  assert.equal(cardWheel(state, -3, 1, 1400), -1);
  assert.equal(cardWheel(state, 1, 2, 1700), 1);
});
test("首尾不循环且空卡流不产生负索引", () => {
  assert.equal(adjacentCardIndex(0, -1, 3), 0);
  assert.equal(adjacentCardIndex(2, 1, 3), 2);
  assert.equal(adjacentCardIndex(0, 1, 3), 1);
  assert.equal(adjacentCardIndex(0, 1, 0), 0);
});
