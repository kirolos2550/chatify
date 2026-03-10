import 'dart:io';

import 'package:chatify/core/common/debug_log_file_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DebugLogFileSink writes a session file line', () async {
    final rootDir = await Directory.systemTemp.createTemp('chatify_log_test_');
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    final sink = createDebugLogFileSink(
      directoryPathProvider: () async => rootDir.path,
      maxFiles: 10,
      clock: () => DateTime.utc(2026, 3, 10, 12, 0, 0),
    );

    await sink.init(sessionId: 'abc12345ff');
    await sink.writeLine('line_1');
    await sink.close();

    final path = sink.currentFilePath;
    expect(path, isNotNull);
    final file = File(path!);
    expect(await file.exists(), isTrue);
    final content = await file.readAsString();
    expect(content, contains('line_1'));
  });

  test(
    'DebugLogFileSink ignores writes after close without throwing',
    () async {
      final rootDir = await Directory.systemTemp.createTemp(
        'chatify_log_close_test_',
      );
      addTearDown(() async {
        if (await rootDir.exists()) {
          await rootDir.delete(recursive: true);
        }
      });

      final sink = createDebugLogFileSink(
        directoryPathProvider: () async => rootDir.path,
        maxFiles: 10,
        clock: () => DateTime.utc(2026, 3, 10, 12, 0, 1),
      );

      await sink.init(sessionId: 'close12345');
      await sink.writeLine('line_before_close');
      await sink.close();

      await sink.writeLine('line_after_close');

      final path = sink.currentFilePath;
      expect(path, isNotNull);
      final content = await File(path!).readAsString();
      expect(content, contains('line_before_close'));
      expect(content, isNot(contains('line_after_close')));
    },
  );

  test(
    'DebugLogFileSink keeps only latest maxFiles by retention policy',
    () async {
      final rootDir = await Directory.systemTemp.createTemp(
        'chatify_retention_',
      );
      addTearDown(() async {
        if (await rootDir.exists()) {
          await rootDir.delete(recursive: true);
        }
      });

      for (var i = 0; i < 12; i++) {
        final sink = createDebugLogFileSink(
          directoryPathProvider: () async => rootDir.path,
          maxFiles: 10,
          clock: () => DateTime.utc(2026, 3, 10, 12, 0, i),
        );
        await sink.init(sessionId: 'session_$i');
        await sink.writeLine('entry_$i');
        await sink.close();
      }

      final files = await rootDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files.length, lessThanOrEqualTo(10));
    },
  );
}
