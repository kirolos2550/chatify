import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:chatify/core/common/debug_log_file_sink_base.dart';
import 'package:path/path.dart' as p;

DebugLogFileSink createPlatformDebugLogFileSink({
  required LogDirectoryPathProvider directoryPathProvider,
  required int maxFiles,
  required Clock clock,
}) {
  return _IoDebugLogFileSink(
    directoryPathProvider: directoryPathProvider,
    maxFiles: maxFiles,
    clock: clock,
  );
}

class _IoDebugLogFileSink implements DebugLogFileSink {
  _IoDebugLogFileSink({
    required this.directoryPathProvider,
    required this.maxFiles,
    required this.clock,
  });

  final LogDirectoryPathProvider directoryPathProvider;
  final int maxFiles;
  final Clock clock;

  IOSink? _sink;
  String? _currentFilePathValue;
  Directory? _sessionDirectory;
  Future<void> _pendingWrite = Future<void>.value();
  bool _isClosed = false;

  @override
  String? get currentFilePath => _currentFilePathValue;

  @override
  Future<void> init({required String sessionId}) async {
    await _closeSinkSilently();
    _pendingWrite = Future<void>.value();
    _isClosed = false;

    final rootPath = await directoryPathProvider();
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _sessionDirectory = dir;

    final fileName = _buildFileName(clock(), sessionId);
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _sink = file.openWrite(mode: FileMode.append);
    _currentFilePathValue = file.path;

    await _applyRetention(dir);
  }

  @override
  Future<void> writeLine(String line) {
    _pendingWrite = _pendingWrite
        .then((_) async {
          if (_isClosed) {
            return;
          }
          final sink = _sink;
          if (sink == null) {
            return;
          }
          try {
            sink.writeln(line);
          } catch (error, stackTrace) {
            developer.log(
              'Debug log sink write failed',
              name: 'chatify.warning',
              error: error,
              stackTrace: stackTrace,
            );
            final recovered = await _recoverSink();
            if (_isClosed || recovered == null) {
              return;
            }
            try {
              recovered.writeln(line);
            } catch (retryError, retryStackTrace) {
              developer.log(
                'Debug log sink retry write failed',
                name: 'chatify.warning',
                error: retryError,
                stackTrace: retryStackTrace,
              );
            }
          }
        })
        .catchError((error, stackTrace) {
          developer.log(
            'Debug log write queue failure',
            name: 'chatify.warning',
            error: error,
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
          );
        });
    return _pendingWrite;
  }

  @override
  Future<void> flush() async {
    await _pendingWrite;
    if (_isClosed) {
      return;
    }
    try {
      await _sink?.flush();
    } catch (error, stackTrace) {
      developer.log(
        'Debug log flush failed',
        name: 'chatify.warning',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<String>> listSessionLogPaths({int limit = 10}) async {
    final dir = _sessionDirectory ?? Directory(await directoryPathProvider());
    if (!await dir.exists()) {
      return const <String>[];
    }
    final files = await _sessionLogFiles(dir);
    return files.take(limit).map((file) => file.path).toList(growable: false);
  }

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _pendingWrite;
    await _closeSinkSilently();
    _sink = null;
  }

  Future<IOSink?> _recoverSink() async {
    if (_isClosed) {
      return null;
    }
    final path = _currentFilePathValue;
    if (path == null || path.isEmpty) {
      _sink = null;
      return null;
    }
    await _closeSinkSilently();
    try {
      final file = File(path);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      _sink = file.openWrite(mode: FileMode.append);
      return _sink;
    } catch (error, stackTrace) {
      developer.log(
        'Debug log sink recovery failed',
        name: 'chatify.warning',
        error: error,
        stackTrace: stackTrace,
      );
      _sink = null;
      return null;
    }
  }

  Future<void> _closeSinkSilently() async {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    _sink = null;
    try {
      await sink.flush();
    } catch (_) {
      // Ignore sink flush failures during cleanup.
    }
    try {
      await sink.close();
    } catch (_) {
      // Ignore sink close failures during cleanup.
    }
  }

  Future<void> _applyRetention(Directory dir) async {
    final files = await _sessionLogFiles(dir);
    if (files.length <= maxFiles) {
      return;
    }
    for (final file in files.skip(maxFiles)) {
      try {
        await file.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  String _buildFileName(DateTime now, String sessionId) {
    final ts =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'debug_session_${ts}_${sessionId.substring(0, 8)}.log';
  }

  Future<List<File>> _sessionLogFiles(Directory dir) async {
    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => p.basename(file.path).startsWith('debug_session_'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}
