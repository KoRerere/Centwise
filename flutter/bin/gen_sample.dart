// 生成虚拟账本（非真实数据），用于在手机上预览界面：
//   dart run bin/gen_sample.dart /path/out.centwise
// 约 4 个月的日常记录，固定随机种子，每次生成内容相同（日期以运行当天为准）。
import 'dart:io';
import 'dart:math';

import 'package:centwise/core/models.dart';
import 'package:centwise/core/repository.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('用法：dart run bin/gen_sample.dart /path/out.centwise');
    exitCode = 1;
    return;
  }
  final rnd = Random(20261019);
  final now = DateTime.now();
  final ledger = Ledger.empty();
  ledger.title = '虚拟账本 · 非真实数据';
  ledger.accounts
    ..[0].name = '微信零钱'
    ..[0].openingBalance = 260000
    ..add(Account(id: 'bank', name: '招商银行储蓄卡', openingBalance: 4580000))
    ..add(Account(id: 'credit', name: '信用卡', openingBalance: 0));
  ledger.categories.addAll([
    LedgerCategory(id: 'coffee', name: '咖啡', kind: EntryKind.expense, symbol: 'coffee', parentID: 'food'),
    LedgerCategory(id: 'takeout', name: '外卖', kind: EntryKind.expense, symbol: 'hamburger', parentID: 'food'),
    LedgerCategory(id: 'groceries', name: '买菜', kind: EntryKind.expense, symbol: 'shopping-basket', parentID: 'food'),
    LedgerCategory(id: 'taxi', name: '打车', kind: EntryKind.expense, symbol: 'car', parentID: 'transport'),
    LedgerCategory(id: 'rent', name: '房租', kind: EntryKind.expense, symbol: 'landmark', parentID: 'home'),
    LedgerCategory(id: 'utilities', name: '水电燃气', kind: EntryKind.expense, symbol: 'zap', parentID: 'home'),
    LedgerCategory(id: 'phone', name: '话费网费', kind: EntryKind.expense, symbol: 'smartphone'),
    LedgerCategory(id: 'subs', name: '会员订阅', kind: EntryKind.expense, symbol: 'tv'),
    LedgerCategory(id: 'health', name: '医疗', kind: EntryKind.expense, symbol: 'pill'),
    LedgerCategory(id: 'pet', name: '宠物', kind: EntryKind.expense, symbol: 'dog'),
    LedgerCategory(id: 'travel', name: '旅行', kind: EntryKind.expense, symbol: 'plane'),
    LedgerCategory(id: 'freelance', name: '副业', kind: EntryKind.income, symbol: 'laptop'),
  ]);
  ledger.budgets = [
    Budget(limit: 1200000),
    Budget(categoryID: 'food', limit: 300000),
    Budget(categoryID: 'shopping', limit: 150000),
    Budget(categoryID: 'fun', limit: 80000),
  ];

  final entries = <Entry>[];
  int around(int cents, [double spread = 0.35]) {
    final v = cents * (1 + (rnd.nextDouble() * 2 - 1) * spread);
    return max(100, (v / 10).round() * 10);
  }

  T pick<T>(List<T> list) => list[rnd.nextInt(list.length)];
  void add(String cat, int amount, DateTime date, String note,
      {String account = 'cash', EntryKind kind = EntryKind.expense, String payee = ''}) {
    if (date.isAfter(now)) return;
    entries.add(Entry(
      kind: kind,
      amount: amount,
      date: date,
      accountID: account,
      allocations: [Allocation(categoryID: cat, amount: amount)],
      note: note,
      payee: payee,
    ));
  }

  DateTime at(DateTime d, int h, [int? m]) => DateTime(d.year, d.month, d.day, h, m ?? rnd.nextInt(60));
  final start = DateTime(now.year, now.month - 3, 1);
  for (var d = start; !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
    final weekend = d.weekday >= 6;
    // 每月固定项
    if (d.day == 1) add('rent', 450000, at(d, 10, 0), '月租', account: 'bank', payee: '房东');
    if (d.day == 10) {
      add('salary', 1850000, at(d, 9, 30), '月度工资', account: 'bank', kind: EntryKind.income, payee: '公司');
    }
    if (d.day == 5) add('phone', 12800, at(d, 11), '手机套餐 + 宽带', account: 'bank', payee: '中国移动');
    if (d.day == 8) add('subs', pick([2500, 3000, 1500]), at(d, 20), pick(['视频会员', '音乐会员', 'iCloud 存储']), account: 'credit');
    if (d.day == 15) add('utilities', around(26000), at(d, 19), '水电燃气费', account: 'bank');
    if (d.day == 20 && rnd.nextBool()) {
      add('freelance', around(300000, 0.4), at(d, 16), '设计外包', account: 'bank', kind: EntryKind.income);
    }
    // 日常
    if (!weekend) {
      if (rnd.nextDouble() < 0.7) add('food', around(1200), at(d, 8), pick(['早餐', '包子豆浆', '便利店早餐']));
      add(rnd.nextDouble() < 0.5 ? 'takeout' : 'food', around(2800), at(d, 12), pick(['午饭', '公司楼下', '外卖午餐', '轻食']));
      if (rnd.nextDouble() < 0.55) add('coffee', around(2600, 0.2), at(d, 14), pick(['拿铁', '美式', '咖啡']));
      add('transport', 400 * (1 + rnd.nextInt(2)), at(d, 18), '地铁');
      if (rnd.nextDouble() < 0.15) add('taxi', around(3500), at(d, 22), '加班打车');
    } else {
      if (rnd.nextDouble() < 0.6) add('food', around(9000, 0.5), at(d, 13), pick(['和朋友聚餐', '火锅', '日料', '周末早午餐']), account: 'credit');
      if (rnd.nextDouble() < 0.6) add('groceries', around(12000), at(d, 17), pick(['超市采购', '买菜', '水果']));
      if (rnd.nextDouble() < 0.35) add('fun', around(8000, 0.5), at(d, 20), pick(['看电影', 'KTV', '展览门票', '桌游']), account: 'credit');
      if (rnd.nextDouble() < 0.3) add('taxi', around(4000), at(d, 21), '打车回家');
    }
    if (rnd.nextDouble() < 0.12) add('shopping', around(22000, 0.7), at(d, 21), pick(['衣服', '日用品', '数码配件', '书', '护肤品']), account: 'credit');
    if (rnd.nextDouble() < 0.06) add('pet', around(15000, 0.5), at(d, 19), pick(['猫粮', '猫砂', '宠物零食']));
    if (rnd.nextDouble() < 0.03) add('health', around(9000, 0.6), at(d, 15), pick(['药店', '体检', '看牙']), account: 'bank');
    if (d.day == 27 && d.month == now.month - 1) {
      add('travel', 168000, at(d, 10), '周末短途旅行机票酒店', account: 'credit');
    }
  }
  entries.sort((a, b) => a.date.compareTo(b.date));
  ledger.entries = entries;
  ledger.validate();
  final out = File(args[0]);
  if (out.existsSync()) out.deleteSync();
  LedgerFiles.createNew(LedgerCodec.encode(ledger), out.path);
  stdout.writeln('已生成 ${entries.length} 笔记录 → ${out.path}');
}
