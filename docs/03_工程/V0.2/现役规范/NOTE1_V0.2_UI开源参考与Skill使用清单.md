# NOTE1 V0.2 UI 开源参考与 Skill 使用清单

> 文档状态：现役开发参考  
> 建立日期：2026-08-02  
> 产品依据：`docs/01_产品/V0.2/NOTE1_PRD_V0.2.md`
> 视觉依据：`docs/02_设计/V0.2/NOTE1_V0.2_产品设计与交互规格.md`

## 0. 结论

GitHub 和现有 UI Skill 值得使用，但用途是减少开发猜测、复用成熟的 SwiftUI 实现判断和加强视觉验收，不是给 NOTE1 更换主题或堆叠第三方依赖。

本轮确定：

1. 开发前使用项目现有确认图和设计规格建立 NOTE1 自己的组件与变量；
2. Skill 负责设计审计、SwiftUI 模式、材质降级和模拟器验证；
3. GitHub 项目默认只读研究，任何包依赖都必须另行说明收益、风险并获得授权；
4. 不复制其他 App 的品牌、颜色和信息架构；
5. 不能用开源示例覆盖 V0.1 已成熟的编辑、附件、卡片位置恢复和手势能力。

## 1. 开发对话必须使用的 Skill

| Skill | 使用阶段 | 负责内容 | 不得做的事 |
| --- | --- | --- | --- |
| `product-design:audit` | 每批修改前后 | 确认图与同尺寸实现图并排审计；检查层级、间距、颜色、裁切和状态 | 自行生成新主题 |
| `product-design:ideate` | 尚无 A 级确认图的高风险页面 | 先给三套独立视觉方案，用户选定后才实现 | 把多个方案混成未确认稿直接开发 |
| `build-ios-apps:swiftui-ui-patterns` | 组件和页面骨架 | 原生 SwiftUI 导航、工具栏、Sheet、焦点、状态和可访问性 | 用网页式组件替代原生页面 |
| `build-ios-apps:swiftui-liquid-glass` | 顶部按钮、底栏、面板 | iOS 26 玻璃与 iOS 17–25 同源降级 | 把纯白高亮当成玻璃 |
| `build-ios-apps:ios-simulator-browser` | 每批自验 | 真实点击、滑动、键盘、截图、录屏和 UI 树检查 | 只看 Preview 或静态截图 |
| `impeccable:impeccable` | 阶段收口 | `critique / audit / polish / harden`，识别模板化卡片、嵌套容器、溢出和边界状态 | 作为 NOTE1 的设计权威 |
| `image-to-ui-skill` | 已有 A 级确认图时 | 测量确认图并约束尺寸、间距和视觉组件 | 根据图片猜业务行为 |

执行规则：

- 开发对话开始一个 UI 批次前，必须读取该批次对应 Skill；
- Skill 的建议与产品设计规格冲突时，以产品设计规格为准；
- 每个批次必须留下“目标图、实现图、差异结论、交互录屏”四类证据。

## 2. GitHub 与官方参考筛选

### 2.1 采用为工程研究参考

| 来源 | 对 NOTE1 的用途 | 使用级别 | 结论 |
| --- | --- | --- | --- |
| [Apple Human Interface Guidelines：Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) | 四个一级入口稳定存在、标签清楚、导航与动作分离 | 规范依据 | 采用；底栏负责导航，新增按钮保持独立 |
| [Apple Human Interface Guidelines：Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) | 顶部搜索入口、范围筛选和搜索状态 | 规范依据 | 采用；NOTE1 使用顶部按钮进入完整搜索 |
| [Apple Human Interface Guidelines：Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | 点击目标、Dynamic Type、VoiceOver、Reduce Motion | 验收依据 | 采用；不能为视觉紧凑牺牲命中区 |
| [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp) | 成熟 SwiftUI 信息流、完整编辑器、媒体和导航状态组织 | 源码研究 | 采用其页面拆分和状态组织思路，不复制 Mastodon UI |
| [danielsaidi/DeckKit](https://github.com/danielsaidi/DeckKit) | 卡片叠层、滑动、边缘滑动与自定义内容 | 手势研究 | 研究其状态机与 Demo；V0.2 默认不引入依赖 |
| [EmergeTools/Pow](https://github.com/EmergeTools/Pow) | 数值变化反馈、轻触觉和可复用过渡 | 动效研究 | 只选取克制的反馈思路；不使用粒子或夸张转场 |
| [exyte/AnimatedTabBar](https://github.com/exyte/AnimatedTabBar) | 底栏图标状态和可配置命中单元 | 反例兼参考 | 研究 API 和命中布局；不采用球形跳跃、凹槽和夸张轨迹 |
| [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | 识别 AI 常见模板味，执行 critique、polish、harden | 质量审计 | 采用审计方法；项目中已有 Skill，无需重复安装 |

### 2.2 只采用“文档方法”，不采用品牌设计包

[Meliwat/awesome-ios-design-md](https://github.com/Meliwat/awesome-ios-design-md) 提出的 `DESIGN.md` 分工值得保留：设计文档单独描述颜色、字体、组件状态、间距、动效、触觉和反例，开发规则由 `AGENTS.md` 与开发准则负责。

NOTE1 已用 `NOTE1_V0.2_产品设计与交互规格.md` 承担该职责，因此：

- 不再新增第二份重复的 `DESIGN.md`；
- 不导入任何其他 App 的逆向品牌包；
- 只借鉴“让设计规格可被开发代理直接读取”的文档治理方式。

### 2.3 明确拒绝作为直接实现依据

| 类型 | 拒绝原因 |
| --- | --- |
| Anthropic `frontend-design` 等 Web 前端风格 Skill | 可用于理解“避免通用 AI 外观”，但不是原生 iOS 实现规范 |
| 大型通用 UI Skill 合集 | 指令互相冲突，容易让开发代理自由换肤 |
| Tinder 风格卡片库 | 横向甩卡和 NOTE1 的纵向卡片流、左滑收起语义冲突 |
| 高动效底栏库 | 容易产生球形跳跃、凹槽、弹跳和抢注意力动画 |
| 直接复制 flomo、X、PikPak 或其他 App | NOTE1 只借鉴指定交互关系，不复制品牌和产品结构 |

## 3. 第三方依赖门禁

V0.2 UI 优化默认使用 SwiftUI、UIKit/Quick Look 和系统触觉完成，不新增第三方包。

如果某个批次认为必须引入依赖，开发对话需先提交一页决策说明：

1. 原生实现为什么无法满足；
2. 依赖解决的唯一问题；
3. 最低 iOS 17、Reduce Motion、VoiceOver 和长期维护风险；
4. 包体积、许可证、离线能力和替代方案；
5. 移除依赖的降级路径。

未获得用户明确同意前，不修改 `Package.swift`、Xcode Package Dependencies 或工程链接项。

## 4. 对当前 UI 优化的直接约束

- 顶部栏、底栏、浮动新增、圆形按钮先统一为项目组件，再逐页优化；
- 搜索优先恢复为顶部输入与紧邻筛选，不引入新的搜索导航结构；
- 卡片预览先恢复 V0.1 成熟能力，再调整纸张、留白和构思集面板；
- 构思集面板使用项目确认的 3 × 2 结构，自行实现连续拖拽命中；
- 小票册基于确认的票据夹、完整长票、左右换票和下拉抽取，不以通用 Deck 组件直接替代；
- 所有动效都要提供 Reduce Motion 版本，避免高亮闪白、过度弹跳和边缘大位移。
