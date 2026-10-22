# Centwise：Mobbin 设计参考

## 2026-10-13：整体改为 Copilot 风格

用户指定参考 [Copilot · iOS screens](https://mobbin.com/apps/copilot-ios-166bc40a-0fb1-47c5-bdd5-6cc642c56f2a/91c57122-173b-52b5-9a0b-6df845b6d1c1/screens)。通过 Mobbin 查看的屏幕：

- [Cash flow](https://mobbin.com/screens/ffb9dae4-85d2-4d54-a997-7921a936e4ad)、[Spend 卡片](https://mobbin.com/screens/e7591103-070b-45f3-bd00-f73be234e5fc)：蓝色渐变顶栏、居中品牌名、齿轮与右侧图标、胶囊标签页；底部悬浮时间范围胶囊。
- [Dashboard（深色）](https://mobbin.com/screens/e45e34c5-26c1-4e20-99de-731530b71704)：累计支出折线与上月虚线对比、“超出”标签、To review 待核对列表、Net this month。
- [Categories](https://mobbin.com/screens/f1778c3a-ee4e-4bd7-960b-52db273f15d2)：左支出 / 中环形图 / 右总预算的摘要卡；每行彩色圆点 + 图标 + 名称 + 已花 + 红/橙/绿进度条 + 预算；右下悬浮“+”。
- [Transactions](https://mobbin.com/screens/e0f620ec-6c04-4d3d-b57f-b108bd34de72)：白色搜索卡 + 筛选图标，按日期分组的灰色小标题，行内彩色分类胶囊，收入绿色。
- [Monthly spending](https://mobbin.com/screens/ea210059-6422-4022-a25c-55063fb025b3)：已花 / 预算 / 剩余三栏指标与红绿状态点。
- [New category 弹层](https://mobbin.com/screens/fdb1a20f-3747-410b-b374-a61c7cd31fac)：胶囊分段、居中大号彩色输入、全宽保存条。

对应到 Centwise：概览 = Dashboard，分类 = Categories（含预算），账单 = Transactions，账户 = Accounts；底部时间范围胶囊改为月份胶囊（账本按月统计）。只参考布局、配色关系与交互方式，没有复制 Copilot 的品牌、图标、文案或素材。

---

## 2026-10-08：记一笔录入页（上一轮）


研究日期：2026-10-08。先查看 Mobbin 公开的真实 iOS 屏幕与流程，再修改录入页。未登录、未购买会员、未下载或复制应用素材。

## 实际查看的参考

1. [One · Enter Amount](https://mobbin.com/explore/screens/635d3a90-1c34-407b-be33-8fd5fbc7e7e3)：大金额集中在页面中部，来源账户是紧凑选择项，数字键盘与单一 Continue 操作在底部。参考视觉主次，不复制银行业务。
2. [Public · Custom Amount Entry](https://mobbin.com/explore/screens/9aad2380-2ddf-4a46-b4a9-c4ae789cfc7d)：输入光标与金额在一处，数字键盘直接编辑金额，Next 是明确的下一动作。参考金额输入的明确性，不照搬存款流程。
3. [Origin · Creating a budget](https://mobbin.com/explore/flows/e0773229-3a96-498d-8cb0-0d574792e565)：预算设置逐步处理月收入、预算、分类和分类金额。参考任务分层，不将 15 屏流程搬到一笔日常开销。
4. [Origin · Spending Overview](https://mobbin.com/explore/screens/d9ac8ded-f15f-474d-ac19-62f1b603a66f)：支出总览、上月比较与最近交易分区。作为后续概览层级参考，本轮不重构统计逻辑。

公开页面和截图可以访问，完整应用库需要登录。以上不代表已经走查各应用全部操作流程。

## 当前截图的具体问题

- Mac 原生 Form 把 TextField 标题作为左侧标签，导致“0.00”与真正输入区域分离。
- 日期、账户、待入账、分摊、备注、交易对象同时展开，缺少日常操作优先级。
- 分类下拉藏住可选项，必须打开才能知道有哪些分类。
- 保存位于角落，金额输入后缺少清晰的下一步。
- 编译通过不是体验验证，Mac 原生布局也不等于 iPhone 真机渲染。

## 本轮设计决定（根据参考归纳）

普通支出的主路径是“金额 → 分类 → 保存”。类型放顶部；金额是一个真正的大输入；常用分类图标网格直接点选；账户与日期默认有效账户和今天，仍能修改；备注可选；保存是底部完整宽度的主按钮。

退款/冲销、分摊、交易对象、待入账、来源字段和删除收进“更多选项”。编辑特殊记录时展开相关选项；已有分摊不因只修改备注被压平；改类型将重设分摊时先确认。

手机用系统数字键盘，Mac 支持直接键入。Mac 录入弹窗限制为手机比例，取消 Form 自动标签列。蓝绿粉渐变仅用于强调，不改变金额和分类含义。

这是交互设计选择，不是可用性研究结论或效果保证；仍需操作测试、用户反馈及 iPhone 真机验证。账本核心、迁移格式与私人备份不改。
