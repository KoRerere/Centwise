# Centwise · Flutter 版

Centwise 记账的 Flutter 实现，界面与交互和 SwiftUI 版保持一致（视觉为黑白极简（参考 Trackly 得意記）：纯白顶栏、黑色胶囊标签页与按钮、无阴影白卡片、今天 / 本月 / 近一年时间胶囊、记一笔内置数字键盘）。目标平台：**iPhone**，以及 **Mac 手机布局预览**。SwiftUI 版仍在上一级目录，未改动。

> 状态：代码已完整迁移，但**尚未在本机编译运行过**（编写环境无法安装 Flutter）。第一次请按下面步骤运行，`flutter analyze` / `flutter test` 有报错时把输出发给 Claude 修。

## 第一次运行

需要：Flutter 3.27 或更新（`flutter --version`），以及 Xcode（iOS 与 macOS 构建都要用）。

```sh
cd flutter
bash scripts/setup.sh          # 生成 ios/ 与 macos/ 工程并写入 Centwise 名称、Bundle ID、文件权限
flutter run -d macos --dart-define=CENTWISE_DEMO=true   # Mac 预览，演示数据，不落盘
flutter run -d macos           # Mac 开发版，数据存到 ~/Library/Containers/com.koray.centwise/…/Centwise/
```

`setup.sh` 只在缺少 `ios/`、`macos/` 时运行 `flutter create`，不会覆盖 `lib/`、`pubspec.yaml` 等已有文件；`flutter create` 附带的计数器示例测试会被改名停用。

### 装到 iPhone

1. `open ios/Runner.xcworkspace`，在 Runner → Signing & Capabilities 选择自己的开发团队。
2. 连接 iPhone，`flutter run -d <设备名>`（或在 Xcode 里 Run）。
3. Bundle ID 是 **com.koray.centwise**，和 SwiftUI 版（com.koray.qingledger）不同：两个 App 可以同时存在，数据互不影响。旧数据请在 SwiftUI 版导出备份，再在 Flutter 版“设置 → 导入”。

## 验证

```sh
bash scripts/verify.sh   # pub get → analyze → 核心测试 → iOS（未签名）与 macOS 调试构建
CENTWISE_LEGACY_DB=/path/database.sql flutter test   # 可选：用本机 Money Pro 数据库做迁移核对
```

## 数据与格式

- 金额为整数分（Dart `int`，64 位）；输入最多两位小数，图表才转浮点。
- 账本保存在 iOS `Documents/Centwise/ledger.centwise`（开启 Finder 文件共享），Mac 在应用支持目录 `Centwise/`。写入用临时文件 + 重命名；`Backups/` 保留最近一次修改前、每天第一笔修改前和每次导入前的快照。
- 备份格式与 SwiftUI 版的 `.qingledger` **相同**（同样的字段、排序键、2001-01-01 起算的秒数日期、`schemaVersion = 1`），所以旧备份可直接导入；新导出的文件扩展名为 `.centwise`。
- 读取失败不会用空账本覆盖原文件，而是暂停写入，等待导入已核对的备份。
- 尚未实现：iOS 数据保护等级（SwiftUI 版写入时用了 completeUntilFirstUserAuthentication）、从“文件”App 直接打开备份、主屏幕图标。
- 不使用网络、云端、第三方分析；字体和图标都随 App 打包。

## Money Pro 迁移

导入逻辑与 SwiftUI 版一致：只读打开 `database.sql`，遇到未确认语义的数据直接停止，原表全部归档。命令行：

```sh
dart run bin/migrate.dart migrate /path/database.sql /path/个人账本.centwise
```

SQLite 的 REAL 字段在 Dart 里先读成浮点再转文本，归档里个别数字的写法可能和 SwiftUI 版略有差异（例如 `26.14` 与 `26.140000000000001`），金额换算仍按“误差小于万分之一分”核对。

## 代码结构

| 路径 | 内容 |
| --- | --- |
| `lib/core/` | 纯 Dart 账本核心：`money.dart` 金额、`models.dart` 模型与校验、`repository.dart` 编解码与快照、`money_pro_importer.dart` 迁移 |
| `lib/app/theme.dart` | 颜色（浅色/深色）、圆体字、分类配色 |
| `lib/app/components.dart` | 卡片、金额、分类标签、预算条、时间胶囊、悬浮按钮、账单行 |
| `lib/app/charts.dart` | 累计折线、年度月柱、环形图、六个月趋势（CustomPainter，无图表依赖） |
| `lib/app/root_page.dart` | 顶栏、标签页、可滑动页面、悬浮控件、错误与导入预览 |
| `lib/app/pages/` | 概览、分类与预算、账单、账户、设置 |
| `lib/app/entry_editor.dart` | 记一笔、内置数字键盘、分类选择 |
| `lib/app/icons.dart`、`lucide_icons.dart` | Lucide 图标（SVG 数据随包，`scripts/gen_icons.py` 生成）；旧 SF Symbol 名称与分类名关键词映射到 Lucide |
| `test/core_test.dart` | 核心测试（由 SwiftUI 版测试逐条移植，另加 SwiftUI 备份读取测试） |

第三方：Lucide 图标（ISC，`assets/LICENSE-lucide.txt`），分类图标用系统自带的 Apple emoji（不打包图片），Nunito 字体（SIL OFL，`assets/fonts/OFL-Nunito.txt`），以及 pub 包 flutter_svg、path_provider、file_picker、sqlite3、sqlite3_flutter_libs。
