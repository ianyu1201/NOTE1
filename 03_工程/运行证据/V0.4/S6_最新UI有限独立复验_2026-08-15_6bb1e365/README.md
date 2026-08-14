# NOTE1 V0.4 S6 最新 UI 有限独立复验

> 完成日期：2026-08-15（Asia/Shanghai）
>
> 固定代码候选：`6bb1e365c9cc52dacbd157310f052a8338b4755e`
>
> 候选父提交：`dde89d08db4545c265b44b1a125318178bf78434`
>
> 分支：`codex/note1-v04-ui-development`
>
> 有限复验结论：`accepted`
>
> 版本批准状态：`pending_evidence`

## 1. 身份、范围与代码未变声明

- 启动门禁通过：当前分支、完整候选 SHA、候选父提交均精确匹配，工作树干净。
- 候选相对父提交包含 9 个 App/测试文件、设计规格的一处授权单句调整，以及本批开发 README、两张静态图和两段录屏；`git diff --check` 通过。
- 业务差异只覆盖灵感首页行内快捷收起、小票索引图标语义、卡片预览连续画布和小票阅读连续画布；没有修改领域业务规则、数据结构、手势阈值、导航结构、底栏顺序或命中区。
- 设计规格只将 VoiceOver 首页句修正为“整行进入编辑且无行内快捷收起语义”，没有修改其他现役合同内容。
- 本轮未修改业务代码、测试、现役合同或旧证据；不重新展开 V0.4 全量验收，不批准版本。只新增本目录的独立复验证据。
- 开发证据仅作为输入；本报告中的结论来自独立 diff、测试、文件身份与视觉中间帧核对。

## 2. 自动化

环境：XcodeBuildMCP，`App.xcodeproj` / `App` / Debug / `NOTE1 Evidence iPhone 15 Pro` / iOS Simulator 26.5 / `CODE_SIGNING_ALLOWED=NO`。

| 项目 | 独立结果 | 证据 |
| --- | --- | --- |
| 本轮针对性测试 | **5/5 通过，0 失败，0 跳过**，10.7 秒；首轮通过、未复跑 | `test_sim_2026-08-14T17-15-27-379Z_pid52574_466a3e11.log`，SHA-256 `b7c1e8651d724f1f23187394c3b0067eea441a998365bf5fb0d492c7b2365c0e`；结果包 `test_sim_2026-08-14T17-15-27-379Z_pid52574_f7fd3062.xcresult` |
| 全量 AppTests | **93/93 通过，0 失败，0 跳过**，5.6 秒；仅运行一次 | `test_sim_2026-08-14T17-15-45-193Z_pid52574_ccf3554a.log`，SHA-256 `458721f0dc57b791ffd6ec6c2be527347dd9145a10b94147b21e4065001e7557`；结果包 `test_sim_2026-08-14T17-15-45-193Z_pid52574_a2e2829d.xcresult` |

原始日志与结果包由 XcodeBuildMCP 保存在 `/Users/yusiyuan/Library/Developer/XcodeBuildMCP/workspaces/NOTE1-42f4784ab39f/`，不复制进 Git。工具文件名使用 UTC 时间；本地完成日期为 2026-08-15。

针对性测试为：

1. `testV04ObjectTransitionsKeepOnlyObjectsOnPaperSurfaces`
2. `testV04InspirationHomeHasNoInlineTuckAndDomainTuckRemainsAvailable`
3. `testV04ReceiptObjectIndexesUseMiniatureReceiptSymbolOutsideSelection`
4. `testV04ReceiptSwitchTransitionKeepsCurrentAndTargetConnectedToDrag`
5. `testV04ReceiptTabUsesMiniatureReceiptSemanticSymbol`

## 3. 四项复验矩阵

| # | 复验项 | 结论 | 独立证据与边界 |
| --- | --- | --- | --- |
| 1 | 灵感首页无行内快捷收起，整行编辑；批量选择和领域收起/放回保留 | **pass** | `V02InspirationTimelineRow` 已移除普通态 `onTuck` 按钮和 44pt 左列；正文按钮扩展为整行宽度。长按仍由高优先级 0.5 秒手势进入批量选择，VoiceOver 保留“选择灵感”动作。针对性测试实际执行 `tuckAway`、`.tuckedAway`、`returnToCardFlow` 和 `.visible`。开发静态图 SHA 与候选一致，独立复核无收起图标或空白左列。真机 VoiceOver 行内语义与焦点仍为 `pending_evidence`。 |
| 2 | 小票对象索引统一 `receipt`；选择态保留 circle/checkmark | **pass** | `V04ReceiptSymbolPolicy` 将全部小票、根页空态、历史小票和历史空态统一为 `receipt`；普通索引分支使用该 policy，选择分支仍为 `circle` / `checkmark.circle.fill`。当前 App 源码未检出字符串 `"ticket"`。针对性测试与小票索引静态图共同支持，静态图 SHA 与候选一致。 |
| 3 | 卡片预览静止和纵向切换使用连续画布；对象外宿主透明 | **pass** | 显式表面策略为 `cardPageHost=.canvas`、`cardDragHost=.transparent`、`cardNeighbourHost=.transparent`、`cardObject=.notePaper`；页面、拖拽层、相邻宿主与纸面调用点已接线。差异未修改纵向切卡、左滑收起、归入入口或阈值实现。录屏 SHA 与候选一致；独立抽查 1/3/5/6/7/9/11/12 秒，5–7 秒关键中间帧未见横向硬色带、异色矩形底板或卡片外纸面，仍保持居中单卡和上下切换。 |
| 4 | 小票左右换票使用连续画布；当前/相邻页面宿主透明 | **pass** | 阅读器固定 `receiptReaderHost=.canvas`；共享阅读中的详情页使用 `receiptPageHost=.transparent`；只有 `receiptObject=.receiptPaper`。换票 transition、横向阈值、首尾与 Reduce Motion 计算未改变，既有 transition 测试通过。录屏 SHA 与候选一致；独立抽查 1/3/5/7/9/11/12 秒，5/7 秒关键双票中间帧的顶部、底部及两票之间均为连续画布，票纸只随小票对象移动；纵向阅读结构未改。 |

## 4. 开发媒体身份与独立核对

四份媒体均由候选 `6bb1e365…` 的 Git 树直接包含，文件哈希与开发索引完全一致：

| 文件 | SHA-256 | 独立使用 |
| --- | --- | --- |
| `01_灵感首页_最终静态.jpg` | `b879d2740a1c4c23c98a28d3dfb0b3cb8718ddcfa8a3b4b069a195a6466e72ce` | 核对普通行无快捷收起、无预留左列 |
| `02_小票索引_最终静态.jpg` | `829f275ab89e870ca7c79b644fe8ebe90ba3d480374b5356651a8b71654339f3` | 核对普通索引为直立小票语义 |
| `03_卡片预览_慢速上下拖拽.mp4` | `d26a998ea61c60d158521df1c4826de88e4cfc549af9887fa9e11038259c921f` | 13.107 秒；抽查静止、拖拽中间态和完成态 |
| `04_小票阅读_慢速左右换票.mp4` | `621438f9c4a84e35838b18d3057c9e318e84c71406267e8d794b35e9ad9d172e` | 12.990 秒；抽查静止、双票中间态和完成态 |

本轮只在 `/tmp` 使用系统媒体能力生成临时抽查帧，没有把派生帧加入仓库，也没有重取等价截图或录屏。

## 5. 合同一致性

结论：**pass**。

- PRD 6.1 与 `V04-PD-011`：首页不显示或预留快捷收起，整行进入完整编辑，收起/放回业务语义继续保留。
- 设计规格 5.1 与适配矩阵：不显示快捷收起或空列；VoiceOver 首页整行进入编辑且没有行内快捷收起语义。
- 工程基线 `UI-V04-002`：与上述首页结果及本轮测试/截图一致。
- PRD `V04-PD-016`、设计规格连续画布条款、工程基线 `UI-V04-003/005`：均要求对象外宿主使用连续 `canvas`，与表面 policy 和录屏中间帧一致。
- PRD `V04-PD-018`、设计规格小票索引条款、工程基线 `UI-V04-005/007`：均要求直立小票/`receipt` 语义，选择态允许系统选择图标，与实现一致。
- 三份现役合同未检出要求首页行内快捷收起的冲突现役句。

## 6. P0–P3 与 pending_evidence

### P0

无。

### P1

无。

### P2

无本轮新发现；未展开范围外问题。

### P3

无本轮新发现。

### pending_evidence（不等同缺陷）

- 真机 VoiceOver：整行编辑、批量选择等价动作及焦点顺序。
- iOS 17–25 的 Liquid Glass / SwiftUI 系统材质降级。
- 最大辅助字号、减少透明度、增强对比度、减少动态效果等完整辅助显示流程。
- 卡片上下切换、小票左右换票和纵向阅读的阻尼、惯性、速度与实际手感。

## 7. 结论与下一步建议

- 固定候选 `6bb1e365c9cc52dacbd157310f052a8338b4755e` 的本轮最新 UI 有限独立复验：**`accepted`**。
- 四项修订和合同一致性均通过；独立 5/5 针对性测试与 93/93 全量测试通过，未发现 P0–P3 新缺陷。
- 建议该候选进入用户实际体验确认，重点只确认卡片/小票切换及纵向阅读的阻尼、速度和视觉连续感。
- 正式版本状态仍为 **`pending_evidence`**；独立验收角色不批准版本，真机、旧系统和完整辅助设置证据关闭前不建议正式批准 V0.4。
