# NOTE1 · iOS 与 Web 源码

NOTE1 是一个低压力、完全在本机运行的原生 iOS 灵感记录 App。产品主张是“简单记，快速看”。

原生端使用 SwiftUI，最低 iOS 17，不包含 WebView、后端、登录、云同步或 AI。正式原生代码使用 V0.2 领域模型与 `V02*` 页面；V0.1 通过 Git 标签保留历史事实，不参与当前 target 编译。

本仓库同时提供独立的 React Web 演示版，源码位于 `03_工程/web/`。两端分别在设备或浏览器本机保存数据，没有跨端同步，也不承诺备份格式互通。Web 演示不改变原生产品的技术与视觉合同。

## 快速运行 Web 版

需要 Node.js 22.13 或更新版本：

```bash
cd 03_工程/web
npm ci
npm run dev
```

打开终端输出的本机地址。构建与单元测试：

```bash
npm run build
npm test
```

完整目录、浏览器端测试步骤和限制见 [Web README](03_工程/web/README.md)。公开源码不等于发布线上网站。

## 当前状态

- V0.1 历史封存：`v0.1.0`
- V0.4 UI 开发分支：`codex/note1-v04-ui-development`
- V0.3 历史产品探索标签：`v0.3-product-start-20260803`
- V0.4 当前状态入口：`00_项目治理/PROJECT_STATE.md`

V0.3 功能范围与合同曾获确认，但用户选择结束独立验收并直接进入 V0.4，因此 V0.3 不标记为独立验收通过或正式批准。V0.4 从功能候选 `35c4ca0208f98aab5be9e99c3b5cac5f8007377e` 和已保存的部分运行证据起步；四页 UI、视觉身份、组件、小票范围和无固定构思集容量已经确认，动效手感与适配/无障碍转为开发后运行验收。路径、提交和门禁以 `00_项目治理/PROJECT_STATE.md` 为准。

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
├── 03_工程/                     # 现役实现、测试与验收合同
│   ├── NOTE1_开发与运行验收基线.md
│   ├── ios/                        # 原生 iOS 工程和 XCTest
│   └── web/                        # 独立 Web 演示、领域测试与浏览器测试
├── 04_技术决策/                 # 已接受 ADR
└── 90_历史归档/                 # 已关闭版本的运行证据与历史材料
    ├── V0.1/运行证据/
    ├── V0.2/运行证据/
    └── V0.3/运行证据/
```

## 产品与开发依据

按以下优先级阅读：

1. `AGENTS.md`
2. `01_产品/NOTE1_PRD.md`
3. `02_设计/NOTE1_产品设计与交互规格.md`
4. `03_工程/NOTE1_开发与运行验收基线.md`
5. 适用的 `04_技术决策/` ADR

V0.1–V0.3 历史代码和文档由 Git、ADR 与 `90_历史归档/` 中已登记材料保留，不再作为现役开发指令。代码说明当前实现事实，不自动覆盖 V0.4 PRD。

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
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行测试：

```bash
xcodebuild \
  -project "03_工程/ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 当前验证边界

2026-10-09 已对本次公开的业务源码执行本地双端回归：

- 原生：iOS 27.0 模拟器下，93 项单元测试和 5 条 UI 流程通过；另完成 iPhone 13 mini 最大辅助字号检查。
- Web：26 项单元测试和 45 个业务、边界与故障检查通过。
- 以上为开发验证，不代表独立验收、V0.4 正式批准或全部运行警告消失。UI 测试使用专用测试宿主；上述 Xcode 命令运行仓库自带的 93 项单元测试。

真机录音、VoiceOver、旧版 iOS、原生系统文件实际保存后恢复的完整 UI 链及最终分享投递仍未验证。AVAudioSession 主线程调用警告仍需音频专项核验。视觉与动效手感继续按现役合同由用户确认。

公开发布内容与验证说明见 [公开发布说明](03_工程/公开发布说明.md)。既有历史证据只证明各自对应的旧批次，不自动外推至本次代码。

## V0.4 工作方式

V0.4 在单一 PRD、设计规格和工程合同中维护整体视觉身份、四页 UI、组件系统、状态、动画与无障碍降级。现役文件继续使用稳定路径，不建立 `V0.4/` 平行文档目录，也不从当前代码反推最终视觉。

V0.4 S2 产品设计与 S3 交付合同已经冻结，用户于 2026-08-14 明确授权进入 S4→S5 UI 开发。合同内缺陷留在开发阶段修复，动效与适配按运行验收清单调优；只有需要改变已确认产品规则或 UI 结果时，才暂停相关实现并局部返回 S2 裁决。
