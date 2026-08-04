# NOTE1 iOS App

NOTE1 是一个低压力、完全在本机运行的原生 iOS 灵感记录 App。产品主张是“简单记，快速看”。

当前工程使用原生 SwiftUI，最低 iOS 17，不包含浏览器版本、PWA、WebView、后端、登录、云同步或 AI。

## 当前状态

- V0.1 历史封存：`v0.1.0`
- V0.2 当前正式目录治理分支：`codex/note1-current-folder-governance@ddb5e8c`
- V0.3 产品阶段封存入口：`v0.3-product-start-20260803`
- V0.3 交接入口：`docs/00_项目治理/NOTE1_V0.3产品会话交接与启动说明.md`

V0.2 已形成可运行的功能闭环和自动化基础，当前正在进行 V0.3 前的 UI/非回归收口；模拟器证据不替代真机 VoiceOver、附件样本和旧系统材质验收。

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
│   ├── 00_项目治理/                # 会话入口、交接和目录规则
│   ├── 01_产品/                    # 按版本保存 PRD 与产品方向
│   ├── 02_设计/                    # 设计规格、视觉基线与候选图
│   ├── 03_工程/                    # 现役规范、ISSUE 与源码风险
│   ├── 04_技术决策/                # ADR
│   └── 90_历史归档/                # 已完成任务单和历史审计
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
2. `docs/01_产品/V0.2/NOTE1_PRD_V0.2.md`
3. `docs/02_设计/V0.2/NOTE1_V0.2_产品设计与交互规格.md`
4. `docs/03_工程/V0.2/现役规范/NOTE1_V0.1到V0.2能力非回归矩阵.md`
5. `docs/01_产品/V0.1/NOTE1_PRD_V2.6.md`
6. `docs/03_工程/V0.2/现役规范/NOTE1_V0.2_UI优化ISSUE.md`
7. `docs/00_项目治理/NOTE1_V0.3产品会话交接与启动说明.md`

代码说明当前实现事实，不自动覆盖产品文档。候选图和外部参考不等于确认稿。

## 当前代码入口

- App：`ios/App/App/NOTE1App.swift`
- 一级外壳：`ios/App/App/V02AppShellView.swift`
- 设计系统：`ios/App/App/DesignSystem.swift`
- 领域与持久化：`ios/App/App/V02Store.swift`、`ios/App/App/ModelStore.swift`
- 四个核心页面：`V02InspirationViews.swift`、`V02CardPreviewViews.swift`、`V02CollectionViews.swift`、`V02ReceiptBookView.swift`
- 测试：`ios/App/AppTests/`

V0.1 与 V0.2 文件目前同时存在。未经能力映射、测试和用户授权，不得删除旧实现。

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

2026-08-04 在 `7962b30` 上独立运行 97 项 XCTest，通过 97、失败 0；通用 iOS 构建和静态分析均成功。该结果不替代：

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
