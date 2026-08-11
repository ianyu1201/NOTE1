# NOTE1 项目状态

> 更新日期：2026-08-11
> 当前版本：V0.3（MINOR）
> 当前状态：`candidate_fixed`
> 唯一当前阶段：S6 独立功能验收准备

## 1. 项目与路径身份

| 字段 | 当前值 |
| --- | --- |
| `workspace_root` | `/Users/yusiyuan/Documents/NOTE1` |
| `active_version_root` | `/Users/yusiyuan/Documents/NOTE1` |
| `repo_root` | `/Users/yusiyuan/Documents/NOTE1` |
| `staging_root` | 未单独物化；用户于 2026-08-11 明确要求只保留一个项目文件夹，V0.3 活动候选在唯一主工作树中维护 |
| `archive_root` | 未物化独立代码归档；旧代码和文档由 `/Users/yusiyuan/Documents/NOTE1/.git` 的 Git 历史/标签保存，历史运行素材统一保存在 `03_工程/evidence/` |
| `git_common_dir` | `/Users/yusiyuan/Documents/NOTE1/.git` |
| 唯一工作树 | `/Users/yusiyuan/Documents/NOTE1`；隔离 worktree 已在完成接管和验证后注销 |
| 正式任务 ID | `019fe09c-5903-7293-bd06-37e5f915fca0` |

拓扑为“编号式单仓库生命周期 + 单一主工作树”。源码只有一份活跃路径；不建立永久并行的 V0.1/V0.2/V0.3 源码副本。被取代的原目录重组已保存到安全分支 `codex/note1-original-layout-snapshot-20260811@86d7f0ae80546ba2ba3398beeec1d1d6ea05c38a`，不再占用第二个项目文件夹。

仓库根目录按 Project Delivery Suite 的生命周期顺序固定为 `00_项目治理/`、`01_产品/`、`02_设计/`、`03_工程/`、`04_技术决策/`。活跃 iOS 工程保留技术栈名称 `03_工程/ios/`，运行材料收入 `03_工程/evidence/`。隐藏的 `.git/` 保存历史，不再额外复制一份“历史代码”目录。

## 2. 版本治理状态

| 字段 | 当前值 |
| --- | --- |
| `latest_observed` | `V0.3`，分支 `codex/note1-v03-product-design`；当前完整提交以该分支 `HEAD` 为准 |
| `current_approved` | `pending`；现有材料没有独立的版本批准记录，不把来源固定点推定为正式批准版本 |
| `active_candidate` | `V0.3`，分支 `codex/note1-v03-product-design`；固定功能验收候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` |
| `source_lineage` | `b403277d61335eaf1ea0c930faca338686624d8c` |
| `governance_cycle_id` | `NOTE1-V03-GOV-20260811-01` |
| `prd_status` | `scope_approved`；V0.3 功能闭环范围已确认，视觉基线和深入 UI/动画已隔离到 V0.4 |
| `delivery_contract_status` | `approved`；用户于 2026-08-11 明确确认 V0.3 功能合同与 V0.4 视觉延期边界 |
| `validation_status` | `locally_verified`；候选与此前 85/85 XCTest、iOS 26.5 模拟器构建/启动之间只有文档治理差异；不替代最终候选独立复验 |
| `acceptance_status` | `task_created_waiting_startup_confirmation`；独立功能验收任务 `019fef64-7488-7a73-abdc-269ffad58764` 已创建，尚无验收结论 |
| `version_approval_status` | `pending` |
| `archive_status` | `not_applicable`；正式版本批准前不归档或清理前序对象 |
| `anti_drift_status` | 三份现役基线采用稳定路径且已唯一化；V0.3 功能合同与 V0.4 视觉/动效输入已分离；开发证据不自动升级为视觉基线 |

## 3. 权威来源

1. 稳定项目定位：`00_项目治理/PROJECT_BRIEF.md`；
2. 产品、对象、范围和业务规则：`01_产品/NOTE1_PRD.md`；
3. 页面、状态、功能交互、适配和无障碍：`02_设计/NOTE1_产品设计与交互规格.md`；视觉基线在 V0.4 另行建立；
4. 工程约束、非回归和运行验收：`03_工程/NOTE1_开发与运行验收基线.md`；
5. 长期技术决定：`04_技术决策/`；
6. 证据批次和提交映射：`03_工程/evidence/V0.3/MANIFEST.md`。

现役产品决定以 PRD 第 8 节实际列项为准，不从编号连续性反推缺失决定；UI 实现合同由工程基线维护；实施过程由 Git 和各证据批次 README 保存。此前在本文件中的完整实施流水账及历史批次编号可从治理前固定点 `137005de23aa8a258bdaae237e9946f50dd0f38a` 追溯，不再与当前状态并列。

## 4. 已满足门禁

- 根目录、分支、来源固定点和唯一活动候选已经明确；
- 三份 V0.3 现役基线和四个 ADR 路径有效；
- 当前 worktree 在本治理开工时无未提交改动；
- 候选代码已形成完整离线功能闭环，85/85 XCTest 与 iOS 26.5 模拟器构建/启动通过；
- 当前没有已知未处置 P0/P1；用户已同意以现有功能为优化起点，但这不等于证明绝对没有 Bug。
- V0.3 功能差量、四页可观察功能结果、状态矩阵、手势边界、非回归和运行验收合同已由用户确认；视觉与深入动效已隔离到 V0.4；
- 固定功能验收候选为 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e`，启动包为 `03_工程/NOTE1_V0.3开发启动包.md`；

## 5. 未满足门禁

- V0.3 不冻结视觉基线；四页视觉身份、UI 质感与深入动效已延期到 V0.4，不再作为 V0.3 阻断项；
- 降低透明度同视口、真实手指连续拖拽、真机 VoiceOver、真实附件、第三方分享目的地、录音和 iOS 17–25 仍缺运行证据；
- 历史开发证据多数只可追溯到进入 Git 的提交，没有独立 build ID；最终验收必须在新的固定候选上批量重取；
- 独立功能验收任务已创建但尚未完成启动复述确认和实际复验；创建任务不等于验收通过；
- `current_approved` 仍待用户或版本责任人单独裁决。

## 6. 下一步

下一步由任务 `019fef64-7488-7a73-abdc-269ffad58764` 推进 S6 独立功能验收：先完成启动复述确认，再按 `03_工程/NOTE1_V0.3开发启动包.md` 在固定候选上逐项复验并形成 `pass/fail/pending/not-applicable` 结论。独立验收通过后仍需用户单独执行 V0.3 版本批准；版本批准前不创建 `v0.3.0` 标签，不归档、移动或删除前序历史材料。

## 7. 本轮知识治理状态

| 事实面 | 状态 | 依据或边界 |
| --- | --- | --- |
| 代码 | `candidate-fixed` | 固定功能验收候选为 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e`，本轮不修改业务代码 |
| 运行态 | `pending` | 85/85 XCTest 与 iOS 26.5 模拟器通过；最终候选真机和系统版本门禁未完成 |
| 文档 | `changed-and-verified` | 现役基线使用稳定文件名；仓库根入口收口为 `00→04` 编号式生命周期目录 |
| 规则 | `changed-and-verified` | `AGENTS.md` 的候选提交、自动化数字和证据边界已同步 |
| 记忆 | `out-of-scope` | Codex 宿主生成记忆未获授权写入，本轮只维护仓库内权威文件 |
| 工作区 | `verified-current` | `/Users/yusiyuan/Documents/NOTE1` 是唯一注册工作树；被取代布局只保留在安全 Git 分支中 |
