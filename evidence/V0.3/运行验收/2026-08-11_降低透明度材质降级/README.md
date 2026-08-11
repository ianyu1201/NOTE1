# NOTE1 V0.3 降低透明度材质降级证据索引

> 日期：2026-08-11
> 状态：代码与策略层完成；系统设置运行同视口尚未关闭

## 本批范围

- `GlassSurface`、`V02GlassIconLabel` 和 `V02GlassTextButton` 统一读取 `accessibilityReduceTransparency`；
- 开启降低透明度时使用不透明 `NoteTheme.paper`、50% `NoteTheme.ink` 边界和克制阴影；该边界与纸面按现役 RGB 令牌计算对比约 3.34:1；关闭时保留现役 iOS 26 玻璃或 iOS 17–25 系统材质降级；
- 页面几何、48pt 命中区、46pt 可见圆形按钮、文案与业务动作不变；
- 删除没有现役调用方的 `SharedTopBar` 与 `RoundGlassButton`，避免后续绕过共享组件重新产生顶部漂移。

## 自动化证据

| 项目 | 结果 |
| --- | --- |
| iOS 26.5 `NOTE1 Evidence iPhone 15 Pro` 构建并启动 | 通过 |
| XCTest | 82/82 通过，新增 `testV03GlassSurfacesUseOpaqueAccessibleFallback` |
| Impeccable 检测 | `[]`，无告警 |
| `git diff --check` | 通过 |

测试结果：`~/Library/Developer/XcodeBuildMCP/workspaces/NOTE1-5b048d27dcd5/result-bundles/test_sim_2026-08-11T01-44-10-936Z_pid29434_7115b86b.xcresult`。

## 未接受为证据的尝试

模拟器自动化能够读取并写入 `com.apple.Accessibility` 偏好，但本轮无法让系统“显示与文字大小”页面的“降低透明度”开关稳定反映该值；设置页仍显示关闭。因此没有把仅靠偏好写入后捕获的 NOTE1 截图冒充为“降低透明度已开启”的运行证据，也没有用默认态截图关闭 AC-09。

本轮结束前已将模拟器偏好恢复为 `ReduceTransparencyEnabled = 0`。

## 仍需关闭

- 在真机或可可靠控制该系统开关的模拟器上，使用同一数据和视口分别捕获关闭/开启状态；
- 抽样一级页顶部、二级页顶部、录入面板和至少一个通用玻璃操作面板；
- 验证不透明降级后的边界、文字对比、命中区和菜单行为；
- 与 iOS 17–25 材质降级、VoiceOver 和减少动态效果门禁一起完成最终运行验收。
