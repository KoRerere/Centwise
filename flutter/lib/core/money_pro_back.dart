import 'dart:convert';
import 'dart:io';

import '../l10n/l10n.dart';
import 'money.dart';

/// Money Pro `.back` backups (what Money Pro writes to its Documents folder when you back up) are a
/// plain sequence of `<path>\n<byte length>\n<bytes>` entries: an info.plist, the ledger's SQLite
/// `database.sql` and a settings plist. This writes the database to [into] for [MoneyProImporter].
File extractMoneyProBack(String path, Directory into) {
  final data = File(path).readAsBytesSync();
  final invalid = LedgerError(tr('无法识别的 Money Pro 备份文件。'));
  int lineEnd(int from) {
    final end = data.indexOf(10, from);
    if (end < 0) throw invalid;
    return end;
  }

  var i = 0;
  while (i < data.length) {
    final nameEnd = lineEnd(i);
    final name = utf8.decode(data.sublist(i, nameEnd), allowMalformed: true);
    final sizeEnd = lineEnd(nameEnd + 1);
    final size = int.tryParse(ascii.decode(data.sublist(nameEnd + 1, sizeEnd), allowInvalid: true));
    if (size == null || size < 0 || sizeEnd + 1 + size > data.length) throw invalid;
    if (name.endsWith('/database.sql')) {
      into.createSync(recursive: true);
      return File('${into.path}/database.sql')..writeAsBytesSync(data.sublist(sizeEnd + 1, sizeEnd + 1 + size), flush: true);
    }
    i = sizeEnd + 1 + size;
  }
  throw LedgerError(tr('Money Pro 备份里没有找到账本数据库。'));
}
