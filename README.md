# NOTE1 iOS App

NOTE1 是一个低压力、完全在本机运行的原生 iOS 灵感记录 App。产品主张是“简单记，快速看”。

当前工程使用原生 SwiftUI，最低 iOS 17，不包含浏览器版本、PWA、WebView、后端、登录、云同步或 AI。正式代码路径已收敛到 V0.2 领域模型与 `V02*` 页面；V0.1 通过 Git 标签保留历史事实，不再参与当前 target 编译。

## 当前状态

- V0.1 历史封存：`v0.1.0`
- V0.3 产品与设计分支：`codex/note1-v03-product-design`
- V0.3 历史产品探索标签：`v0.3-product-start-20260803`
- V0.3 状态入口：`00_项目治理/PROJECT_STATE.md`

当前活动实现候选已形成可运行的功能闭环，正在继续收口 V0.3 产品、设计与运行合同。当前路径、提交和门禁以 `00_项目治理/PROJECT_STATE.md` 为准；模拟器证据不替代真机 VoiceOver、附件样本和旧系统材质验收。

## 当前产品闭环

```text
记录灵感
→ 灵感时间流
→ 卡片预览
→ 收起或归入构思集
→ 在构思集继续构思
→ 结束本轮构思
→ 生成构思小票
→ 在小票册浏览、导出或分享
```

四个一级页面固定为：

```text
灵感｜卡片预览｜构思集｜小票册
```

## 项目结构

```text
NOTE1/
├── AGENTS.md                       # 全局项目规则、术语和开发约束
├── README.md                       # 当前仓库入口
├── 00_项目治理/                 # 项目状态、任务登记与交接
├── 01_产品/                     # 唯一现役 PRD
├── 02_设计/                     # 唯一现役设计与交互规格
├── 03_工程/                     # 现役实现、测试、验收合同与运行材料
│   ├── NOTE1_开发与运行验收基线.md
│   ├── ios/                        # 原生 iOS 工程和 XCTest
│   └── evidence/                   # 按版本登记的运行与视觉材料
└── 04_技术决策/                 # 已接受 ADR
```

## 产品与开发依据

按以下优先级阅读：

1. `AGENTS.md`
2. `01_产品/NOTE1_PRD.md`
3. `02_设计/NOTE1_产品设计与交互规格.md`
4. `03_工程/NOTE1_开发与运行验收基线.md`
5. 适用的 `04_技术决策/` ADR

V0.1/V0.2 历史代码和文档由 Git、ADR 保留，历史运行事实由 `03_工程/evidence/` 保留，不再作为现役开发指令。代码说明当前实现事实，不自动覆盖 V0.3 PRD。

## 当前代码入口

- App：`03_工程/ios/App/App/NOTE1App.swift`
- 一级外壳：`03_工程/ios/App/App/V02AppShellView.swift`
- 设计系统：`03_工程/ios/App/App/DesignSystem.swift`
- 领域与持久化：`03_工程/ios/App/App/V02Store.swift`、`03_工程/ios/App/App/ModelStore.swift`
- 共享附件能力：`03_工程/ios/App/App/AttachmentImporter.swift`、`03_工程/ios/App/App/AttachmentSupport.swift`
- 四个核心页面：`V02InspirationViews.swift`、`V02CardPreviewViews.swift`、`V02CollectionViews.swift`、`V02ReceiptBookView.swift`
- 测试：`03_工程/ios/App/AppTests/`

V0.1 旧实现已经完成能力映射和 target 清理；历史源码保留在 `v0.1.0` 标签和 Git 历史中，当前 App 只编译 V0.2 活跃代码。

## Xcode 运行

工程路径：

```text
03_工程/ios/App/App.xcodeproj
```

打开工程：

```bash
open "03_工程/ios/App/App.xcodeproj"
```

模拟器构建：

```bash
xcodebuild \
  -project "03_工程/ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行测试：

```bash
xcodebuild \
  -project "03_工程/ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 当前验证边界

2026-08-11 在活动实现候选 `137005de23aa8a258bdaae237e9946f50dd0f38a` 上运行 85 项 XCTest，通过 85、失败 0；iOS 26.5 模拟器构建和启动成功。固定起点的 69 项及历史 86/100 项结果只对应各自旧测试集合。自动化结果不替代：

- 真机完整闭环；
- VoiceOver 真实语音导航；
- 最大辅助字号；
- 中文输入与权限；
- iOS 17–25 材质降级；
- 文件提供器和最终分享投递；
- 大附件备份恢复与失败回滚。

## V0.3 工作方式

V0.3 当前任务负责与用户冻结产品方案、视觉、交互和运行合同，同时维护已经获得明确授权的实现候选。现役事实写入三份 V0.3 基线、项目状态和证据 manifest，不依赖旧聊天摘要。

在 S3 冻结前，不创建开发总控或独立验收任务，不扩展未写入 PRD 的业务范围，也不把候选实现宣称为正式批准版本。
