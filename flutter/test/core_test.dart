import 'dart:convert';
import 'dart:io';

import 'package:centwise/core/models.dart';
import 'package:centwise/core/money.dart';
import 'package:centwise/core/money_pro_importer.dart';
import 'package:centwise/core/repository.dart';
import 'package:flutter_test/flutter_test.dart';

Ledger sample() {
  final ledger = Ledger.empty();
  ledger.accounts[0].openingBalance = 100000;
  ledger.accounts.add(Account(id: 'bank', name: '银行卡', openingBalance: 200000));
  return ledger;
}

/// Canonical form (sorted keys) so equality does not depend on map insertion order.
String json(Ledger ledger) => utf8.decode(LedgerCodec.encode(ledger));

void main() {
  test('amounts are exact', () {
    expect(Money.parse('0.10') + Money.parse('0.20'), 30);
    expect(Money.parse('-26.14'), -2614);
    expect(Money.parse(' 12800.01 '), 1280001);
    expect(() => Money.parse('1.001'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('NaN'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('1,000'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('999999999999999999999999'), throwsA(isA<LedgerError>()));
    // Keypad calculations: × ÷ before + −, exact rationals, rounded half away from zero to fen.
    expect(Money.parse('12.5+8×2'), 2850);
    expect(Money.parse('0.1+0.2'), 30);
    expect(Money.parse('10÷3'), 333);
    expect(Money.parse('2-5'), -300);
    expect(Money.parse('-12.5×2'), -2500);
    expect(() => Money.parse('1+'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('1×'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('-'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('5÷0'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('+5'), throwsA(isA<LedgerError>()));
    expect(() => Money.parse('1.2.3'), throwsA(isA<LedgerError>()));
    expect(Money.legacy('26.140000000000001'), 2614);
    expect(Money.legacy('1e-7'), 0);
    expect(() => Money.legacy('1.2345'), throwsA(isA<LedgerError>()));
    expect(Money.text(123456), '¥1,234.56');
    expect(Money.text(-5, symbol: false), '-0.05');
    expect(Money.input(1230), '12.3');
    expect(Money.input(-2614), '-26.14');
    expect(Money.input(0), '0');
  });

  test('transfers do not inflate income or expense', () {
    final ledger = sample();
    ledger.entries = [Entry(kind: EntryKind.transfer, amount: 12345, accountID: 'cash', destinationID: 'bank')];
    ledger.validate();
    expect(ledger.balance('cash'), 87655);
    expect(ledger.balance('bank'), 212345);
    expect(ledger.total(EntryKind.income, DateTime.now()), 0);
    expect(ledger.total(EntryKind.expense, DateTime.now()), 0);
  });

  test('pending does not affect posted balance', () {
    final ledger = sample();
    ledger.entries = [
      Entry(kind: EntryKind.expense, amount: 10000, accountID: 'cash', allocations: [Allocation(categoryID: 'food', amount: 10000)], pending: true)
    ];
    ledger.validate();
    expect(ledger.balance('cash'), 100000);
    expect(ledger.total(EntryKind.expense, DateTime.now()), 0);
  });

  test('refunds reduce expense and adjustments are not income', () {
    final ledger = sample();
    ledger.entries = [
      Entry(kind: EntryKind.expense, amount: -1200, accountID: 'cash', allocations: [Allocation(categoryID: 'food', amount: -1200)]),
      Entry(kind: EntryKind.adjustment, amount: -500, accountID: 'cash'),
    ];
    ledger.validate();
    expect(ledger.balance('cash'), 100700);
    expect(ledger.total(EntryKind.expense, DateTime.now()), -1200);
    expect(ledger.total(EntryKind.income, DateTime.now()), 0);
  });

  test('split allocations are preserved and checked', () {
    final ledger = sample();
    ledger.entries = [
      Entry(kind: EntryKind.expense, amount: 3000, accountID: 'cash', allocations: [
        Allocation(categoryID: 'food', amount: 1200),
        Allocation(categoryID: 'home', amount: 1800),
      ])
    ];
    ledger.validate();
    expect(ledger.spent(Budget(categoryID: 'food', limit: 10000), DateTime.now()), 1200);
    expect(ledger.spent(Budget(limit: 10000), DateTime.now()), 3000);
    ledger.entries[0].allocations[0].amount = 1201;
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger.entries[0].amount = 0;
    ledger.entries[0].allocations = [
      Allocation(categoryID: 'food', amount: Money.maximum),
      Allocation(categoryID: 'home', amount: -Money.maximum),
    ];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
  });

  test('invalid dates are rejected', () {
    final ledger = sample();
    ledger.entries = [Entry(kind: EntryKind.adjustment, amount: 0, date: DateTime.fromMillisecondsSinceEpoch(-100000), accountID: 'cash')];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    expect(() => decodeDate(double.nan), throwsA(isA<LedgerError>()));
    expect(() => decodeDate(double.infinity), throwsA(isA<LedgerError>()));
  });

  test('duplicate ids and bad references are rejected', () {
    var ledger = sample();
    ledger.accounts.add(ledger.accounts[0].copy());
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger = sample();
    ledger.entries = [Entry(kind: EntryKind.transfer, amount: 100, accountID: 'cash', destinationID: 'cash')];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger.entries[0].destinationID = 'missing';
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger = sample();
    ledger.entries = [
      Entry(kind: EntryKind.expense, amount: 100, accountID: 'cash', allocations: [Allocation(categoryID: 'salary', amount: 100)])
    ];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
  });

  test('duplicate budgets and foreign currency are rejected', () {
    final ledger = sample();
    ledger.budgets = [Budget(limit: 100), Budget(limit: 200)];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger.budgets = [Budget(categoryID: 'salary', limit: 100)];
    expect(ledger.validate, throwsA(isA<LedgerError>()));
    ledger.budgets = [];
    ledger.accounts[0].currency = 'USD';
    expect(ledger.validate, throwsA(isA<LedgerError>()));
  });

  test('month boundaries are half open', () {
    final start = DateTime(2026, 10, 1);
    final end = DateTime(2026, 11, 1);
    final ledger = sample();
    ledger.entries = [
      Entry(id: 'first', kind: EntryKind.adjustment, amount: 0, date: start, accountID: 'cash'),
      Entry(id: 'last', kind: EntryKind.adjustment, amount: 0, date: end.subtract(const Duration(seconds: 1)), accountID: 'cash'),
      Entry(id: 'next', kind: EntryKind.adjustment, amount: 0, date: end, accountID: 'cash'),
    ];
    ledger.validate();
    expect(ledger.monthEntries(start).map((e) => e.id).toSet(), {'first', 'last'});
  });

  test('backup round trip preserves all fields', () {
    final ledger = Ledger.demo();
    ledger.legacy = LegacyArchive(tables: {
      'extra': [
        {'nullable': null, 'amount': '0.10'}
      ]
    }, warnings: ['保留原始字段']);
    final decoded = LedgerCodec.decode(LedgerCodec.encode(ledger));
    expect(json(decoded), json(ledger));
    ledger.schemaVersion = 2;
    expect(() => LedgerCodec.encode(ledger), throwsA(isA<LedgerError>()));
  });

  test('reads a backup written by the SwiftUI version', () {
    // Shape of a .qingledger file: sorted keys, dates as seconds since 2001-01-01, optional keys omitted.
    const swiftBackup = '''
{
  "accounts" : [ { "archived" : false, "currency" : "CNY", "id" : "cash", "name" : "日常账户", "openingBalance" : 100000 } ],
  "budgets" : [ { "id" : "B1", "limit" : 600000 } ],
  "categories" : [ { "id" : "food", "kind" : "expense", "name" : "餐饮", "symbol" : "fork.knife" } ],
  "entries" : [ {
    "accountID" : "cash",
    "allocations" : [ { "amount" : 3600, "categoryID" : "food" } ],
    "amount" : 3600,
    "date" : 781920000.5,
    "id" : "E1",
    "kind" : "expense",
    "needsReview" : false,
    "note" : "早餐",
    "payee" : "",
    "pending" : false
  } ],
  "schemaVersion" : 1,
  "title" : "我的账本"
}''';
    final ledger = LedgerCodec.decode(utf8.encode(swiftBackup));
    expect(ledger.entries.single.amount, 3600);
    expect(ledger.entries.single.date.toUtc(), DateTime.utc(2025, 10, 12, 0, 0, 0, 500));
    expect(ledger.categories.single.symbol, 'fork.knife');
    final reencoded = jsonDecode(utf8.decode(LedgerCodec.encode(ledger))) as Map<String, dynamic>;
    expect((reencoded['entries'] as List).single['date'], closeTo(781920000.5, 1e-6));
    expect((reencoded['entries'] as List).single.containsKey('destinationID'), isFalse);
  });

  test('repository creates snapshots and a failed save leaves the original', () {
    final directory = Directory.systemTemp.createTempSync('centwise-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final repository = LedgerRepository(directory);
    expect(repository.load(), isNull);
    final ledger = sample();
    repository.save(ledger);
    ledger.title = '修改后';
    repository.save(ledger);
    expect(repository.load()?.title, '修改后');
    final backups = repository.backups.listSync().whereType<File>().toList();
    expect(backups.length, 2);
    final daily = backups.firstWhere((f) => f.path.contains('daily-'));
    expect(LedgerCodec.decode(daily.readAsBytesSync()).title, '我的账本');
    ledger.entries = [Entry(kind: EntryKind.transfer, amount: -1, accountID: 'cash', destinationID: 'bank')];
    expect(() => repository.save(ledger), throwsA(isA<LedgerError>()));
    expect(repository.load()?.title, '修改后');
    final replacement = sample()..title = '导入替换';
    repository.save(replacement, preserveImportSnapshot: true);
    final afterImport = repository.backups.listSync().whereType<File>().toList();
    expect(afterImport.length, 3);
    final importBackup = afterImport.firstWhere((f) => f.uri.pathSegments.last.startsWith('before-import-'));
    expect(LedgerCodec.decode(importBackup.readAsBytesSync()).title, '修改后');
  });

  test('corrupted backup is not silently replaced', () {
    expect(() => LedgerCodec.decode(utf8.encode('not a ledger')), throwsA(isA<LedgerError>()));
  });

  test('new export cannot overwrite an existing file', () {
    final directory = Directory.systemTemp.createTempSync('centwise-export-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/backup.centwise';
    LedgerFiles.createNew(utf8.encode('original'), path);
    expect(() => LedgerFiles.createNew(utf8.encode('replacement'), path), throwsA(isA<LedgerError>()));
    expect(File(path).readAsStringSync(), 'original');
    expect(directory.listSync().map((e) => e.uri.pathSegments.last).toList(), ['backup.centwise']);
  });

  test('subscriptions: monthly average, this month, month-end days, codec', () {
    final ledger = sample();
    expect(ledger.toJson().containsKey('subscriptions'), isFalse); // old files stay unchanged
    ledger.subscriptions = [
      Subscription(name: 'A', amount: 3000, nextDate: DateTime(2026, 10, 31)),
      Subscription(name: 'B', amount: 9000, cycle: BillingCycle.quarterly, nextDate: DateTime(2026, 11, 5)),
      Subscription(name: 'C', amount: 12000, cycle: BillingCycle.yearly, nextDate: DateTime(2027, 3, 1)),
      Subscription(name: 'D', amount: 5000, nextDate: DateTime(2026, 10, 1), cancelled: true),
    ];
    // 30 + 90/3 + 120/12 = 70; the cancelled one doesn't count.
    expect(ledger.subscriptionMonthlyAverage, 7000);
    // Monthly on the 31st: Nov 30, then back to Dec 31.
    final a = ledger.subscriptions[0];
    expect(a.after(a.nextDate), DateTime(2026, 11, 30));
    expect(a.after(a.after(a.nextDate)), DateTime(2026, 12, 31));
    // November: A on the 30th, B on the 5th.
    expect(ledger.subscriptionChargesIn(DateTime(2026, 11)), 12000);
    // A charge already booked this month still counts, and is never counted twice.
    a.charged.add('2026-10-31');
    expect(ledger.subscriptionChargesIn(DateTime(2026, 10)), 3000);
    final decoded = LedgerCodec.decode(LedgerCodec.encode(ledger));
    expect(json(decoded), json(ledger));
    expect(decoded.subscriptions[0].anchorDay, 31);
    expect(decoded.subscriptions[3].cancelled, isTrue);
  });

  /// Opt-in integration check with a local Money Pro database; real data is never a fixture.
  test('actual Money Pro migration when provided', () {
    final path = Platform.environment['CENTWISE_LEGACY_DB'];
    if (path == null) return;
    final before = File(path).readAsBytesSync();
    final (ledger, summary) = MoneyProImporter.read(path);
    expect(summary.sourceActiveEntries, 4674);
    expect(summary.importedEntries, 4674);
    expect(summary.reviewedEntries, 2);
    expect(ledger.entries.where((e) => e.kind == EntryKind.expense).length, 4618);
    expect(ledger.entries.where((e) => e.kind == EntryKind.income).length, 55);
    expect(File(path).readAsBytesSync(), before);
    expect(json(LedgerCodec.decode(LedgerCodec.encode(ledger))), json(ledger));
  });
}
