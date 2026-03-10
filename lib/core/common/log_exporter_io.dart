import 'dart:io';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/log_exporter_base.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<PreparedLogExport?> prepareLatestSessionExport({
  int maxSessions = 4,
}) async {
  await AppLogger.flush();
  final sessionPaths = await AppLogger.listRecentSessionLogPaths(
    limit: maxSessions,
  );
  if (sessionPaths.isEmpty) {
    return null;
  }

  final existingFiles = <File>[];
  for (final sessionPath in sessionPaths) {
    final file = File(sessionPath);
    if (await file.exists()) {
      existingFiles.add(file);
    }
  }
  if (existingFiles.isEmpty) {
    return null;
  }

  final tempDir = await getTemporaryDirectory();
  final exportPath = p.join(
    tempDir.path,
    'chatify_logs_export_${_timestamp(DateTime.now().toUtc())}.log',
  );
  final buffer = StringBuffer()
    ..writeln('Chatify Debug Log Export')
    ..writeln('generated_utc=${DateTime.now().toUtc().toIso8601String()}')
    ..writeln('session_count=${existingFiles.length}');

  for (final file in existingFiles) {
    String content;
    try {
      content = await file.readAsString();
    } catch (error) {
      content = '[Failed to read ${file.path}: $error]';
    }
    buffer
      ..writeln()
      ..writeln('===== BEGIN ${p.basename(file.path)} =====')
      ..writeln(content)
      ..writeln('===== END ${p.basename(file.path)} =====');
  }

  final exportFile = File(exportPath);
  await exportFile.writeAsString(buffer.toString(), flush: true);

  return PreparedLogExport(
    filePath: exportFile.path,
    sourceSessionPaths: existingFiles
        .map((file) => file.path)
        .toList(growable: false),
  );
}

String _timestamp(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_'
      '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}';
}
