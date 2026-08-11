# NOTE1 项目状态

> 更新日期：2026-08-11
> 当前版本：V0.4（MINOR）
> 当前状态：`defining`
> 唯一当前阶段：S2 视觉与交互设计

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
| 当前正式任务 ID | `019fef8d-3ab6-7fe0-a374-ca2b7329ac72`（NOTE1｜V0.4｜01 视觉与交互设计） |

拓扑为“编号式单仓库生命周期 + 单一主工作树”。源码只有一份活跃路径；不建立永久并行的 V0.1/V0.2/V0.3 源码副本。被取代的原目录重组已保存到安全分支 `codex/note1-original-layout-snapshot-20260811@86d7f0ae80546ba2ba3398beeec1d1d6ea05c38a`，不再占用第二个项目文件夹。

仓库根目录按 Project Delivery Suite 的生命周期顺序固定为 `00_项目治理/`、`01_产品/`、`02_设计/`、`03_工程/`、`04_技术决策/`。活跃 iOS 工程保留技术栈名称 `03_工程/ios/`，运行材料收入 `03_工程/evidence/`。隐藏的 `.git/` 保存历史，不再额外复制一份“历史代码”目录。

## 2. 版本治理状态

| 字段 | 当前值 |
| --- | --- |
| `latest_observed` | `V0.4`，分支 `codex/note1-v04-visual-design`；当前完整提交以该分支 `HEAD` 为准 |
| `current_approved` | `pending`；现有材料没有独立的版本批准记录，不把来源固定点推定为正式批准版本 |
| `active_candidate` | `V0.4`，分支 `codex/note1-v04-visual-design`；尚处 S2，不存在已批准视觉或实现候选 |
| `source_lineage` | V0.3 关闭点 `b92d2a7938ebf9bf6bca91cde91a6cb9ded60273`；功能候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` |
| `governance_cycle_id` | `NOTE1-V04-GOV-20260811-01` |
| `prd_status` | `defining`；稳定 PRD 文件仍保存 V0.3 功能基线，待 V0.4 用户确认后就地更新 |
| `delivery_contract_status` | `not_started`；V0.4 UI 实现与运行验收合同尚未形成 |
| `validation_status` | `not_started`；V0.3 证据只作为非回归输入 |
| `acceptance_status` | `not_applicable_at_S2` |
| `version_approval_status` | `not_started` |
| `archive_status` | `deferred`；V0.3 未获版本批准，不执行前序归档或删除 |
| `anti_drift_status` | 单一稳定文档路径继续使用；V0.3 功能事实、V0.4 视觉输入和真实运行证据保持身份分离 |

## 3. 权威来源

1. 稳定项目定位与当前阶段：`00_项目治理/PROJECT_BRIEF.md`、本文件；
2. V0.3 功能来源基线与待更新的 V0.4 产品入口：`01_产品/NOTE1_PRD.md`；
3. V0.3 功能交互来源与待建立的 V0.4 视觉基线：`02_设计/NOTE1_产品设计与交互规格.md`；
4. 工程约束、非回归和运行验收：`03_工程/NOTE1_开发与运行验收基线.md`；
5. 长期技术决定：`04_技术决策/`；
6. 证据批次和提交映射：`03_工程/evidence/V0.3/MANIFEST.md`。

现役产品决定以 PRD 第 8 节实际列项为准，不从编号连续性反推缺失决定；UI 实现合同由工程基线维护；实施过程由 Git 和各证据批次 README 保存。此前在本文件中的完整实施流水账及历史批次编号可从治理前固定点 `137005de23aa8a258bdaae237e9946f50dd0f38a` 追溯，不再与当前状态并列。

## 4. 已满足门禁

- 根目录、V0.4 分支、V0.3 关闭点和功能来源候选已经明确；
- 三份 V0.3 现役基线和四个 ADR 路径有效；
- 当前 worktree 在本治理开工时无未提交改动；
- 候选代码已形成完整离线功能闭环，85/85 XCTest 与 iOS 26.5 模拟器构建/启动通过；
- 当前没有已知未处置 P0/P1；用户已同意以现有功能为优化起点，但这不等于证明绝对没有 Bug。
- V0.3 功能候选、85/85 自动化基线与中止前部分运行证据已保存，可供 V0.4 做非回归；
- 用户已明确要求结束 V0.3 并进入 V0.4 UI 与动画优化。

## 5. 未满足门禁

- V0.4 的视觉原则、组件语言、四页确认稿、动画层级和减少动态效果方案尚未由用户确认；
- V0.4 PRD 差量、设计状态矩阵、UI 实现约束和运行证据矩阵尚未冻结；
- V0.3 未覆盖的 AC-07、AC-10、AC-11、真机 VoiceOver、系统版本与真实系统入口继续是非回归风险；
- S3 冻结前不授权修改 `03_工程/ios/` 业务代码。

## 6. 下一步

由任务 `019fef8d-3ab6-7fe0-a374-ca2b7329ac72` 推进 `NOTE1｜V0.4｜01 视觉与交互设计`：先查看当前模拟器和 V0.4 视觉输入，与用户逐项确认整体身份、四页 UI、组件和动画边界；确认结果就地写回三份稳定基线。S3 冻结前不开发。

## 7. 本轮知识治理状态

| 事实面 | 状态 | 依据或边界 |
| --- | --- | --- |
| 代码 | `source-fixed / no-v0.4-change` | V0.4 尚未修改业务代码；V0.3 功能候选为来源基线 |
| 运行态 | `source-evidence-only` | 85/85 XCTest、iOS 26.5 模拟器及中止前部分运行取证只作为 V0.4 非回归输入 |
| 文档 | `changed-and-verified` | 现役基线使用稳定文件名；仓库根入口收口为 `00→04` 编号式生命周期目录 |
| 规则 | `changed-and-verified` | `AGENTS.md` 的候选提交、自动化数字和证据边界已同步 |
| 记忆 | `out-of-scope` | Codex 宿主生成记忆未获授权写入，本轮只维护仓库内权威文件 |
| 工作区 | `verified-current` | `/Users/yusiyuan/Documents/NOTE1` 是唯一注册工作树；被取代布局只保留在安全 Git 分支中 |
