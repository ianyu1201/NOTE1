# NOTE1 V0.3 运行证据 Manifest

> 更新日期：2026-08-11
> 作用：把证据批次映射到进入 Git 的提交和适用边界；不把开发证据升级为最终独立验收。

## V0.3 证据范围裁决

- V0.3 只批准功能闭环，不冻结视觉基线；颜色、材质、纸张质感、品牌身份及深入动画优化延期到 V0.4。
- `确认视觉/` 中的文件降为 V0.4 视觉输入；它们不再是 V0.3 独立验收的通过依据，也不证明当前实现已经达到目标外观。
- 既有截图和录屏仍可证明其固定环境中的功能可见性、可读性、命中、手势结果和辅助设置行为；不得据此给出视觉质量通过结论。

## 状态说明

- `development-valid`：批次 README 与原始文件仍能证明所列模拟器环境中的开发观察。
- `final-invalidated`：后续共享外壳、令牌或页面继续变化，旧图不能证明最终固定候选；S6 前必须按最终提交重取受影响证据。
- “证据提交”是该批文件首次完整进入当前 Git 历史的提交。历史批次没有单独保存 build ID 时，不反推或伪造 build ID。
- “当前索引提交”用于识别后来补充的失效说明或边界；它不改变原始截图的捕获身份。

## 批次追踪

| 批次 | 证据提交 | 当前索引提交 | 环境 / 自动化 | 当前身份 |
| --- | --- | --- | --- | --- |
| `2026-08-09_实施批次` | `0d2ff3044e578ecb4c4dfa46c6779d869e7c725f` | `46d3deb1c939505cef0e4ac8ba9dee1002381380` | iPhone 15 Pro / iOS 26.5；74 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_UI优化批次` | `9013d2322a6df00d36d85136135bcb5e302293a7` | `4a710cb0a581adba58794006669ff634b6767760` | iPhone 15 Pro、iPhone 13 mini / iOS 26.5；74 项 XCTest | `development-valid / final-invalidated`；暖色小票已失效 |
| `2026-08-09_小票黑白视觉修正` | `4a710cb0a581adba58794006669ff634b6767760` | 同左 | iPhone 15 Pro / iOS 26.5；构建与语义抽样 | `development-valid / final-invalidated` |
| `2026-08-09_顶部细节统一` | `f70eaeb38df7d53d312ecc3e2cf441639472e836` | 同左 | iPhone 15 Pro、iPhone 13 mini / iOS 26.5；75/75 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_内容边界统一` | `d97067a8949373c91a4971658dcb23d80393425b` | 同左 | iPhone 15 Pro、iPhone 13 mini / iOS 26.5；76/76 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_排版与表面细节统一` | `66d9b9d66d2b84317eaeb2775f40d3bafb5902ae` | 同左 | iPhone 15 Pro、iPhone 13 mini / iOS 26.5；78/78 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_短票与手势边界` | `50b97b30700e17a34b119db46357c04ee99ea43d` | 同左 | iPhone 15 Pro / iOS 26.5；79 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_卡片与归入边界` | `2b61b3e6864a07e2f00cd83fbbda9dddff4ce089` | 同左 | iPhone 15 Pro / iOS 26.5；80 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_窄屏与末张边界` | `edd2fe91c006c1575cff40b817a2f8b2abf31e6e` | 同左 | iPhone 13 mini / iOS 26.5；80 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_容量与导出细节` | `e447ba19c8b1599707841ab110eb75b674145e3e` | 同左 | iPhone 13 mini、iPhone 15 Pro / iOS 26.5；81/81 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_二级页面顶部统一` | `9ad7078c4e0d100d2c39466ba83baf07d12f5691` | 同左 | iPhone 13 mini、iPhone 15 Pro / iOS 26.5；81/81 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_对象页顶部与工作台细节` | `89ccd6e25318304350a6b94ff52b074a98615a7d` | 同左 | iPhone 13 mini、iPhone 15 Pro / iOS 26.5；81 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-09_应用自有详情页统一` | `c3917fda296b6a7b3714c177ec0ab0572ca661ed` | 同左 | iPhone 13 mini、iPhone 15 Pro / iOS 26.5；81 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-11_降低透明度材质降级` | `64ef95f6344f04090e5da017c0379fdfe4748168` | 同左 | iPhone 15 Pro / iOS 26.5；82/82 XCTest | `development-valid / final-invalidated`；同视口运行证据仍缺失 |
| `2026-08-11_稳定用户文案` | `3398733949bc79303d8f5c58b86a844125e8acea` | 同左 | iPhone 15 Pro / iOS 26.5；83 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-11_批量动作术语统一` | `840a200f3dad20b98cea5f14fd6a0eafb1927c25` | 同左 | iPhone 15 Pro / iOS 26.5；84 项 XCTest | `development-valid / final-invalidated` |
| `2026-08-11_次级文字对比度` | `137005de23aa8a258bdaae237e9946f50dd0f38a` | 同左 | iPhone 15 Pro / iOS 26.5；85/85 XCTest | `development-valid`；仅证明所列功能可读性，不是视觉批准证据 |

## 最终验收重取规则

进入独立功能验收前，先固定一个候选提交，再按工程基线的功能 UI 证据矩阵批量取证。最终 manifest 每项必须补齐：合同 ID、固定提交/build、设备/OS、页面状态、数据夹具、字号与辅助设置、操作步骤、预期/实际、原始文件、采集时间及 `pass/fail/pending`。旧开发批次用于影响分析和回归线索，不直接复用为最终通过结论；V0.4 另行建立视觉基线和视觉证据矩阵。
