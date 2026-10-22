import 'dart:math';

import 'currency.dart';
import 'money.dart';
import '../l10n/l10n.dart';

/// Foundation's `Date` Codable form: seconds since 2001-01-01 00:00:00 UTC.
/// Kept so `.qingledger` backups from the SwiftUI version import unchanged.
const double _referenceOffset = 978307200;

double encodeDate(DateTime date) => date.toUtc().microsecondsSinceEpoch / 1e6 - _referenceOffset;

DateTime decodeDate(Object? value) {
  if (value is! num || !value.isFinite) throw LedgerError(tr('记录含无效日期、金额或账户。'));
  final micros = ((value.toDouble() + _referenceOffset) * 1e6).round();
  return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toLocal();
}

int _int(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw LedgerError(tr('备份中的数字字段无效。'));
}

String _string(Object? value, [String fallback = '']) => value is String ? value : fallback;
bool _bool(Object? value, [bool fallback = false]) => value is bool ? value : fallback;

/// First element or null (kept local so the code does not depend on newer SDK extensions).
extension FirstOrNullValue<T> on Iterable<T> {
  T? get firstOrNullValue {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

final Random _random = Random.secure();

/// Random (version 4) UUID in Foundation's uppercase form, e.g. "1B4E28BA-2FA1-41D2-883F-0016D3CCA427".
String newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

enum EntryKind {
  expense,
  income,
  transfer,
  adjustment;

  String get title => switch (this) {
        EntryKind.expense => tr('支出'),
        EntryKind.income => tr('收入'),
        EntryKind.transfer => tr('转账'),
        EntryKind.adjustment => tr('余额调整'),
      };

  static EntryKind parse(Object? raw) {
    for (final kind in EntryKind.values) {
      if (kind.name == raw) return kind;
    }
    throw LedgerError(tr('备份中有未知的记录类型。'));
  }
}

class Account {
  Account({String? id, required this.name, this.openingBalance = 0, this.currency = 'CNY', this.archived = false})
      : id = id ?? newId();

  String id;
  String name;
  int openingBalance;
  String currency;
  bool archived;

  Account copy() => Account(id: id, name: name, openingBalance: openingBalance, currency: currency, archived: archived);

  Map<String, Object?> toJson() =>
      {'archived': archived, 'currency': currency, 'id': id, 'name': name, 'openingBalance': openingBalance};

  factory Account.fromJson(Map<String, Object?> json) => Account(
        id: _string(json['id']),
        name: _string(json['name']),
        openingBalance: _int(json['openingBalance']),
        currency: _string(json['currency'], 'CNY'),
        archived: _bool(json['archived']),
      );
}

class LedgerCategory {
  LedgerCategory({String? id, required this.name, required this.kind, this.symbol = 'layout-grid', this.parentID})
      : id = id ?? newId();

  String id;
  String name;
  EntryKind kind;

  /// A Lucide icon name for new categories; backups from the SwiftUI version carry SF Symbol names,
  /// which the app maps to Lucide when drawing (see app/icons.dart).
  String symbol;
  String? parentID;

  LedgerCategory copy() => LedgerCategory(id: id, name: name, kind: kind, symbol: symbol, parentID: parentID);

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        if (parentID != null) 'parentID': parentID,
        'symbol': symbol,
      };

  factory LedgerCategory.fromJson(Map<String, Object?> json) => LedgerCategory(
        id: _string(json['id']),
        name: _string(json['name']),
        kind: EntryKind.parse(json['kind']),
        symbol: _string(json['symbol'], 'layout-grid'),
        parentID: json['parentID'] as String?,
      );
}

class Allocation {
  Allocation({required this.categoryID, required this.amount});
  String categoryID;
  int amount;

  Allocation copy() => Allocation(categoryID: categoryID, amount: amount);
  Map<String, Object?> toJson() => {'amount': amount, 'categoryID': categoryID};
  factory Allocation.fromJson(Map<String, Object?> json) =>
      Allocation(categoryID: _string(json['categoryID']), amount: _int(json['amount']));
}

class Entry {
  Entry({
    String? id,
    required this.kind,
    required this.amount,
    DateTime? date,
    required this.accountID,
    this.destinationID,
    List<Allocation>? allocations,
    this.note = '',
    this.payee = '',
    this.pending = false,
    this.legacyType,
    this.needsReview = false,
  })  : id = id ?? newId(),
        date = date ?? DateTime.now(),
        allocations = allocations ?? [];

  String id;
  EntryKind kind;
  int amount;
  DateTime date;
  String accountID;
  String? destinationID;
  List<Allocation> allocations;
  String note;
  String payee;
  bool pending;
  int? legacyType;
  bool needsReview;

  Entry copy() => Entry(
        id: id,
        kind: kind,
        amount: amount,
        date: date,
        accountID: accountID,
        destinationID: destinationID,
        allocations: allocations.map((a) => a.copy()).toList(),
        note: note,
        payee: payee,
        pending: pending,
        legacyType: legacyType,
        needsReview: needsReview,
      );

  Map<String, Object?> toJson() => {
        'accountID': accountID,
        'allocations': allocations.map((a) => a.toJson()).toList(),
        'amount': amount,
        'date': encodeDate(date),
        if (destinationID != null) 'destinationID': destinationID,
        'id': id,
        'kind': kind.name,
        if (legacyType != null) 'legacyType': legacyType,
        'needsReview': needsReview,
        'note': note,
        'payee': payee,
        'pending': pending,
      };

  factory Entry.fromJson(Map<String, Object?> json) => Entry(
        id: _string(json['id']),
        kind: EntryKind.parse(json['kind']),
        amount: _int(json['amount']),
        date: decodeDate(json['date']),
        accountID: _string(json['accountID']),
        destinationID: json['destinationID'] as String?,
        allocations: ((json['allocations'] as List?) ?? const [])
            .map((a) => Allocation.fromJson((a as Map).cast<String, Object?>()))
            .toList(),
        note: _string(json['note']),
        payee: _string(json['payee']),
        pending: _bool(json['pending']),
        legacyType: json['legacyType'] == null ? null : _int(json['legacyType']),
        needsReview: _bool(json['needsReview']),
      );
}

class Budget {
  Budget({String? id, this.categoryID, required this.limit, DateTime? month})
      : id = id ?? newId(),
        month = month == null ? null : DateTime(month.year, month.month);
  String id;
  String? categoryID;
  int limit;

  /// null: 每月预算, applies to every month. Otherwise 本月预算: only that month, where it takes the
  /// place of the every-month budget for the same scope.
  DateTime? month;

  bool appliesTo(DateTime m) => month == null || (month!.year == m.year && month!.month == m.month);

  Budget copy() => Budget(id: id, categoryID: categoryID, limit: limit, month: month);
  Map<String, Object?> toJson() => {
        if (categoryID != null) 'categoryID': categoryID,
        'id': id,
        'limit': limit,
        if (month != null) 'month': '${month!.year}-${month!.month.toString().padLeft(2, '0')}',
      };
  factory Budget.fromJson(Map<String, Object?> json) => Budget(
        id: _string(json['id']),
        categoryID: json['categoryID'] as String?,
        limit: _int(json['limit']),
        month: _budgetMonth(json['month']),
      );

  static DateTime? _budgetMonth(Object? value) {
    if (value is! String) return null;
    final parts = value.split('-');
    final year = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (year == null || month == null || month < 1 || month > 12) throw LedgerError(tr('备份中的数字字段无效。'));
    return DateTime(year, month);
  }
}

/// Original Money Pro tables kept verbatim (values as text, NULL as null). Treated as read-only.
class LegacyArchive {
  LegacyArchive({DateTime? importedAt, required this.tables, required this.warnings})
      : importedAt = importedAt ?? DateTime.now();

  final DateTime importedAt;
  final Map<String, List<Map<String, String?>>> tables;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
        'importedAt': encodeDate(importedAt),
        'tables': tables,
        'warnings': warnings,
      };

  factory LegacyArchive.fromJson(Map<String, Object?> json) {
    final rawTables = (json['tables'] as Map?) ?? const {};
    return LegacyArchive(
      importedAt: decodeDate(json['importedAt']),
      tables: {
        for (final entry in rawTables.entries)
          entry.key as String: [
            for (final row in (entry.value as List))
              {for (final cell in (row as Map).entries) cell.key as String: cell.value as String?}
          ]
      },
      warnings: ((json['warnings'] as List?) ?? const []).cast<String>(),
    );
  }
}

class Ledger {
  Ledger({
    this.schemaVersion = 1,
    this.title = '我的账本',
    List<Account>? accounts,
    List<LedgerCategory>? categories,
    List<Entry>? entries,
    List<Budget>? budgets,
    this.legacy,
  })  : accounts = accounts ?? [],
        categories = categories ?? [],
        entries = entries ?? [],
        budgets = budgets ?? [];

  int schemaVersion;
  String title;
  List<Account> accounts;
  List<LedgerCategory> categories;
  List<Entry> entries;
  List<Budget> budgets;
  LegacyArchive? legacy;

  /// Working copy for an edit. The legacy archive is shared because it is never modified.
  Ledger copy() => Ledger(
        schemaVersion: schemaVersion,
        title: title,
        accounts: accounts.map((a) => a.copy()).toList(),
        categories: categories.map((c) => c.copy()).toList(),
        entries: entries.map((e) => e.copy()).toList(),
        budgets: budgets.map((b) => b.copy()).toList(),
        legacy: legacy,
      );

  Map<String, Object?> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'budgets': budgets.map((b) => b.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        if (legacy != null) 'legacy': legacy!.toJson(),
        'schemaVersion': schemaVersion,
        'title': title,
      };

  factory Ledger.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) =>
        ((json[key] as List?) ?? const []).map((e) => (e as Map).cast<String, Object?>()).toList();
    return Ledger(
      schemaVersion: _int(json['schemaVersion'], 1),
      title: _string(json['title'], '我的账本'),
      accounts: list('accounts').map(Account.fromJson).toList(),
      categories: list('categories').map(LedgerCategory.fromJson).toList(),
      entries: list('entries').map(Entry.fromJson).toList(),
      budgets: list('budgets').map(Budget.fromJson).toList(),
      legacy: json['legacy'] == null ? null : LegacyArchive.fromJson((json['legacy'] as Map).cast<String, Object?>()),
    );
  }

  static Ledger empty() => Ledger(accounts: [
        Account(id: 'cash', name: tr('日常账户'))
      ], categories: [
        LedgerCategory(id: 'food', name: tr('餐饮'), kind: EntryKind.expense, symbol: 'utensils'),
        LedgerCategory(id: 'transport', name: tr('交通'), kind: EntryKind.expense, symbol: 'train-front'),
        LedgerCategory(id: 'shopping', name: tr('购物'), kind: EntryKind.expense, symbol: 'shopping-bag'),
        LedgerCategory(id: 'home', name: tr('居家'), kind: EntryKind.expense, symbol: 'house'),
        LedgerCategory(id: 'fun', name: tr('休闲'), kind: EntryKind.expense, symbol: 'sparkles'),
        LedgerCategory(id: 'other', name: tr('其他'), kind: EntryKind.expense, symbol: 'ellipsis'),
        LedgerCategory(id: 'salary', name: tr('工资'), kind: EntryKind.income, symbol: 'briefcase'),
        LedgerCategory(id: 'bonus', name: tr('其他收入'), kind: EntryKind.income, symbol: 'gift'),
      ]);

  static Ledger demo({DateTime? now}) {
    final today = now ?? DateTime.now();
    final ledger = empty();
    ledger.title = tr('演示账本 · 非真实数据');
    ledger.accounts[0].openingBalance = 320000;
    ledger.accounts.add(Account(id: 'bank', name: tr('储蓄账户'), openingBalance: 2400000));
    ledger.budgets = [Budget(limit: 600000), Budget(categoryID: 'food', limit: 150000)];
    final beginning = DateTime(today.year, today.month, 1, 12);
    final data = [
      (0, 'salary', 1280000, tr('月度工资')),
      (1, 'food', 3600, tr('周末早餐')),
      (2, 'transport', 2800, tr('通勤打车')),
      (3, 'shopping', 25900, tr('换季衣物')),
      (4, 'food', 12600, tr('和朋友吃晚饭')),
      (5, 'home', 18900, tr('生活用品')),
      (6, 'fun', 6800, tr('看一场电影')),
      (7, 'food', 2800, tr('咖啡与面包')),
    ];
    ledger.entries = [
      for (final (day, category, amount, note) in data)
        Entry(
          kind: category == 'salary' ? EntryKind.income : EntryKind.expense,
          amount: amount,
          date: DateTime(beginning.year, beginning.month, beginning.day + day, 12),
          accountID: category == 'salary' ? 'bank' : 'cash',
          allocations: [Allocation(categoryID: category, amount: amount)],
          note: note,
        ),
      // A couple of entries today so the default "today" view is not empty.
      Entry(
          kind: EntryKind.expense,
          amount: 3200,
          date: DateTime(today.year, today.month, today.day, 8, 30),
          accountID: 'cash',
          allocations: [Allocation(categoryID: 'food', amount: 3200)],
          note: tr('早餐')),
      Entry(
          kind: EntryKind.expense,
          amount: 600,
          date: DateTime(today.year, today.month, today.day, 9, 10),
          accountID: 'cash',
          allocations: [Allocation(categoryID: 'transport', amount: 600)],
          note: tr('地铁')),
    ];
    return ledger;
  }

  void validate() {
    if (schemaVersion != 1) throw LedgerError(tr('不支持此备份版本，不能覆盖现有账本。'));
    if (title.trim().isEmpty ||
        title.length > 100 ||
        entries.length > 100000 ||
        accounts.length > 500 ||
        categories.length > 5000 ||
        budgets.length > 500) {
      throw LedgerError(tr('账本名称或记录数量超出范围。'));
    }
    void unique(Iterable<String> ids, String label) {
      final list = ids.toList();
      if (list.any((id) => id.isEmpty) || list.toSet().length != list.length) {
        throw LedgerError(tr('{label}含重复或空编号。', {'label': label}));
      }
    }

    unique(accounts.map((a) => a.id), tr('账户'));
    unique(categories.map((c) => c.id), tr('分类'));
    unique(entries.map((e) => e.id), tr('记录'));
    unique(budgets.map((b) => b.id), tr('预算'));
    final accountIDs = accounts.map((a) => a.id).toSet();
    final categoryIDs = categories.map((c) => c.id).toSet();
    bool inRange(int value) => value >= -Money.maximum && value <= Money.maximum;
    for (final account in accounts) {
      if (!isSupportedCurrency(account.currency) || account.name.isEmpty || account.name.length > 200 || !inRange(account.openingBalance)) {
        throw LedgerError(tr('第一版只支持人民币；请检查账户名称和期初余额。'));
      }
    }
    final categoryKinds = {for (final c in categories) c.id: c.kind};
    for (final category in categories) {
      final parent = category.parentID;
      if (category.name.isEmpty ||
          category.name.length > 200 ||
          !(category.kind == EntryKind.expense || category.kind == EntryKind.income) ||
          (parent != null && !categoryIDs.contains(parent)) ||
          parent == category.id) {
        throw LedgerError(tr('分类名称、类型或父分类无效。'));
      }
    }
    for (final entry in entries) {
      final seconds = entry.date.millisecondsSinceEpoch / 1000;
      if (seconds < 0 ||
          seconds > 4102444800 ||
          !accountIDs.contains(entry.accountID) ||
          !inRange(entry.amount) ||
          entry.note.length > 10000 ||
          entry.payee.length > 1000) {
        throw LedgerError(tr('记录含无效日期、金额或账户。'));
      }
      if (entry.kind == EntryKind.transfer) {
        final destination = entry.destinationID;
        if (entry.amount <= 0 ||
            destination == null ||
            !accountIDs.contains(destination) ||
            destination == entry.accountID ||
            entry.allocations.isNotEmpty) {
          throw LedgerError(tr('转账必须有不同的转出/转入账户、正数金额，且不能参与收支分类。'));
        }
      } else if (entry.destinationID != null) {
        throw LedgerError(tr('非转账记录不能有转入账户。'));
      }
      if (entry.kind == EntryKind.adjustment && entry.allocations.isNotEmpty) {
        throw LedgerError(tr('余额调整不能计入分类收支。'));
      }
      if (entry.kind == EntryKind.income || entry.kind == EntryKind.expense) {
        final absolute = entry.allocations.fold<int>(0, (sum, a) => sum + a.amount.abs());
        final total = entry.allocations.fold<int>(0, (sum, a) => sum + a.amount);
        if (entry.allocations.isEmpty ||
            entry.allocations.length > 100 ||
            !entry.allocations.every((a) => categoryKinds[a.categoryID] == entry.kind && inRange(a.amount)) ||
            absolute > Money.maximum ||
            total != entry.amount) {
          throw LedgerError(tr('分类分摊金额必须与该笔收支一致。'));
        }
      }
    }
    final targets = <String>{};
    for (final budget in budgets) {
      final m = budget.month;
      final target = '${budget.categoryID ?? '__all__'}@${m == null ? 'every' : '${m.year}-${m.month}'}';
      if (budget.limit <= 0 ||
          budget.limit > Money.maximum ||
          !targets.add(target) ||
          (budget.categoryID != null && categoryKinds[budget.categoryID] != EntryKind.expense)) {
        throw LedgerError(tr('同一范围只能有一个每月预算，同一个月也只能有一个本月预算，金额需大于零。'));
      }
    }
  }

  int balance(String accountID) {
    var value = 0;
    for (final account in accounts) {
      if (account.id == accountID) {
        value = account.openingBalance;
        break;
      }
    }
    for (final entry in entries) {
      if (entry.pending) continue;
      var delta = 0;
      if (entry.accountID == accountID) {
        delta = entry.kind == EntryKind.expense || entry.kind == EntryKind.transfer ? -entry.amount : entry.amount;
      }
      if (entry.kind == EntryKind.transfer && entry.destinationID == accountID) delta += entry.amount;
      value += delta;
    }
    return value;
  }

  /// Booked entries in [start, end).
  List<Entry> entriesBetween(DateTime start, DateTime end) =>
      entries.where((e) => !e.pending && !e.date.isBefore(start) && e.date.isBefore(end)).toList();

  List<Entry> monthEntries(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return entriesBetween(start, end);
  }

  int total(EntryKind kind, DateTime month) =>
      monthEntries(month).where((e) => e.kind == kind).fold(0, (sum, e) => sum + e.amount);

  List<(LedgerCategory, int)> categorySpending(DateTime month) => categorySpendingIn(monthEntries(month));

  /// The ledger's currency: every account uses the same one (no conversion).
  String get currency => accounts.isEmpty ? 'CNY' : accounts.first.currency;

  // MARK: Category hierarchy (Money Pro has two levels, e.g. 住宅 › 租金)

  LedgerCategory? categoryByID(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Direct subcategories of [id], in ledger order.
  List<LedgerCategory> childrenOf(String id) => [for (final c in categories) if (c.parentID == id) c];

  /// [id] and every category below it.
  Set<String> subtreeIDs(String id) {
    final result = {id};
    var added = true;
    while (added) {
      added = false;
      for (final c in categories) {
        if (c.parentID != null && result.contains(c.parentID) && result.add(c.id)) added = true;
      }
    }
    return result;
  }

  /// The top-level category [id] belongs to (itself when it has no parent).
  String topLevelID(String id) {
    var current = id;
    for (var depth = 0; depth < 10; depth++) {
      final parent = categoryByID(current)?.parentID;
      if (parent == null || categoryByID(parent) == null) return current;
      current = parent;
    }
    return current;
  }

  /// Like [categorySpendingIn], but each subcategory's spending is added to its top-level category.
  List<(LedgerCategory, int)> topLevelSpendingIn(List<Entry> list) {
    final values = <String, int>{};
    for (final (category, value) in categorySpendingIn(list)) {
      final top = topLevelID(category.id);
      values[top] = (values[top] ?? 0) + value;
    }
    final result = [for (final c in categories) if ((values[c.id] ?? 0) != 0) (c, values[c.id]!)];
    result.sort((a, b) => b.$2.compareTo(a.$2));
    return result;
  }

  List<(LedgerCategory, int)> categorySpendingIn(List<Entry> list) {
    final values = <String, int>{};
    for (final entry in list) {
      if (entry.kind != EntryKind.expense) continue;
      for (final allocation in entry.allocations) {
        values[allocation.categoryID] = (values[allocation.categoryID] ?? 0) + allocation.amount;
      }
    }
    final result = [
      for (final c in categories)
        if (c.kind == EntryKind.expense && (values[c.id] ?? 0) != 0) (c, values[c.id]!)
    ];
    result.sort((a, b) => b.$2.compareTo(a.$2));
    return result;
  }

  /// The budget in force for [categoryID] (null = all spending) in [month]: that month's 本月预算 if
  /// there is one, otherwise the 每月预算.
  Budget? budgetFor(String? categoryID, DateTime month) {
    Budget? recurring;
    for (final budget in budgets) {
      if (budget.categoryID != categoryID || !budget.appliesTo(month)) continue;
      if (budget.month != null) return budget;
      recurring = budget;
    }
    return recurring;
  }

  /// One budget per scope for [month], as [budgetFor] picks them.
  List<Budget> budgetsFor(DateTime month) {
    final scopes = {for (final b in budgets) b.categoryID};
    return [
      for (final scope in scopes)
        if (budgetFor(scope, month) case final budget?) budget
    ];
  }

  int spent(Budget budget, DateTime month) {
    final category = budget.categoryID;
    if (category == null) return total(EntryKind.expense, month);
    // A budget on a parent category covers its subcategories too.
    final ids = subtreeIDs(category);
    var sum = 0;
    for (final entry in monthEntries(month)) {
      if (entry.kind != EntryKind.expense) continue;
      for (final allocation in entry.allocations) {
        if (ids.contains(allocation.categoryID)) sum += allocation.amount;
      }
    }
    return sum;
  }
}
