# NOTE1 iOS App

NOTE1 是一个低压力、完全在本机运行的原生 iOS 灵感记录 App。产品主张是“简单记，快速看”。

当前工程使用原生 SwiftUI，最低 iOS 17，不包含浏览器版本、PWA、WebView、后端、登录、云同步或 AI。正式代码路径已收敛到 V0.2 领域模型与 `V02*` 页面；V0.1 通过 Git 标签保留历史事实，不再参与当前 target 编译。

## 当前状态

- V0.1 历史封存：`v0.1.0`
- V0.3 产品与设计分支：`codex/note1-v03-product-design`
- V0.3 历史产品探索标签：`v0.3-product-start-20260803`
- V0.3 唯一文档入口：`docs/README.md`

固定提交已形成可运行的功能闭环和自动化基础，当前正在定义 V0.3 产品、设计与运行合同；模拟器证据不替代真机 VoiceOver、附件样本和旧系统材质验收。

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
├── docs/
│   ├── 00_项目治理/                # 项目状态、任务登记和目录规则
│   ├── 01_产品/V0.3/               # 唯一现役完整 PRD
│   ├── 02_设计/V0.3/               # 唯一现役设计与交互规格
│   ├── 03_工程/V0.3/               # 唯一现役工程与运行验收基线
│   └── 04_技术决策/                # ADR
├── evidence/                       # 运行截图、录屏与开发参考
├── ios/App/
│   ├── App.xcodeproj
│   ├── App/                        # SwiftUI 源码
│   └── AppTests/                   # XCTest
└── media/demo/                     # V0.1 历史真实运行证据
```

## 产品与开发依据

按以下优先级阅读：

1. `AGENTS.md`
2. `docs/01_产品/V0.3/NOTE1_PRD_V0.3.md`
3. `docs/02_设计/V0.3/NOTE1_V0.3产品设计与交互规格.md`
4. `docs/03_工程/V0.3/NOTE1_V0.3开发与运行验收基线.md`
5. 适用的 `docs/04_技术决策/` ADR

V0.1/V0.2 历史事实由 Git、ADR、`media/` 和 `evidence/` 保留，不再作为现役开发指令。代码说明当前实现事实，不自动覆盖 V0.3 PRD。

## 当前代码入口

- App：`ios/App/App/NOTE1App.swift`
- 一级外壳：`ios/App/App/V02AppShellView.swift`
- 设计系统：`ios/App/App/DesignSystem.swift`
- 领域与持久化：`ios/App/App/V02Store.swift`、`ios/App/App/ModelStore.swift`
- 共享附件能力：`ios/App/App/AttachmentImporter.swift`、`ios/App/App/AttachmentSupport.swift`
- 四个核心页面：`V02InspirationViews.swift`、`V02CardPreviewViews.swift`、`V02CollectionViews.swift`、`V02ReceiptBookView.swift`
- 测试：`ios/App/AppTests/`

V0.1 旧实现已经完成能力映射和 target 清理；历史源码保留在 `v0.1.0` 标签和 Git 历史中，当前 App 只编译 V0.2 活跃代码。

## Xcode 运行

工程路径：

```text
ios/App/App.xcodeproj
```

打开工程：

```bash
open "ios/App/App.xcodeproj"
```

模拟器构建：

```bash
xcodebuild \
  -project "ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行测试：

```bash
xcodebuild \
  -project "ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 当前验证边界

2026-08-08 在当前代码治理结果上独立运行 69 项 XCTest，通过 69、失败 0；通用 iOS 构建和静态分析均成功。历史提交的 86 项或 100 项结果只对应清理前测试集合。自动化结果不替代：

- 真机完整闭环；
- VoiceOver 真实语音导航；
- 最大辅助字号；
- 中文输入与权限；
- iOS 17–25 材质降级；
- 文件提供器和最终分享投递；
- 大附件备份恢复与失败回滚。

## V0.3 工作方式

V0.3 产品会话先完整理解仓库，与用户冻结产品方案、视觉和交互，再产出完整开发基准。独立开发会话可调用多个子智能体实施、测试和收集证据，最终将 App 与报告返回产品会话验收。

在 V0.3 产品基准冻结前，不进行大范围业务代码修改。
