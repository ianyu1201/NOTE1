# NOTE1 iOS App

NOTE1 是一个低压力、完全在本机运行的原生 iOS 灵感记录 App。

当前工程使用 SwiftUI，不包含浏览器版本、PWA、WebView、后端、登录、云同步、
AI 或备份。

## 当前产品闭环

```text
快速记录 → 最近灵感续写 → 卡片回看 → 专注编辑
→ 加入灵感组 → 完成 → 历史查询 → 恢复或删除
```

卡片回看采用：

- 上下滑动：切换上一条或下一条
- 左右滑动：完成当前想法或灵感组
- 点按卡片：进入编辑或灵感组
- 点按 / 向上拖动底部灵感组按钮：归入现有组或新建组

## 项目结构

```text
NOTE1/
├── AGENTS.md
├── README.md
├── docs/
│   ├── 产品文档/
│   │   └── NOTE1_PRD_V2.6.md
│   ├── 技术决策/
│   │   └── ADR-001-本机数据损坏保护.md
│   └── 推广资料/
│       ├── NOTE1_公众号文章.md
│       └── NOTE1_抖音口播稿.md
├── ios/App/
│   ├── App.xcodeproj
│   ├── App/
│   └── AppTests/
├── media/demo/
│   ├── 01-home.png
│   ├── 02-review.png
│   ├── 03-editor.png
│   ├── 04-group.png
│   ├── 05-history.png
│   └── 06-group-picker.png
└── 可删除文件/（本机清理候选，不进入 Git）
```

## 产品与开发依据

- `docs/产品文档/NOTE1_PRD_V2.6.md`：当前唯一 PRD 和产品基线。
- `docs/技术决策/`：记录需要长期保持一致的重要技术选择及原因。
- `docs/推广资料/`：公众号文章与抖音口播稿，不参与产品需求裁决。
- `ios/App/App/`：当前真实功能、UI 和交互实现。
- `ios/App/AppTests/`：数据规则、持久化保护、选择范围与手势判定自动化测试。
- `media/demo/`：从当前模拟器运行态生成的公众号演示图。

旧 UI 参考图、设计对比图、启动验证中间物和未使用占位素材统一放在
`可删除文件/`。该目录仅供用户本机复核和删除，不进入 Git，也不参与开发或验收。

## Xcode 运行

工程路径：

```text
ios/App/App.xcodeproj
```

打开工程：

```bash
cd "/Users/yusiyuan/Documents/NOTE1"
open "ios/App/App.xcodeproj"
```

打开后选择 `App` Scheme 和目标模拟器或自己的 iPhone，点击运行。

命令行构建模拟器版本：

```bash
cd "/Users/yusiyuan/Documents/NOTE1"
xcodebuild \
  -project "ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

运行测试：

```bash
cd "/Users/yusiyuan/Documents/NOTE1"
xcodebuild \
  -project "ios/App/App.xcodeproj" \
  -scheme "App" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 当前验证

- 平台：iPhone 17 Pro 模拟器，iOS 26.5
- 构建：成功，0 个错误，0 个警告
- XCTest：22 项通过，0 项失败，0 项跳过
- 演示图：1206×2622 PNG，来自当前 App 真实运行态

真机运行由用户使用 Personal Team 测试开发者身份完成。免费 Personal Team 只适合
个人设备测试，不用于 App Store 或 TestFlight 分发。
