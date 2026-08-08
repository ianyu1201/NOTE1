# NOTE1 iOS 工程入口

> 当前代码治理分支：`codex/note1-current-folder-governance`
> 当前代码基线：`6aafa9b1198def7e08c63693c13d3b5accd8b9a4`
> 最近验证：2026-08-08，69 项 XCTest 全部通过，通用 iOS 构建和静态分析成功

## 运行入口

- Xcode 工程：`App/App.xcodeproj`
- Scheme：`App`
- App 入口：`App/App/NOTE1App.swift`
- 一级外壳：`App/App/V02AppShellView.swift`
- 状态管理：`App/App/V02Store.swift`
- 错误类型：`StoreError`（V02Store.swift，5 cases）
- 领域模型：`App/App/ModelStore.swift`（`V02DomainState` / `V02DomainEngine` 等）
- 自动化测试：`App/AppTests/`

## 当前架构

工程采用 SwiftUI + Store 驱动的单体原生架构，没有第三方状态管理依赖。`V02Store` 负责页面状态与业务编排，`V02DomainEngine`（`ModelStore.swift`）是纯函数事务引擎，各 `V02*View` 负责界面呈现。

### 错误分层

| 类型 | 位置 | 职责 |
|------|------|------|
| `StoreError` | V02Store.swift | 持久化 / 校验 / 附件大小（5 cases） |
| `V02DomainError` | ModelStore.swift | 业务规则（集合上限、灵感未找到等 11 cases） |

## 文件职责

| 范围 | 主要文件 |
| --- | --- |
| App 外壳与一级页面 | `V02AppShellView.swift`、`V02InspirationViews.swift`、`V02CardPreviewViews.swift`、`V02CollectionViews.swift`、`V02ReceiptBookView.swift` |
| 卡片与小票交互 | `V02CardDeck.swift`、`V02ReceiptDeck.swift`、`V02ReceiptDetailView.swift`、`V02ReceiptGenerationView.swift`、`V02ReceiptPaper.swift` |
| 编辑、搜索与设置 | `V02EditingViews.swift`、`V02SearchView.swift`、`V02SettingsView.swift`、`V02TrashView.swift` |
| 附件、音频、导出与备份 | `V02CollectionAttachmentView.swift`、`V02VoiceRecorder.swift`、`V02ReceiptExport*.swift`、`V02BackupService.swift`、`AttachmentImporter.swift` |
| 共用设计与系统能力 | `DesignSystem.swift`、`DynamicTypeSupport.swift`、`ReviewInteractionPolicies.swift` |
| 领域模型与引擎 | `V02Store.swift`（Store + StoreError）、`ModelStore.swift`（V02 领域类型与 V02DomainEngine） |
| 共享附件支持 | `AttachmentImporter.swift`、`AttachmentSupport.swift` |

## 治理边界

1. 当前活跃 Swift 文件均属 App 或 AppTests target。V0.1 页面、旧 `NoteStore` 和旧测试已从正式 target 移除，历史实现由 Git 标签保留。
2. 移动 Swift 文件必须同步 `project.pbxproj`，并完成构建与全部测试。
3. `xcuserdata`、DerivedData、`.DS_Store` 和临时截图不进入版本库。
4. V0.3 产品基准冻结前，不做大规模业务架构重写。
5. 当前自动化结果来自 iPhone 13 mini / iOS 26.5 模拟器，不替代真机 VoiceOver、最大辅助字号和 iOS 17–25 材质降级验收。
