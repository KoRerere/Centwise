import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/currency.dart';
import '../../core/models.dart';
import '../../core/repository.dart';
import '../components.dart';
import '../icons.dart';
import '../motion.dart';
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
  late final TextEditingController _title = TextEditingController(text: StoreScope.read(context).ledger.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

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
        ThemeMode.dark => tr('始终开启'),
        ThemeMode.light => tr('始终关闭'),
      };

  static String _languageLabel(LanguagePref pref) => switch (pref) {
        LanguagePref.system => tr('跟随系统'),
        LanguagePref.zhHans => '简体中文',
        LanguagePref.zhHant => '繁體中文',
        LanguagePref.en => 'English',
      };

  Future<void> _pickTheme(LedgerStore store) async {
    final picked = await _pickOption<ThemeMode>(tr('深色模式'), store.themeMode, [
      (ThemeMode.system, tr('自动（跟随系统）')),
      (ThemeMode.dark, tr('始终开启')),
      (ThemeMode.light, tr('始终关闭')),
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
            Text(caption, style: cw(13, color: p.muted)),
            const SizedBox(height: 8),
            for (final (value, title) in options)
              Pressable(
                onTap: () => Navigator.of(context).pop(value),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(title,
                        style: cw(17,
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
      leadingLabel: tr('完成'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
        FormSection(title: tr('我的账本'), children: [
          Row(children: [
            LIcon('book-open', size: 17, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: FormTextField(controller: _title, hint: tr('账本名称'))),
          ]),
          FormRow(
            icon: 'check',
            label: tr('保存名称'),
            onTap: () => store.commit((ledger) => ledger.title = _title.text.trim()),
          ),
          FormRow(icon: 'receipt', label: tr('记录'), trailing: Text(tr('{n} 笔', {'n': store.ledger.entries.length}), style: cw(15, color: p.muted))),
          FormRow(icon: 'banknote', label: tr('货币'), chevron: true, trailing: CurrencyLabel(store.ledger.currency), onTap: _pickCurrency),
        ]),
        const SizedBox(height: 22),
        // One place for 备份与恢复: where the data lives, the two actions, and the details on request.
        FormSection(
          title: tr('备份与恢复'),
          footer: tr('换设备前先导出备份，在新设备导入即可恢复。删除 App 会删除本机数据，请定期导出。'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.track, shape: BoxShape.circle),
                  child: Center(child: LIcon('cloud-off', size: 20, color: p.muted)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('账本保存在本机'), style: cw(16, weight: FontWeight.w600, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(tr('iCloud 同步暂未开放'), style: cw(13, color: p.muted)),
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
        const SizedBox(height: 22),
        FormSection(title: tr('分类管理'), children: [
          FormRow(icon: 'layout-grid', label: tr('编辑分类'), chevron: true, onTap: _openCategories),
        ]),
        const SizedBox(height: 22),
        FormSection(title: tr('外观'), children: [
          FormRow(
            icon: 'sun-moon',
            label: tr('深色模式'),
            chevron: true,
            trailing: Text(_themeLabel(store.themeMode), style: cw(15, color: p.muted)),
            onTap: () => _pickTheme(store),
          ),
        ]),
        const SizedBox(height: 22),
        FormSection(title: tr('语言'), children: [
          FormRow(
            icon: 'languages',
            label: tr('应用语言'),
            chevron: true,
            trailing: Text(_languageLabel(store.languagePref), style: cw(15, color: p.muted)),
            onTap: () => _pickLanguage(store),
          ),
        ]),
        const SizedBox(height: 22),
        FormSection(title: tr('关于 Centwise'), children: [
          FormRow(icon: 'info', label: tr('版本'), trailing: Text(appVersion, style: cw(15, color: p.muted))),
          FormRow(
            icon: 'refresh-cw',
            label: tr('检查更新'),
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

/// Category list with "添加分类".
/// 设置 → 分类: every category, subcategories under their parent. Tap one to rename it, change its
/// icon or move it under another category.
class CategoriesSheet extends StatelessWidget {
  const CategoriesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    void edit(LedgerCategory? category) =>
        showCwSheet<void>(context, (_) => StoreScope(store: store, child: CategoryEditor(editing: category)));
    Widget row(LedgerCategory category, {bool child = false}) => Pressable(
          onTap: () => edit(category),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(children: [
              if (child) const SizedBox(width: 26),
              CategoryIcon(category, size: child ? 16 : 18, color: categoryTint(category.id)),
              const SizedBox(width: 10),
              Expanded(child: Text(category.name, style: cw(child ? 14 : 15, color: p.ink))),
              LIcon('chevron-right', size: 16, color: p.muted.withValues(alpha: 0.7)),
            ]),
          ),
        );
    return SheetScaffold(
      title: tr('分类'),
      leadingLabel: tr('完成'),
      trailingLabel: tr('添加'),
      onTrailing: () => edit(null),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
        for (final kind in const [EntryKind.expense, EntryKind.income]) ...[
          FormSection(title: kind.title, children: [
            for (final top in ledger.categories.where((c) =>
                c.kind == kind && (c.parentID == null || ledger.categoryByID(c.parentID!) == null))) ...[
              row(top),
              for (final sub in ledger.childrenOf(top.id)) row(sub, child: true),
            ],
          ]),
          const SizedBox(height: 22),
        ],
        Text(tr('点分类可以改名、换图标或调整上级分类；改名不影响已有账单。'), style: cw(12, color: p.muted)),
      ]),
    );
  }
}

/// New category, or edit an existing one ([editing]): name, icon, and optional parent (two levels).
class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.editing});
  final LedgerCategory? editing;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.name ?? '');
  late EntryKind _kind = widget.editing?.kind ?? EntryKind.expense;
  late String _icon = widget.editing == null ? categoryIconChoices.first : categoryIcon(widget.editing!);
  late String? _parentID = widget.editing?.parentID;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickParent(BuildContext context) async {
    final store = StoreScope.read(context);
    final ledger = store.ledger;
    final editing = widget.editing;
    final options = ledger.categories
        .where((c) =>
            c.kind == _kind &&
            c.id != editing?.id &&
            (c.parentID == null || ledger.categoryByID(c.parentID!) == null))
        .toList();
    final picked = await showCwSheet<String>(
      context,
      (sheetContext) {
        final p = Palette.of(sheetContext);
        Widget option(String? id, Widget leading, String label) => Pressable(
              onTap: () => Navigator.of(sheetContext).pop(id ?? ''),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: Row(children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: cw(15, color: p.ink))),
                  if ((id ?? '') == (_parentID ?? '')) LIcon('check', size: 18, color: p.accent, strokeWidth: 2.5),
                ]),
              ),
            );
        return SheetScaffold(
          title: tr('上级分类'),
          leadingLabel: tr('取消'),
          body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
            FormSection(children: [
              option(null, const SizedBox(width: 21), tr('无（一级分类）')),
              for (final c in options) option(c.id, CategoryIcon(c, size: 18), c.name),
            ]),
          ]),
        );
      },
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
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
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
            Emoji3DIcon(_icon, size: 22),
            const SizedBox(width: 10),
            Expanded(child: FormTextField(controller: _name, hint: tr('分类名称'), onChanged: (_) => setState(() {}))),
          ]),
          if (!hasChildren)
            FormRow(
              label: tr('上级分类'),
              chevron: true,
              trailing: Text(parent?.name ?? tr('无'), style: cw(15, color: p.muted)),
              onTap: () => _pickParent(context),
            ),
        ]),
        const SizedBox(height: 18),
        CardCaption(tr('图标')),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final icon in categoryIconChoices)
            Pressable(
              selected: icon == _icon,
              onTap: () {
                tick();
                setState(() => _icon = icon);
              },
              child: AnimatedContainer(
                duration: IOSMotion.snappyCurve.duration,
                curve: IOSMotion.snappyCurve,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: icon == _icon ? p.accent.withValues(alpha: 0.14) : p.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: icon == _icon ? p.accent : p.cardStroke, width: icon == _icon ? 2 : 0.75),
                ),
                child: Center(child: Emoji3DIcon(icon, size: 24)),
              ),
            ),
        ]),
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
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 32), children: [
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
                        Text(currency.name, style: cw(15, color: p.ink)),
                        Text('${currency.code} · ${currency.symbol}', style: cw(12, color: p.muted)),
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
