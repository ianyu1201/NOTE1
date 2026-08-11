# NOTE1 V0.3 批量动作术语统一

> 日期：2026-08-11
> 状态：代码、源码扫描、模拟器构建与自动化已通过

## 范围

- 灵感页与搜索页共享“放回卡片流”“归入构思集”两项完整动作名称；
- 搜索页不再缩写为“放回”“归入”；
- 既有横向/纵向 `ViewThatFits`、44pt 命中高度、批量原子操作和容量规则不变。

## 结果

- 用户可见源码扫描未发现独立的 `Button("放回")` 或 `Menu("归入")`；
- iOS 26.5 `NOTE1 Evidence iPhone 15 Pro` 模拟器构建通过；
- 84 项 XCTest 全部通过，新增共享术语策略断言；
- XCTest 结果：`~/Library/Developer/XcodeBuildMCP/workspaces/NOTE1-5b048d27dcd5/result-bundles/test_sim_2026-08-11T02-05-57-531Z_pid29434_61e5f5c0.xcresult`。

## 证据边界

本批仅统一动作文字，不改变布局、材质、手势或动画，因此不新增截图。搜索选择态的窄屏最大辅助字号结构已有前批证据；真机 VoiceOver 焦点顺序仍按工程基线补证。
