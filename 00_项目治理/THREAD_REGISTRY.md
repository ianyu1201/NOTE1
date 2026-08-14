# NOTE1 任务登记

> 更新日期：2026-08-14

| 标题 | 任务 ID | 职责 | 状态 | 工作目录 / 分支 | 来源与候选 | 必读入口 | 日期 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NOTE1｜V0.3｜01 产品与设计 | `019fe09c-5903-7293-bd06-37e5f915fca0` | S2→S3：冻结功能差量、功能交互、实现约束和运行验收合同；视觉基线与深入 UI/动画已隔离到 V0.4 | `completed`；S3 功能合同已确认；固定候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | `/Users/yusiyuan/Documents/NOTE1`；`codex/note1-v03-product-design` | 来源 `b403277d61335eaf1ea0c930faca338686624d8c`；阶段交付 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | 历史启动包 `90_历史归档/V0.3/NOTE1_V0.3开发启动包.md`、运行证据 `90_历史归档/V0.3/运行证据/MANIFEST.md` | 创建 2026-08-08；关闭 2026-08-11 |
| NOTE1｜V0.3｜03 独立功能验收 | `019fef64-7488-7a73-abdc-269ffad58764` | S6：独立复验固定候选，逐项给出合同结论、缺陷分级与接受建议；不批准版本 | `owner_terminated`；用户已归档删除；只留下部分原始证据，验收结论 `not_accepted` | `/Users/yusiyuan/Documents/NOTE1`；任务曾直接使用唯一项目目录 | 固定候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e`；部分证据提交 `634508463073563479cc58a6a1f6c7c61b594239` | `90_历史归档/V0.3/运行证据/独立验收/2026-08-11_S6_35c4ca0/README.md` | 创建 2026-08-11；用户结束并归档删除 2026-08-11 |
| NOTE1｜V0.4｜01 视觉与交互设计 | `019fef8d-3ab6-7fe0-a374-ca2b7329ac72` | S2→S3：确认整体视觉身份、四页 UI、组件系统、动画交互、适配与 UI 运行验收合同；不开发业务代码 | `completed / contracted`；S2 固定提交 `ea6ddbf7f0b85db567576e04e0f153557b2a47a6`，运行体验转入开发后验收 | `/Users/yusiyuan/Documents/NOTE1`；`codex/note1-v04-visual-design` | 治理权威起点 `71a97459695274493d700d9a27fdf7959041cbd4`；V0.3 关闭点 `b92d2a7938ebf9bf6bca91cde91a6cb9ded60273`；功能来源 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` | `AGENTS.md`、`00_项目治理/PROJECT_STATE.md`、三份稳定基线、ADR、`02_设计/视觉素材/` | 创建 2026-08-11；关闭 2026-08-14 |
| NOTE1｜V0.4｜02 UI 开发总控 | `019fffab-8669-76f0-b122-19fd9b1ff29c` | S4→S5：实现已冻结四页 UI、组件、小票、容量差量、动效和无障碍；形成可独立验收候选 | `active / building`；先只读复述，登记提交完成后解除门禁 | `/Users/yusiyuan/Documents/NOTE1`；`codex/note1-v04-ui-development` | S2 固定起点 `ea6ddbf7f0b85db567576e04e0f153557b2a47a6`；`semantic_coverage_passed` | `AGENTS.md`、`README.md`、`PROJECT_BRIEF.md`、`PROJECT_STATE.md`、三份现役基线、ADR、`02_设计/视觉素材/` | 创建 2026-08-14；关闭 `pending` |

## 创建门禁

- S3 功能交付合同已经确认；现有实现已形成，不为补视觉另建 V0.3 开发总控；
- V0.3 独立功能验收任务已由用户结束并归档删除，不再恢复；
- V0.4 UI 开发总控已在用户明确授权后创建；独立验收任务只在固定开发候选、开发报告和证据索引形成后创建；
- 独立验收通过不自动批准版本；版本批准必须单独记录。

## 当前边界

- 用户最新明确确认高于历史候选方案；候选图、当前代码和测试均不自动成为视觉基线；V0.3 只批准功能闭环，视觉/UI/深入动画进入 V0.4；
- 固定候选与已通过 85/85 XCTest 和 iOS 26.5 模拟器构建/启动的代码只有文档治理差异；这些结果不替代固定候选复验、真机、VoiceOver、真实连续手势、附件、分享、录音或 iOS 17–25；
- `/Users/yusiyuan/Documents/NOTE1` 是用户确认保留的唯一项目工作树；被取代的 148 项目录重组保存在 `codex/note1-original-layout-snapshot-20260811@86d7f0ae80546ba2ba3398beeec1d1d6ea05c38a`；
- 不删除安全分支或证据，直至完整治理/验收报告后获得单独授权。
- V0.3 未获独立验收或正式版本批准；它只作为 V0.4 的功能与非回归起点。
