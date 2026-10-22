# Centwise：界面组件约定

2026-10-13 更新：按用户要求，界面改为参考 Copilot（iOS）的视觉与交互。原“原生组件优先”约定中，顶部导航、类型切换、分类点选和保存按钮改为自定义样式；其余仍优先使用 SwiftUI 系统组件。最低版本保持 iOS 17 / macOS 14，不使用全局 UIAppearance。

| 用途 | 实现 |
| --- | --- |
| 页面导航 | 自定义：蓝色渐变顶栏 + 居中品牌名 + 胶囊标签页（概览 / 分类 / 账单 / 账户）；iPhone 上用分页 `TabView` 支持左右滑动 |
| 设置与备份 | 顶栏左侧齿轮，以 sheet 打开 `NavigationStack` + `Form` |
| 时段切换 | 底部悬浮胶囊 `MonthCapsule`：‹ 今天 | 本月 | 近一年 ›，默认今天；箭头按模式翻天/翻月/翻 12 个月，再点已选中项回到当前 |
| 记一笔 | 底部右侧圆形悬浮“+”按钮 `FloatingCircleButton` |
| 支出/收入/转账切换 | 自定义胶囊分段控件；保留分摊重设确认 |
| 分类点选 | 圆形彩色图标网格（`Theme.tint(for:)` 按分类编号生成稳定颜色） |
| 保存 | 全宽主操作条 `PrimaryBarButtonStyle`，禁用时变灰 |
| 账户/转入账户 | `Picker` + `.menu`（系统） |
| 日期 | `DatePicker` + `.compact`（系统） |
| 金额与备注 | `TextField`；金额为系统数字/标点键盘，允许负号；中文/全角小数点在输入层转为英文点 |
| 退款、待入账、归档 | `Toggle`（系统） |
| 高级选项、分类查询 | `DisclosureGroup`、`List`、`.searchable`（系统） |
| 错误、删除及类型变更确认 | `alert` / `confirmationDialog`（系统） |
| 备份导入导出 | `fileImporter` / `fileExporter`（系统） |
| 图表 | Swift Charts：累计支出折线、分类环形图、六个月柱状图 |

视觉规则（`App/Components.swift` 的 `Theme`）：

- 颜色：品牌蓝 `brand`、深蓝 `brandDeep`、浅灰蓝画布 `canvas`、白色卡片 `card`、海军蓝正文 `ink`、灰色说明 `muted`；收入/低于预算绿色，接近预算橙色，超出红色。均有深色模式版本。
- 卡片：圆角 20、0.75pt 浅描边、无阴影（`ledgerCard`）；只有底部悬浮的时间胶囊和“+”按钮保留阴影。
- 文字：全局圆体（`.fontDesign(.rounded)`）；卡片标题为小号加粗、字距加宽的灰色说明文字（`CardCaption`）。
- 金额：`AmountText`，¥ 为缩小上标；支出不加负号，收入与退款显示为绿色并带“+”。

自绘组件意味着按下、禁用、无障碍和大字体由代码负责，需要真机检查。Mac 预览会显示 macOS 版本的系统控件（例如日期选择），不能当作 iPhone 截图。
