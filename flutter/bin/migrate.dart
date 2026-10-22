// Command line migration: dart run bin/migrate.dart migrate /path/database.sql /path/个人账本.centwise
// Writes a new backup plus a JSON report next to it; never overwrites existing files.
import 'dart:convert';
import 'dart:io';

import 'package:centwise/core/money.dart';
import 'package:centwise/core/money_pro_importer.dart';
import 'package:centwise/core/repository.dart';

void main(List<String> args) {
  try {
    if (args.length != 3 || args[0] != 'migrate') {
      throw LedgerError('用法：dart run bin/migrate.dart migrate /path/database.sql /path/output.centwise');
    }
    final source = File(args[1]).absolute.path;
    final destination = File(args[2]).absolute.path;
    final report = '$destination.migration-report.json';
    if (File(destination).existsSync() || File(report).existsSync() || source == destination) {
      throw LedgerError('输出文件已存在，或与原文件相同；不会覆盖。');
    }
    final (ledger, summary) = MoneyProImporter.read(source);
    LedgerFiles.createNew(LedgerCodec.encode(ledger), destination);
    final reportData = const JsonEncoder.withIndent('  ').convert(summary.toJson());
    LedgerFiles.createNew(utf8.encode(reportData), report);
    stdout.writeln(reportData);
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
