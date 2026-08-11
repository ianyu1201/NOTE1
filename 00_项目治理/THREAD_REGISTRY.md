# NOTE1 任务登记

> 更新日期：2026-08-11

| 标题 | 任务 ID | 职责 | 状态 | 工作目录 / 分支 | 来源与候选 | 必读入口 | 日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NOTE1｜V0.3｜01 产品与设计 | `019fe09c-5903-7293-bd06-37e5f915fca0` | S2→S3：冻结功能差量、功能交互、实现约束和运行验收合同；视觉基线与深入 UI/动画已隔离到 V0.4 | `completed`；S3 功能合同已确认；固定候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | `/Users/yusiyuan/Documents/NOTE1`；`codex/note1-v03-product-design` | 来源 `b403277d61335eaf1ea0c930faca338686624d8c`；阶段交付 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | `AGENTS.md`、`00_项目治理/PROJECT_BRIEF.md`、三份现役基线、`03_工程/evidence/V0.3/MANIFEST.md`、`03_工程/NOTE1_V0.3开发启动包.md` | 创建 2026-08-08；关闭 2026-08-11 |
| NOTE1｜V0.3｜03 独立功能验收 | `019fef64-7488-7a73-abdc-269ffad58764` | S6：独立复验固定候选，逐项给出合同结论、缺陷分级与接受建议；不批准版本 | `owner_terminated`；用户已归档删除；只留下部分原始证据，验收结论 `not_accepted` | `/Users/yusiyuan/Documents/NOTE1`；任务曾直接使用唯一项目目录 | 固定候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e`；部分证据提交 `634508463073563479cc58a6a1f6c7c61b594239` | `03_工程/evidence/V0.3/独立验收/2026-08-11_S6_35c4ca0/README.md` | 创建 2026-08-11；用户结束并归档删除 2026-08-11 |
| NOTE1｜V0.4｜01 视觉与交互设计 | `019fef8d-3ab6-7fe0-a374-ca2b7329ac72` | S2→S3：确认整体视觉身份、四页 UI、组件系统、动画交互、适配与 UI 运行验收合同；不开发业务代码 | `active`；等待启动复述确认；阶段交付 `pending` | `/Users/yusiyuan/Documents/NOTE1`；`codex/note1-v04-visual-design` | V0.4 起点 `c56a9ce`；V0.3 关闭点 `b92d2a7938ebf9bf6bca91cde91a6cb9ded60273`；功能来源 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | `AGENTS.md`、`00_项目治理/PROJECT_STATE.md`、三份稳定基线、ADR、V0.3 manifest 与视觉输入 | 创建 2026-08-11；关闭 `pending` |

## 创建门禁

- S3 功能交付合同已经确认；现有实现已形成，不为补视觉另建 V0.3 开发总控；
- V0.3 独立功能验收任务已由用户结束并归档删除，不再恢复；
- V0.4 当前只创建视觉与交互设计任务；S3 合同确认前不创建 UI 开发总控或独立验收任务；
- 独立验收通过不自动批准版本；版本批准必须单独记录。

## 当前边界

- 用户最新明确确认高于历史候选方案；候选图、当前代码和测试均不自动成为视觉基线；V0.3 只批准功能闭环，视觉/UI/深入动画进入 V0.4；
- 固定候选与已通过 85/85 XCTest 和 iOS 26.5 模拟器构建/启动的代码只有文档治理差异；这些结果不替代固定候选复验、真机、VoiceOver、真实连续手势、附件、分享、录音或 iOS 17–25；
- `/Users/yusiyuan/Documents/NOTE1` 是用户确认保留的唯一项目工作树；被取代的 148 项目录重组保存在 `codex/note1-original-layout-snapshot-20260811@86d7f0ae80546ba2ba3398beeec1d1d6ea05c38a`；
- 不删除安全分支或证据，直至完整治理/验收报告后获得单独授权。
- V0.3 未获独立验收或正式版本批准；它只作为 V0.4 的功能与非回归起点。
