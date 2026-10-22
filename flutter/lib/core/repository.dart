import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'money.dart';

/// JSON backup format, compatible with `.qingledger` files written by the SwiftUI version
/// (same keys, sorted; dates as seconds since 2001-01-01; `schemaVersion` 1).
class LedgerCodec {
  LedgerCodec._();

  static const int maxBytes = 100000000;

  static Uint8List encode(Ledger ledger) {
    ledger.validate();
    final data = utf8.encode(const JsonEncoder.withIndent('  ').convert(_sorted(ledger.toJson())));
    if (data.length > maxBytes) throw LedgerError('账本超过第一版 100 MB 文件限制，已停止保存或导出。');
    return Uint8List.fromList(data);
  }

  static Ledger decode(List<int> data) {
    if (data.length > maxBytes) throw LedgerError('备份文件超过 100 MB，已停止导入。');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException {
      throw LedgerError('这不是有效的 Centwise 备份文件。');
    }
    if (json is! Map) throw LedgerError('这不是有效的 Centwise 备份文件。');
    final Ledger ledger;
    try {
      ledger = Ledger.fromJson(json.cast<String, Object?>());
    } on LedgerError {
      rethrow;
    } catch (_) {
      throw LedgerError('备份文件结构不完整，无法读取。');
    }
    ledger.validate();
    return ledger;
  }

  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k as String).toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }
}

class LedgerFiles {
  LedgerFiles._();

  /// Stage in the destination directory, then rename. Existing files are never replaced.
  static void createNew(List<int> data, String destination) {
    final target = File(destination);
    if (target.existsSync()) throw LedgerError('目标文件已存在，不会覆盖。');
    final stage = File('${target.parent.path}/.centwise-stage-${newId()}');
    try {
      stage.writeAsBytesSync(data, flush: true);
      if (target.existsSync()) throw LedgerError('目标文件已存在，不会覆盖。');
      stage.renameSync(destination);
    } finally {
      if (stage.existsSync()) stage.deleteSync();
    }
  }

  /// Write to a sibling temp file and rename over the target, so a crash never leaves half a file.
  static void writeAtomic(File file, List<int> data) {
    final temp = File('${file.path}.tmp-${newId()}');
    try {
      temp.writeAsBytesSync(data, flush: true);
      temp.renameSync(file.path);
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }
}

/// A failed load is surfaced to the UI and never silently replaced with an empty ledger.
class LedgerRepository {
  LedgerRepository(this.directory);

  final Directory directory;

  File get file => File('${directory.path}/ledger.centwise');
  Directory get backups => Directory('${directory.path}/Backups');

  Ledger? load() {
    if (!file.existsSync()) return null;
    return LedgerCodec.decode(file.readAsBytesSync());
  }

  void save(Ledger ledger, {bool preserveImportSnapshot = false}) {
    final data = LedgerCodec.encode(ledger);
    directory.createSync(recursive: true);
    if (file.existsSync()) {
      backups.createSync(recursive: true);
      final now = DateTime.now();
      final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final daily = File('${backups.path}/daily-$day.centwise');
      if (!daily.existsSync()) file.copySync(daily.path);
      if (preserveImportSnapshot) file.copySync('${backups.path}/before-import-${newId()}.centwise');
      LedgerFiles.writeAtomic(File('${backups.path}/last-good.centwise'), file.readAsBytesSync());
    }
    LedgerFiles.writeAtomic(file, data);
  }
}
