import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'money.dart';

class MigrationSummary {
  MigrationSummary({
    required this.sourceActiveEntries,
    required this.importedEntries,
    required this.accounts,
    required this.categories,
    required this.reviewedEntries,
    required this.incomeCents,
    required this.expenseCents,
    required this.warnings,
  });

  final int sourceActiveEntries;
  final int importedEntries;
  final int accounts;
  final int categories;
  final int reviewedEntries;
  final int incomeCents;
  final int expenseCents;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'accounts': accounts,
        'categories': categories,
        'expenseCents': expenseCents,
        'importedEntries': importedEntries,
        'incomeCents': incomeCents,
        'reviewedEntries': reviewedEntries,
        'sourceActiveEntries': sourceActiveEntries,
        'warnings': warnings,
      };
}

/// Read-only migration of a Money Pro `database.sql`. Unknown semantics stop the import
/// instead of being skipped or guessed. All source tables are archived verbatim.
class MoneyProImporter {
  MoneyProImporter._();

  static (Ledger, MigrationSummary) read(String path) {
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on Object {
      throw LedgerError('无法以只读方式打开 Money Pro 数据库。请选择 database.sql，不是 .back 文件。');
    }
    try {
      return _read(db);
    } on SqliteException catch (error) {
      throw LedgerError('旧账本结构不支持：${error.message}');
    } finally {
      db.dispose();
    }
  }

  /// SQLite values as text, matching what the SwiftUI version stored (`sqlite3_column_text`).
  static String? _text(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double) {
      if (value == value.truncateToDouble() && value.abs() < 1e15) return '${value.toInt()}.0';
      return value.toString();
    }
    if (value is Uint8List) return utf8.decode(value, allowMalformed: true);
    return value.toString();
  }

  static (Ledger, MigrationSummary) _read(Database db) {
    List<Map<String, String?>> rows(String sql) {
      final result = db.select(sql);
      if (result.rows.length > 200000) throw LedgerError('旧账本表过大，已停止导入。');
      return [
        for (final row in result.rows)
          {for (var i = 0; i < result.columnNames.length; i++) result.columnNames[i]: _text(row[i])}
      ];
    }

    String value(Map<String, String?> row, String key) => row[key] ?? '';
    int integer(Map<String, String?> row, String key) => int.tryParse(value(row, key)) ?? 0;

    final integrity = rows('PRAGMA integrity_check');
    if (integrity.length != 1 || integrity.first.values.first != 'ok') {
      throw LedgerError('旧数据库未通过完整性检查，未导入任何内容。');
    }
    final names = rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        .map((r) => value(r, 'name'))
        .toList();
    const required = {'balance', 'category', 'transactions', 'splitTransaction', 'currency'};
    if (!names.toSet().containsAll(required)) throw LedgerError('这不是支持的 Money Pro 账本数据库。');

    final tables = <String, List<Map<String, String?>>>{};
    for (final name in names) {
      final safe = name.replaceAll('"', '""');
      tables[name] = rows('SELECT * FROM "$safe"');
    }
    final warnings = <String>[
      '第一版仅迁移人民币账户；余额按旧账户 sum 字段与历史记录推算，尚未与 Money Pro 或银行对账。',
      '旧预算、循环规则、计划、同步状态和其他源表原字段已归档，但暂不执行；请在 Centwise 重新设置预算。',
    ];

    final accounts = <Account>[];
    for (final row in tables['balance'] ?? const <Map<String, String?>>[]) {
      if (value(row, 'currencyKey') != 'CNY') throw LedgerError('旧账本包含非人民币账户，第一版无法无损导入，已停止。');
      accounts.add(Account(
        id: value(row, 'primaryKey'),
        name: value(row, 'name').isEmpty ? '旧账户' : value(row, 'name'),
        openingBalance: Money.legacy(value(row, 'sum')),
        archived: integer(row, 'isDeleted') != 0 || integer(row, 'isHidden') != 0,
      ));
    }

    final categories = <LedgerCategory>[];
    for (final row in tables['category'] ?? const <Map<String, String?>>[]) {
      final type = integer(row, 'flowType');
      if (type != 1 && type != 2) throw LedgerError('发现未支持的旧分类类型，已停止导入。');
      final name = value(row, 'name');
      final parent = value(row, 'parentPrimaryKey');
      categories.add(LedgerCategory(
        id: value(row, 'primaryKey'),
        name: name.isEmpty ? '旧分类' : name,
        kind: type == 1 ? EntryKind.income : EntryKind.expense,
        // Icons are chosen from the name when drawing; store a neutral default.
        symbol: 'layout-grid',
        parentID: parent.isEmpty ? null : parent,
      ));
    }
    final categoryIDs = categories.map((c) => c.id).toSet();
    for (final category in categories) {
      if (category.parentID != null && !categoryIDs.contains(category.parentID)) {
        category.parentID = null;
        warnings.add('有一个旧分类的父分类不存在，已保留为独立分类。');
      }
    }

    final payees = {for (final row in tables['payee'] ?? const <Map<String, String?>>[]) value(row, 'primaryKey'): value(row, 'name')};
    final splits = <String, List<Map<String, String?>>>{};
    for (final row in tables['splitTransaction'] ?? const <Map<String, String?>>[]) {
      splits.putIfAbsent(value(row, 'transactionsPrimaryKey'), () => []).add(row);
    }
    final transactionRows = tables['transactions'] ?? const <Map<String, String?>>[];
    for (final row in transactionRows) {
      if (int.tryParse(value(row, 'isDeleted')) == null || int.tryParse(value(row, 'transactionType')) == null) {
        throw LedgerError('旧账本缺少有效的交易状态或类型字段，已停止导入。');
      }
    }
    final active = transactionRows.where((r) => integer(r, 'isDeleted') == 0).toList();
    final entries = <Entry>[];
    var recoveredCategories = 0;
    final recoveredCategoryIDs = <String>{};
    for (final row in active) {
      final id = value(row, 'primaryKey');
      final type = integer(row, 'transactionType');
      if (integer(row, 'isBalanceChange') != 0 ||
          value(row, 'balanceAdjasmentPK').isNotEmpty ||
          value(row, 'assetsPrimaryKey').isNotEmpty ||
          value(row, 'liabilitiesPrimaryKey').isNotEmpty ||
          value(row, 'secondCashFlowPrimaryKey').isNotEmpty) {
        throw LedgerError('发现尚未支持的资产、负债或余额关联，无法确认金额语义，已停止导入。');
      }
      final EntryKind kind;
      switch (type) {
        case 0:
          kind = EntryKind.expense;
        case 1:
          kind = EntryKind.income;
        case 7:
          if (Money.legacy(value(row, 'sum')) != 0) throw LedgerError('发现非零的旧类型 7 记录，无法确认余额语义，已停止导入。');
          kind = EntryKind.adjustment;
        default:
          throw LedgerError('旧交易类型 $type 尚未实现无损迁移，未修改当前账本。');
      }
      final seconds = double.tryParse(value(row, 'date'));
      if (seconds == null || !seconds.isFinite || seconds < 0 || seconds > 4102444800) {
        throw LedgerError('旧账本含异常日期，已停止导入。');
      }
      final amount = Money.legacy(value(row, 'sum'));
      var needsReview = type == 7;
      final allocations = <Allocation>[];
      for (final split in splits[id] ?? const <Map<String, String?>>[]) {
        var categoryID = value(split, 'categoryPrimaryKey');
        if (categoryID.isEmpty) categoryID = 'legacy-unassigned-${kind.name}';
        if (!categories.any((c) => c.id == categoryID)) {
          categories.add(LedgerCategory(id: categoryID, name: '未识别旧分类', kind: kind, symbol: 'folder-search'));
          recoveredCategories += 1;
          recoveredCategoryIDs.add(categoryID);
          needsReview = true;
        }
        if (recoveredCategoryIDs.contains(categoryID)) needsReview = true;
        allocations.add(Allocation(categoryID: categoryID, amount: Money.legacy(value(split, 'sum'))));
      }
      entries.add(Entry(
        id: id,
        kind: kind,
        amount: amount,
        date: DateTime.fromMicrosecondsSinceEpoch((seconds * 1e6).round()),
        accountID: value(row, 'cashFlowPrimaryKey'),
        allocations: allocations,
        note: value(row, 'description'),
        payee: payees[value(row, 'payeePrimaryKey')] ?? '',
        pending: integer(row, 'isPending') != 0,
        legacyType: type,
        needsReview: needsReview,
      ));
    }
    final reviewCount = entries.where((e) => e.needsReview).length;
    final specialCount = entries.where((e) => e.legacyType == 7).length;
    if (specialCount > 0) warnings.add('$specialCount 条零金额类型 7 记录保留为待核对的余额调整；不计入收入或支出。');
    if (recoveredCategories > 0) {
      warnings.add('$recoveredCategories 个分摊引用的旧分类已不存在，已建立“未识别旧分类”保留其金额与编号，相关记录标为待核对。');
    }
    final ledger = Ledger(
      title: '个人账本',
      accounts: accounts,
      categories: categories,
      entries: entries,
      legacy: LegacyArchive(tables: tables, warnings: warnings),
    );
    ledger.validate();
    int sum(EntryKind kind) =>
        entries.where((e) => e.kind == kind && !e.pending).fold(0, (total, e) => total + e.amount);
    final summary = MigrationSummary(
      sourceActiveEntries: active.length,
      importedEntries: entries.length,
      accounts: accounts.length,
      categories: categories.length,
      reviewedEntries: reviewCount,
      incomeCents: sum(EntryKind.income),
      expenseCents: sum(EntryKind.expense),
      warnings: warnings,
    );
    return (ledger, summary);
  }
}
