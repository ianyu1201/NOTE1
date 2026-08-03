# NOTE1 iOS 工程入口

> 当前代码基线：`v0.3-product-start-20260803`

## 运行入口

- Xcode 工程：`App/App.xcodeproj`
- Scheme：`App`
- App 入口：`App/App/NOTE1App.swift`
- 当前一级外壳：`App/App/V02AppShellView.swift`
- 当前状态入口：`App/App/V02Store.swift`
- 领域模型与本机持久化：`App/App/ModelStore.swift`
- 自动化测试：`App/AppTests/`

## 当前架构

工程采用 SwiftUI + Store 驱动的单体原生架构，没有第三方状态管理依赖。`V02Store` 负责页面状态与业务编排，`ModelStore.swift` 保存领域模型、迁移兼容和本机数据能力，各 `V02*View` 负责界面呈现。

这套结构与轻量 MVVM 接近，但当前没有独立 ViewModel 层。治理时保持现有模式，不引入 TCA、Clean Architecture 或新的依赖。

## 文件职责

| 范围 | 主要文件 |
| --- | --- |
| App 外壳与一级页面 | `V02AppShellView.swift`、`V02InspirationViews.swift`、`V02CardPreviewViews.swift`、`V02CollectionViews.swift`、`V02ReceiptBookView.swift` |
| 卡片与小票交互 | `V02CardDeck.swift`、`V02ReceiptDeck.swift`、`V02ReceiptDetailView.swift`、`V02ReceiptGenerationView.swift`、`V02ReceiptPaper.swift` |
| 编辑、搜索与设置 | `V02EditingViews.swift`、`V02SearchView.swift`、`V02SettingsView.swift`、`V02TrashView.swift` |
| 附件、音频、导出与备份 | `V02CollectionAttachmentView.swift`、`V02AudioPlayback.swift`、`V02VoiceRecorder.swift`、`V02ReceiptExport*.swift`、`V02BackupService.swift` |
| 共用设计与系统能力 | `DesignSystem.swift`、`DynamicTypeSupport.swift`、`AppShortcutSupport.swift`、`SpeechTranscriptionService.swift` |
| V0.1 兼容实现 | 不带 `V02` 前缀的旧页面与交互文件；在非回归映射完成前不得按命名删除 |

## 治理边界

1. 当前全部 Swift 文件均属于 App 或 AppTests target，没有已确认的无引用源码。
2. V0.1 文件仍承担迁移、复用或非回归参考职责，不能仅因入口切到 V0.2 就删除。
3. 移动 Swift 文件必须同步 `project.pbxproj`，并完成构建与全部测试。
4. `xcuserdata`、DerivedData、`.DS_Store` 和临时截图不进入版本库。
5. V0.3 产品基准冻结前，不做大规模业务架构重写。
