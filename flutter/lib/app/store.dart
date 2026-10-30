import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/currency.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/money_pro_back.dart';
import '../core/money_pro_importer.dart';
import '../core/repository.dart';
import '../l10n/l10n.dart';

enum Period { day, month, year }

class MonthTotal {
  MonthTotal(this.month, this.income, this.expense);
  final DateTime month;
  final int income;
  final int expense;
}

/// App state: the ledger, the selected period, persistence and import.
class LedgerStore extends ChangeNotifier with WidgetsBindingObserver {
  LedgerStore._(this.repository, this.isDemo, this._ledger) {
    _syncCurrency();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _undoTimer?.cancel();
    super.dispose();
  }

  final LedgerRepository? repository;
  final bool isDemo;

  /// Amounts everywhere draw [Money.symbol]; keep it on the ledger's currency.
  void _syncCurrency() => Money.symbol = currencyFor(_ledger.currency).symbol;

  /// Keeps the ledger in [code]: every account switches to it. Amounts are not converted.
  bool setCurrency(String code) => commit((ledger) {
        for (final account in ledger.accounts) {
          account.currency = code;
        }
      });
  Ledger _ledger;
  Ledger get ledger => _ledger;

  String? error;
  bool loadingFailed = false;

  /// Signed-in account for iCloud sync. Real Apple sign-in / iCloud sync is not wired up yet;
  /// only the demo build simulates a signed-in account so the screens can be previewed.
  AccountInfo? account;
  Ledger? pendingImport;
  String importDescription = '';

  /// Anchor date of the selected period.
  DateTime month = DateTime.now();

  /// Default timeline is today; the bottom capsule switches between today, this month and the last 12 months.
  Period period = Period.day;

  static const bool _demoDefine = bool.fromEnvironment('CENTWISE_DEMO');

  /// 设置 → 外观 → 深色模式. Saved in preferences.json next to (not inside) the ledger, also in demo mode.
  ThemeMode themeMode = ThemeMode.system;

  /// 设置 → 语言. The resolved language lives in [L10n.current].
  LanguagePref languagePref = LanguagePref.system;

  /// Where the floating 记一笔 button was dragged to, as fractions of the free area (null = default corner).
  Offset? addButtonPosition;
  File? _preferencesFile;

  static Future<LedgerStore> open() async {
    // Preferences first, so a new ledger's default account and categories use the chosen language.
    File? file;
    var theme = ThemeMode.system;
    var language = LanguagePref.system;
    Offset? addButton;
    try {
      final support = await getApplicationSupportDirectory();
      file = File('${support.path}/Centwise/preferences.json');
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync());
        if (json is Map) {
          theme = ThemeMode.values.firstWhere((m) => m.name == json['themeMode'], orElse: () => ThemeMode.system);
          language = LanguagePref.values.firstWhere((l) => l.name == json['language'], orElse: () => LanguagePref.system);
          final button = json['addButton'];
          if (button is List && button.length == 2 && button.every((v) => v is num)) {
            addButton = Offset((button[0] as num).toDouble().clamp(0, 1), (button[1] as num).toDouble().clamp(0, 1));
          }
        }
      }
    } catch (_) {
      // Preferences are optional; fall back to defaults.
    }
    _applyLanguage(language);
    final store = await _openLedger();
    store
      .._preferencesFile = file
      ..themeMode = theme
      ..languagePref = language
      ..addButtonPosition = addButton;
    return store;
  }

  static void _applyLanguage(LanguagePref pref) {
    final locale = PlatformDispatcher.instance.locale;
    L10n.current = L10n.resolve(pref,
        languageCode: locale.languageCode, scriptCode: locale.scriptCode, countryCode: locale.countryCode);
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    _savePreferences();
  }

  void setLanguage(LanguagePref pref) {
    languagePref = pref;
    _applyLanguage(pref);
    notifyListeners();
    _savePreferences();
    // Text is translated when built; rebuild everything, including widgets that don't listen to the store.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }
    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  void setAddButtonPosition(Offset fraction) {
    addButtonPosition = fraction;
    _savePreferences();
  }

  void _savePreferences() {
    final file = _preferencesFile;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      final button = addButtonPosition;
      file.writeAsStringSync(jsonEncode({
        'themeMode': themeMode.name,
        'language': languagePref.name,
        if (button != null) 'addButton': [button.dx, button.dy],
      }));
    } catch (_) {
      // Not worth interrupting the user; the choice still applies for this session.
    }
  }

  static Future<LedgerStore> _openLedger() async {
    final demo = _demoDefine || Platform.environment['CENTWISE_DEMO'] == '1';
    if (demo) return LedgerStore._(null, true, Ledger.demo());
    final base = Platform.isIOS ? await getApplicationDocumentsDirectory() : await getApplicationSupportDirectory();
    final repository = LedgerRepository(Directory('${base.path}/Centwise'));
    try {
      final loaded = repository.load();
      return LedgerStore._(repository, false, loaded ?? Ledger.empty());
    } catch (e) {
      final store = LedgerStore._(repository, false, Ledger.empty());
      store.error = tr('账本读取失败：{error}\n原文件已保留，暂停所有写入。请导入已核对的备份。', {'error': e});
      store.loadingFailed = true;
      return store;
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  /// Applies [change] to a copy, validates and saves it; the visible ledger only changes on success.
  bool commit(void Function(Ledger ledger) change) {
    if (loadingFailed) {
      error = tr('读取失败期间禁止修改账本，请先恢复备份。');
      notifyListeners();
      return false;
    }
    try {
      final next = _ledger.copy();
      change(next);
      next.validate();
      if (!isDemo) repository!.save(next);
      _ledger = next;
      _syncCurrency();
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  bool save(Entry entry) => commit((ledger) {
        final index = ledger.entries.indexWhere((e) => e.id == entry.id);
        if (index >= 0) {
          ledger.entries[index] = entry;
        } else {
          ledger.entries.add(entry);
        }
      });

  // MARK: Hidden default account

  /// The account new bills are booked to: the first one that isn't archived. Accounts are no longer
  /// shown in the app, so when there is none, a default one is added quietly in the ledger's currency.
  /// Old entries keep the accounts they were booked to.
  static String defaultAccountIn(Ledger ledger) {
    for (final account in ledger.accounts) {
      if (!account.archived) return account.id;
    }
    final account = Account(name: tr('日常账户'), currency: ledger.currency);
    ledger.accounts.add(account);
    return account.id;
  }

  /// [defaultAccountIn] for the live ledger, saving the new account when one had to be added.
  /// Null when the ledger can't be written.
  String? defaultAccountID() {
    for (final account in _ledger.accounts) {
      if (!account.archived) return account.id;
    }
    String? id;
    return commit((ledger) => id = defaultAccountIn(ledger)) ? id : null;
  }

  // MARK: Subscriptions

  static Subscription _subscriptionIn(Ledger ledger, String id) {
    for (final s in ledger.subscriptions) {
      if (s.id == id) return s;
    }
    throw LedgerError(tr('找不到这个订阅。'));
  }

  bool saveSubscription(Subscription subscription) => commit((ledger) {
        final index = ledger.subscriptions.indexWhere((s) => s.id == subscription.id);
        if (index >= 0) {
          ledger.subscriptions[index] = subscription;
        } else {
          ledger.subscriptions.add(subscription);
        }
      });

  /// Stops future charges. Bills already booked from it stay in the ledger.
  bool cancelSubscription(String id) => commit((ledger) {
        final s = _subscriptionIn(ledger, id);
        s.cancelled = true;
        s.cancelledAt = DateTime.now();
      });

  /// Starts a cancelled subscription again. If its next charge day has passed meanwhile, it moves on
  /// to the first charge day from today; the missed ones are not booked.
  bool resumeSubscription(String id) => commit((ledger) {
        final s = _subscriptionIn(ledger, id);
        s.cancelled = false;
        s.cancelledAt = null;
        final today = _dateOnly(DateTime.now());
        for (var guard = 0; guard < 400 && s.nextDate.isBefore(today); guard++) {
          s.nextDate = s.after(s.nextDate);
        }
      });

  /// Confirms the charge that is due: books one expense on its charge day and moves the subscription
  /// on to the next cycle, in one save. A day that was already booked is never booked again.
  bool confirmSubscriptionCharge(String id) => commit((ledger) {
        final s = _subscriptionIn(ledger, id);
        final now = DateTime.now();
        if (!s.isDue(now)) throw LedgerError(tr('这一期还没到扣费日期。'));
        final key = dayKey(s.nextDate);
        if (!s.charged.contains(key)) {
          final day = s.nextDate;
          ledger.entries.add(Entry(
            kind: EntryKind.expense,
            amount: s.amount,
            // Today's charge gets the current time (so it lists with today's bills in order); an
            // older one is booked at noon of its own charge day.
            date: _dateOnly(now) == day ? now : DateTime(day.year, day.month, day.day, 12),
            accountID: defaultAccountIn(ledger),
            allocations: [Allocation(categoryID: _subscriptionCategoryIn(ledger, s), amount: s.amount)],
            note: s.note.trim().isEmpty ? s.name : '${s.name} · ${s.note.trim()}',
            payee: s.name,
          ));
          s.charged.add(key);
        }
        s.nextDate = s.after(s.nextDate);
      });

  /// Skips the due charge without booking anything (e.g. a free month), moving on to the next cycle.
  bool skipSubscriptionCharge(String id) => commit((ledger) {
        final s = _subscriptionIn(ledger, id);
        if (!s.isDue(DateTime.now())) throw LedgerError(tr('这一期还没到扣费日期。'));
        s.nextDate = s.after(s.nextDate);
      });

  /// The subscription's own expense category, or 其他 (added to [ledger] the first time) when it has
  /// none or it was deleted.
  static String _subscriptionCategoryIn(Ledger ledger, Subscription s) {
    final own = s.categoryID == null ? null : ledger.categoryByID(s.categoryID!);
    if (own != null && own.kind == EntryKind.expense) return own.id;
    final other = _otherCategoryIn(ledger, EntryKind.expense);
    if (other != null) return other.id;
    final created = LedgerCategory(name: tr('其他'), kind: EntryKind.expense, symbol: 'ellipsis');
    ledger.categories.add(created);
    return created.id;
  }

  void prepareImport(String path) {
    try {
      final lower = path.toLowerCase();
      final Ledger next;
      if (lower.endsWith('.sql') || lower.endsWith('.sqlite') || lower.endsWith('.back')) {
        // A Money Pro .back backup wraps the same database; unpack it to a temporary folder first.
        Directory? unpacked;
        var source = path;
        if (lower.endsWith('.back')) {
          unpacked = Directory('${Directory.systemTemp.path}/centwise-back-${DateTime.now().microsecondsSinceEpoch}');
          source = extractMoneyProBack(path, unpacked).path;
        }
        final (ledger, summary) = MoneyProImporter.read(source);
        try {
          unpacked?.deleteSync(recursive: true);
        } catch (_) {}
        next = ledger;
        importDescription = '${tr('Money Pro：{entries} 条记录、{accounts} 个账户、{categories} 个分类。', {'entries': summary.importedEntries, 'accounts': summary.accounts, 'categories': summary.categories})}\n'
            '${summary.warnings.join('\n')}';
      } else {
        next = LedgerCodec.decode(File(path).readAsBytesSync());
        final buffer = StringBuffer(tr('{title}：{entries} 条记录、{accounts} 个账户。', {'title': next.title, 'entries': next.entries.length, 'accounts': next.accounts.length}));
        final review = next.entries.where((e) => e.needsReview).length;
        if (review > 0) buffer.write('\n${tr('{n} 条记录需要核对。', {'n': review})}');
        final warnings = next.legacy?.warnings;
        if (warnings != null && warnings.isNotEmpty) buffer.write('\n${warnings.join('\n')}');
        importDescription = buffer.toString();
      }
      pendingImport = next;
    } catch (e) {
      error = tr('导入失败，当前账本未改动：{error}', {'error': e});
    }
    notifyListeners();
  }

  /// Import inbox: a Money Pro database or Centwise backup placed in `<data folder>/Import/` (on iPhone
  /// also the top of Documents, where Finder file sharing puts files) is opened in the import preview at launch, then moved to
  /// `Import/Done/` so it isn't offered again. Nothing is written until the preview is confirmed.
  void scanImportFolder() {
    final repo = repository;
    if (repo == null || pendingImport != null) return;
    final inbox = Directory('${repo.directory.path}/Import');
    const types = ['.sql', '.sqlite', '.back', '.centwise', '.qingledger'];
    List<File> candidates(Directory dir) => dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => types.any(f.path.toLowerCase().endsWith)).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    // On iPhone, Finder file sharing drops files at the top of the app's Documents folder.
    final files = [...candidates(inbox), if (Platform.isIOS) ...candidates(repo.directory.parent)];
    if (files.isEmpty) return;
    final file = files.first;
    prepareImport(file.path);
    try {
      final done = Directory('${inbox.path}/Done')..createSync(recursive: true);
      file.renameSync('${done.path}/${DateTime.now().millisecondsSinceEpoch}-${file.uri.pathSegments.last}');
    } catch (_) {
      // Leaving the file in place only means it is offered again next launch.
    }
  }

  // MARK: Delete with undo

  /// Entries deleted in the last few seconds that "撤销" would bring back (newest last).
  /// Several deletes in a row share one undo; the window restarts with each delete.
  final List<Entry> recentlyDeleted = [];
  Timer? _undoTimer;
  static const Duration undoWindow = Duration(seconds: 5);

  /// Deletes [entry] and offers "已删除账单 · 撤销" for [undoWindow].
  bool deleteEntry(Entry entry) {
    final ok = commit((ledger) => ledger.entries.removeWhere((e) => e.id == entry.id));
    if (ok) {
      recentlyDeleted.add(entry);
      _undoTimer?.cancel();
      _undoTimer = Timer(undoWindow, dismissUndo);
      notifyListeners();
    }
    return ok;
  }

  /// Puts every entry from the current undo window back. Balances and reports are computed from the
  /// entries, so they come back with them.
  bool undoDelete() {
    if (recentlyDeleted.isEmpty) return false;
    final restore = List<Entry>.of(recentlyDeleted);
    _undoTimer?.cancel();
    recentlyDeleted.clear();
    final ok = commit((ledger) {
      for (final entry in restore) {
        if (!ledger.entries.any((e) => e.id == entry.id)) ledger.entries.add(entry);
      }
    });
    if (!ok) notifyListeners();
    return ok;
  }

  void dismissUndo() {
    _undoTimer?.cancel();
    if (recentlyDeleted.isEmpty) return;
    recentlyDeleted.clear();
    notifyListeners();
  }

  // MARK: Day change (midnight, or coming back to the app on a later day)

  DateTime _today = _dateOnly(DateTime.now());
  Timer? _midnightTimer;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    _midnightTimer = Timer(next.difference(now), () {
      refreshDay();
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        refreshDay();
        _scheduleMidnight();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // An undo offer shouldn't survive leaving the app.
        dismissUndo();
      default:
        break;
    }
  }

  /// When the date has changed since the last check: if the user was following the current period
  /// (today / this month / the last 12 months), move with it; a past date they picked stays put.
  /// Either way everything rebuilds, so "今天 / 昨天" labels, titles, lists and totals agree.
  void refreshDay() {
    final today = _dateOnly(DateTime.now());
    if (today == _today) return;
    final followingNow = _isCurrentPeriodOn(_today);
    _today = today;
    if (followingNow) month = DateTime.now();
    notifyListeners();
  }

  bool _isCurrentPeriodOn(DateTime day) => period == Period.day
      ? month.year == day.year && month.month == day.month && month.day == day.day
      : month.year == day.year && month.month == day.month;

  /// Where an expense / income goes when no category is picked: the ledger's own "其他" category of
  /// that kind (any of the usual spellings), or null when there is none yet.
  LedgerCategory? otherCategory(EntryKind kind) => _otherCategoryIn(_ledger, kind);

  static LedgerCategory? _otherCategoryIn(Ledger ledger, EntryKind kind) {
    final names = kind == EntryKind.income
        ? ['其他收入', '其它收入', '其他', '其它', tr('其他收入'), tr('其他')]
        : ['其他', '其它', '其他支出', '其它支出', tr('其他')];
    for (final name in names) {
      for (final category in ledger.categories) {
        if (category.kind == kind && category.name.trim() == name) return category;
      }
    }
    return null;
  }

  void cancelImport() {
    pendingImport = null;
    notifyListeners();
  }

  void confirmImport() {
    final next = pendingImport;
    if (next == null) return;
    try {
      next.validate();
      if (!isDemo) repository!.save(next, preserveImportSnapshot: true);
      _ledger = next;
      _syncCurrency();
      loadingFailed = false;
      pendingImport = null;
      final latest = next.entries.isEmpty
          ? DateTime.now()
          : next.entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);
      month = latest;
      period = Period.month;
    } catch (e) {
      error = tr('恢复失败，当前账本未改动：{error}', {'error': e});
    }
    notifyListeners();
  }

  String categoryName(Entry entry) {
    if (entry.kind == EntryKind.transfer) return tr('账户转账');
    if (entry.kind == EntryKind.adjustment) return tr('余额调整');
    final ids = entry.allocations.map((a) => a.categoryID).toSet();
    return _ledger.categories.where((c) => ids.contains(c.id)).map((c) => c.name).join(' / ');
  }

  String accountName(String id) {
    for (final account in _ledger.accounts) {
      if (account.id == id) return account.name;
    }
    return tr('未知账户');
  }

  LedgerCategory? category(String id) {
    for (final category in _ledger.categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  // MARK: Selected period (today / this month / last 12 months)

  (DateTime, DateTime) intervalContaining(DateTime date) {
    switch (period) {
      case Period.day:
        final start = DateTime(date.year, date.month, date.day);
        return (start, DateTime(date.year, date.month, date.day + 1));
      case Period.month:
        return (DateTime(date.year, date.month, 1), DateTime(date.year, date.month + 1, 1));
      case Period.year:
        // Rolling 12 months ending with the anchor month (this month included).
        return (DateTime(date.year, date.month - 11, 1), DateTime(date.year, date.month + 1, 1));
    }
  }

  (DateTime, DateTime) get interval => intervalContaining(month);

  DateTime _shift(DateTime date, int steps) => switch (period) {
        Period.day => DateTime(date.year, date.month, date.day + steps, date.hour, date.minute),
        Period.month => DateTime(date.year, date.month + steps, 1),
        Period.year => DateTime(date.year, date.month + steps * 12, 1),
      };

  /// The same period one step earlier (yesterday / last month / the 12 months before).
  (DateTime, DateTime) get previousInterval => intervalContaining(_shift(month, -1));

  List<Entry> entriesIn((DateTime, DateTime) range) => _ledger.entriesBetween(range.$1, range.$2);

  /// Booked entries in the selected period, newest first.
  List<Entry> get periodEntries => entriesIn(interval)..sort((a, b) => b.date.compareTo(a.date));

  int periodTotal(EntryKind kind) => entriesIn(interval).where((e) => e.kind == kind).fold(0, (s, e) => s + e.amount);

  List<(LedgerCategory, int)> get periodCategorySpending => _ledger.categorySpendingIn(entriesIn(interval));

  bool get isCurrentPeriod {
    final now = DateTime.now();
    return period == Period.day
        ? month.year == now.year && month.month == now.month && month.day == now.day
        : month.year == now.year && month.month == now.month;
  }

  List<MonthTotal> get yearMonths {
    final start = intervalContaining(month).$1;
    return [
      for (var i = 0; i < 12; i++)
        () {
          final value = DateTime(start.year, start.month + i, 1);
          return MonthTotal(value, _ledger.total(EntryKind.income, value), _ledger.total(EntryKind.expense, value));
        }()
    ];
  }

  /// Months counted for the monthly average: the window's months from the first recorded entry onwards.
  /// The current, unfinished month counts as a whole month.
  int get averageMonthCount {
    if (_ledger.entries.isEmpty) return 12;
    final first = _ledger.entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final firstMonth = DateTime(first.year, first.month, 1);
    final count = yearMonths.where((m) => !m.month.isBefore(firstMonth)).length;
    return count < 1 ? 1 : count;
  }

  int monthlyAverage(EntryKind kind) {
    final total = yearMonths.fold<int>(0, (s, m) => s + (kind == EntryKind.income ? m.income : m.expense));
    return total ~/ averageMonthCount;
  }

  /// Short label for captions: 今日 / 本月 / 近一年.
  String get periodWord => switch (period) { Period.day => tr('今日', {}, 'period'), Period.month => tr('本月', {}, 'period'), Period.year => tr('近一年', {}, 'period') };

  /// Segment title: "今天" / "本月" / "近一年", or the specific day / month when browsing away from now.
  String get periodName {
    final now = DateTime.now();
    final thisYear = month.year == now.year;
    switch (period) {
      case Period.day:
        final today = DateTime(now.year, now.month, now.day);
        final day = DateTime(month.year, month.month, month.day);
        final difference = today.difference(day).inDays;
        if (difference == 0) return tr('今天');
        if (difference == 1) return tr('昨天');
        return thisYear ? fmtMonthDay(month) : fmtYMD(month);
      case Period.month:
        if (thisYear && month.month == now.month) return tr('本月');
        return thisYear ? fmtMonth(month) : fmtYearMonth(month);
      case Period.year:
        if (thisYear && month.month == now.month) return tr('近一年');
        return tr('至{month}', {'month': fmtYearMonth(month)});
    }
  }

  /// "2025年11月 – 2026年10月", shown under the year view.
  String get yearRangeText {
    final (start, end) = intervalContaining(month);
    final last = DateTime(end.year, end.month - 1, 1);
    return '${fmtYearMonth(start)} – ${fmtYearMonth(last)}';
  }

  void stepPeriod(int value) {
    month = _shift(month, value);
    notifyListeners();
  }

  /// Tapping a segment: switch mode, or jump back to now if it is already selected.
  void select(Period next) {
    if (period == next) {
      month = DateTime.now();
    } else {
      period = next;
    }
    notifyListeners();
  }
}

/// Makes the store available to widgets; widgets that call [StoreScope.of] rebuild on changes.
class StoreScope extends InheritedNotifier<LedgerStore> {
  const StoreScope({super.key, required LedgerStore store, required super.child}) : super(notifier: store);

  static LedgerStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static LedgerStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

/// The account shown under 设置 → 账号.
class AccountInfo {
  AccountInfo({required this.name, required this.email, this.syncEnabled = true, this.lastSynced});
  final String name;
  final String email;
  bool syncEnabled;
  DateTime? lastSynced;
}
