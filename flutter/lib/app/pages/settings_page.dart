import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/currency.dart';
import '../../core/models.dart';
import '../../core/repository.dart';
import '../components.dart';
import '../emoji_picker.dart';
import '../icons.dart';
import '../motion.dart';
import '../entry_editor.dart' show CategoryChooser, CategoryGrid, CategoryGridTile;
import '../sheets.dart';
import '../store.dart';
import '../theme.dart';
import '../version.dart';
import '../../l10n/l10n.dart';

/// "设置与备份", opened from the gear in the header.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  Future<void> _export() async {
    final store = StoreScope.read(context);
    final now = DateTime.now();
    final name = '${tr('Centwise备份')}-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.centwise';
    try {
      final data = LedgerCodec.encode(store.ledger);
      final path = await FilePicker.platform.saveFile(dialogTitle: tr('导出完整备份'), fileName: name, bytes: data);
      if (path == null) return;
      // On desktop the picker only returns the chosen path; write the file ourselves.
      if (!Platform.isIOS && !Platform.isAndroid) File(path).writeAsBytesSync(data, flush: true);
      if (mounted) await showCwAlert(context, tr('备份已保存'), tr('已导出完整备份，请保存在可信位置。'));
    } catch (e) {
      store.update(() => store.error = e.toString());
    }
  }

  Future<void> _import() async {
    final store = StoreScope.read(context);
    final result = await FilePicker.platform.pickFiles(dialogTitle: tr('导入 Centwise 备份 / Money Pro 数据库'), type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    store.prepareImport(path);
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => tr('自动'),
        ThemeMode.dark => tr('深色'),
        ThemeMode.light => tr('浅色'),
      };

  static String _languageLabel(LanguagePref pref) => switch (pref) {
        LanguagePref.system => tr('跟随系统'),
        LanguagePref.zhHans => '简体中文',
        LanguagePref.zhHant => '繁體中文',
        LanguagePref.en => 'English',
      };

  Future<void> _pickTheme(LedgerStore store) async {
    final picked = await _pickOption<ThemeMode>(tr('外观'), store.themeMode, [
      (ThemeMode.system, tr('自动（跟随系统）')),
      // iOS 显示与亮度 wording and order: 浅色, then 深色.
      (ThemeMode.light, tr('浅色')),
      (ThemeMode.dark, tr('深色')),
    ]);
    if (picked != null) store.setThemeMode(picked);
  }

  Future<void> _pickLanguage(LedgerStore store) async {
    final picked = await _pickOption<LanguagePref>(tr('应用语言'), store.languagePref, [
      for (final pref in LanguagePref.values) (pref, _languageLabel(pref)),
    ]);
    if (picked != null) store.setLanguage(picked);
  }

  /// Copilot-style option sheet: small caption, centred choices; the current one is in accent colour with a check.
  Future<T?> _pickOption<T>(String caption, T current, List<(T, String)> options) {
    final p = Palette.of(context);
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: p.card,
      barrierColor: const Color(0x59000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 38, height: 5, decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(9))),
            const SizedBox(height: 16),
            Text(caption, style: cw(IOSText.footnote, color: p.muted)),
            const SizedBox(height: 8),
            for (final (value, title) in options)
              Pressable(
                onTap: () => Navigator.of(context).pop(value),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(title,
                        style: cw(IOSText.headline,
                            weight: value == current ? FontWeight.w700 : FontWeight.w400,
                            color: value == current ? p.accent : p.ink)),
                    if (value == current) ...[const SizedBox(width: 6), LIcon('check', size: 18, color: p.accent, strokeWidth: 2.5)],
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _pickCurrency() {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: const CurrencyPicker()));
  }

  void _openCategories() {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: const CategoriesSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    return SheetScaffold(
      title: tr('设置与备份'),
      largeTitle: true,
      closeButton: false,
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(16, SheetLargeTitle.topPadding, 16, 32), children: [
        SheetLargeTitle(tr('设置与备份')),
        FormSection(children: [
          FormRow(icon: 'receipt', label: tr('记录'), trailing: Text(tr('{n} 笔', {'n': store.ledger.entries.length}), style: cw(IOSText.body, color: p.muted))),
          FormRow(icon: 'coins', label: tr('货币'), chevron: true, trailing: CurrencyLabel(store.ledger.currency), onTap: _pickCurrency),
        ]),
        const SizedBox(height: 28),
        // One place for 备份与恢复: where the data lives, the two actions, and the details on request.
        FormSection(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                // Same tile and text column as the rows below, so the status lines up with them.
                const FormIconTile('cloud-off'),
                const SizedBox(width: FormRow.textInset - FormIconTile.size),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('账本保存在本机'), style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(tr('iCloud 同步暂未开放'), style: cw(IOSText.footnote, color: p.muted)),
                  ]),
                ),
              ]),
            ),
            FormRow(icon: 'upload', label: tr('导出完整备份'), onTap: _export),
            FormRow(icon: 'download', label: tr('导入备份或 Money Pro 数据'), onTap: _import),
            FormRow(
              icon: 'info',
              label: tr('了解更多'),
              chevron: true,
              onTap: () => showCwAlert(
                context,
                tr('关于备份'),
                tr('.centwise 备份包含全部 Centwise 数据和旧账本原字段归档；也可以导入 SwiftUI 版导出的 .qingledger 备份。导入前会显示预览并询问是否替换，不会操作手机里的 Money Pro。\n\n') +
                    tr('备份是明文财务数据，建议保存在加密磁盘。无云同步，删除应用仍可能丢失本机数据，请定期导出。Backups 保留最近一次修改前、每天第一笔修改前和导入前的快照；第一版不自动清理每日/导入快照。'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        // 通用: related rows share one card the way iOS Settings groups them, instead of one
        // skinny card each.
        FormSection(children: [
          FormRow(icon: 'layout-grid', label: tr('编辑分类'), chevron: true, onTap: _openCategories),
          FormRow(
            icon: 'sun-moon',
            label: tr('外观'),
            chevron: true,
            trailing: Text(_themeLabel(store.themeMode), style: cw(IOSText.body, color: p.muted)),
            onTap: () => _pickTheme(store),
          ),
          FormRow(
            icon: 'languages',
            label: tr('应用语言'),
            chevron: true,
            trailing: Text(_languageLabel(store.languagePref), style: cw(IOSText.body, color: p.muted)),
            onTap: () => _pickLanguage(store),
          ),
          FormRow(
            icon: 'refresh-cw',
            label: tr('检查更新'),
            trailing: Text(tr('当前版本：{version}', {'version': appVersion}), style: cw(IOSText.body, color: p.muted)),
            onTap: () => showCwAlert(
              context,
              tr('检查更新'),
              tr('当前版本 {version}。Centwise 目前是开发版，还没有接入在线更新；新版本会直接安装到你的设备上。', {'version': appVersion}),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// 设置 → 编辑分类: each kind's top-level categories as a grid (the 选择分类 layout). Tap one
/// without subcategories to edit it; one with subcategories (count badge) opens its own page —
/// edit the parent there, see its subcategories as a grid, and add one.
class CategoriesSheet extends StatefulWidget {
  const CategoriesSheet({super.key});

  @override
  State<CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<CategoriesSheet> {
  /// The top-level category whose page is showing; null = the overview.
  String? _parentID;

  /// +1 going into a parent, −1 coming back: which way the content slides.
  int _direction = 1;

  void _open(String id) => setState(() {
        _direction = 1;
        _parentID = id;
      });

  void _back() => setState(() {
        _direction = -1;
        _parentID = null;
      });

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    void edit(LedgerCategory? category, {EntryKind? kind, String? parentID}) => showCwSheet<void>(
          context,
          (_) => StoreScope(store: store, child: CategoryEditor(editing: category, initialKind: kind, initialParentID: parentID)),
        );
    // The parent may have been deleted or moved while its page was open.
    final parent = _parentID == null ? null : ledger.categoryByID(_parentID!);
    if (_parentID != null && (parent == null || parent.parentID != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _back();
      });
    }

    Widget caption(String text) => Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 10),
          child: Text(text, style: cw(IOSText.footnote, color: p.muted)),
        );
    Widget addTile(VoidCallback onTap, String label) => CategoryGridTile(
          name: label,
          icon: LIcon('plus', size: 22, color: p.ink),
          onTap: onTap,
        );
    Widget tile(LedgerCategory c, {bool drill = true}) {
      final children = ledger.childrenOf(c.id).length;
      return CategoryGridTile(
        name: c.name,
        icon: CategoryIcon(c, size: 24, color: categoryTint(c.id)),
        badge: drill && children > 0 ? '$children' : null,
        onTap: drill && children > 0 ? () => _open(c.id) : () => edit(c),
      );
    }

    final Widget content;
    if (parent == null) {
      content = ListView(key: const ValueKey('overview'), clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        for (final kind in const [EntryKind.expense, EntryKind.income]) ...[
          caption(kind.title),
          CategoryGrid(children: [
            for (final top in ledger.categories.where((c) =>
                c.kind == kind && (c.parentID == null || ledger.categoryByID(c.parentID!) == null)))
              tile(top),
            addTile(() => edit(null, kind: kind), tr('添加')),
          ]),
          const SizedBox(height: 22),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(tr('点分类可以改名、换图标或调整上级分类；带数字的分类有子分类，点开查看。改名不影响已有账单。'),
              style: cw(IOSText.footnote, color: p.muted, height: 1.35)),
        ),
      ]);
    } else {
      final subs = ledger.childrenOf(parent.id);
      content = ListView(key: ValueKey('parent-${parent.id}'), clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        FormSection(children: [
          Pressable(
            onTap: () => edit(parent),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: FormRow.minHeight),
              child: Row(children: [
                CategoryIcon(parent, size: 24, color: categoryTint(parent.id)),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('编辑「{name}」', {'name': parent.name}), style: cw(IOSText.body, color: p.ink))),
                LIcon('chevron-right', size: 14, color: p.muted.withValues(alpha: 0.6)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 22),
        caption(tr('子分类')),
        CategoryGrid(children: [
          for (final c in subs) tile(c, drill: false),
          addTile(() => edit(null, kind: parent.kind, parentID: parent.id), tr('添加')),
        ]),
      ]);
    }

    return PopScope(
      // Inside a parent, the back gesture / Esc returns to the overview first.
      canPop: _parentID == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SheetScaffold(
        title: parent?.name ?? tr('分类'),
        leadingLabel: parent == null ? tr('完成') : tr('返回'),
        onLeading: parent == null ? null : _back,
        // iOS push between the overview and a parent's page; each level scrolls on its own.
        body: PushSwitcher(direction: _direction, child: content),
      ),
    );
  }
}

/// New category, or edit an existing one ([editing]): name, icon, and optional parent (two levels).
class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.editing, this.initialKind, this.initialParentID});
  final LedgerCategory? editing;

  /// Parent for a new category (添加子分类 from inside a parent in 编辑分类).
  final String? initialParentID;

  /// Kind for a new category when the caller already knows it (e.g. opened from the category chooser).
  final EntryKind? initialKind;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.name ?? '');
  late EntryKind _kind = widget.editing?.kind ?? widget.initialKind ?? EntryKind.expense;
  late String _icon = widget.editing == null ? categoryIconChoices.first : categoryIcon(widget.editing!);
  late String? _parentID = widget.editing == null ? widget.initialParentID : widget.editing!.parentID;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 上级分类 uses the same emoji-grid category sheet as 记一笔, first level only, with 无 first.
  Future<void> _pickParent(BuildContext context) async {
    final store = StoreScope.read(context);
    final picked = await showCwSheet<String>(
      context,
      (_) => StoreScope(
        store: store,
        child: CategoryChooser(
          kind: _kind,
          selectedID: _parentID ?? '',
          title: tr('上级分类'),
          leadingLabel: tr('无'),
          leadingIcon: 'circle-x',
          topLevelOnly: true,
          excludeID: widget.editing?.id,
          showAdd: false,
        ),
      ),
    );
    if (picked != null) setState(() => _parentID = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    final editing = widget.editing;
    final name = _name.text.trim();
    // Two levels only: a category that has subcategories stays top-level.
    final hasChildren = editing != null && ledger.childrenOf(editing.id).isNotEmpty;
    final parent = _parentID == null ? null : ledger.categoryByID(_parentID!);
    final changed = editing == null ||
        name != editing.name ||
        _icon != categoryIcon(editing) ||
        _parentID != editing.parentID;
    return SheetScaffold(
      title: editing == null ? tr('新分类') : tr('编辑分类'),
      trailingLabel: tr('保存'),
      onTrailing: name.isEmpty || !changed
          ? null
          : () {
              final ok = store.commit((ledger) {
                if (editing == null) {
                  ledger.categories.add(LedgerCategory(name: name, kind: _kind, symbol: _icon, parentID: _parentID));
                } else {
                  final target = ledger.categoryByID(editing.id);
                  if (target == null) return;
                  target
                    ..name = name
                    ..symbol = _icon
                    ..parentID = _parentID;
                }
              });
              if (ok) Navigator.of(context).pop();
            },
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
        // The kind can't change once bills use the category.
        if (editing == null) ...[
          CapsuleSegments<EntryKind>(
            values: const [EntryKind.expense, EntryKind.income],
            selected: _kind,
            label: (k) => k.title,
            onChanged: (k) => setState(() {
              _kind = k;
              _parentID = null;
            }),
          ),
          const SizedBox(height: 18),
        ],
        FormSection(children: [
          Row(children: [
            EmojiIcon(_icon, size: 22),
            const SizedBox(width: 10),
            Expanded(child: FormTextField(controller: _name, hint: tr('分类名称'), onChanged: (_) => setState(() {}))),
          ]),
          if (!hasChildren)
            FormRow(
              label: tr('上级分类'),
              chevron: true,
              trailing: Text(parent?.name ?? tr('无'), style: cw(IOSText.body, color: p.muted)),
              onTap: () => _pickParent(context),
            ),
        ]),
        const SizedBox(height: 18),
        CardCaption(tr('图标')),
        const SizedBox(height: 10),
        // The whole Apple emoji set, grouped like the system picker (常用 first: the bookkeeping picks).
        EmojiPicker(
          selected: emojiFor(_icon),
          common: [for (final icon in categoryIconChoices) categoryEmoji[icon]!],
          onSelected: (emoji) => setState(() => _icon = iconKeyForEmoji(emoji)),
        ),
      ]),
    );
  }
}

/// 设置 → 货币: the ledger's single currency, with round flags. Only the symbol changes; amounts are
/// not converted.
class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final current = store.ledger.currency;
    return SheetScaffold(
      title: tr('货币'),
      leadingLabel: tr('完成'),
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
        FormSection(
          footer: tr('账本只用一种货币。切换后只改变显示的货币符号，已记录的金额不会换算。'),
          children: [
            for (final currency in supportedCurrencies)
              Pressable(
                selected: currency.code == current,
                onTap: () {
                  if (currency.code == current) return;
                  tick();
                  store.setCurrency(currency.code);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 54),
                  child: Row(children: [
                    FlagIcon(currency.flag, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(currency.name, style: cw(IOSText.body, color: p.ink)),
                        Text('${currency.code} · ${currency.symbol}', style: cw(IOSText.footnote, color: p.muted)),
                      ]),
                    ),
                    if (currency.code == current) LIcon('check', size: 18, color: p.accent, strokeWidth: 2.5),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
