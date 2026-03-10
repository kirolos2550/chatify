import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:chatify/core/common/debug_log_file_sink.dart';
import 'package:chatify/core/common/log_redactor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppLogLevel { info, warning, error, breadcrumb }

abstract final class AppLogger {
  static const int _maxDebugSessionFiles = 10;
  static DebugLogFileSink? _debugFileSink;
  static bool _isSessionInitialized = false;
  static String? _currentRoute;
  static String? _sessionId;
  static DateTime Function() _clock = DateTime.now;

  static String? get currentSessionLogPath => _debugFileSink?.currentFilePath;

  static Future<void> flush() async {
    await _debugFileSink?.flush();
  }

  static Future<List<String>> listRecentSessionLogPaths({
    int limit = 10,
  }) async {
    final sink = _debugFileSink;
    if (sink == null) {
      return const <String>[];
    }
    return sink.listSessionLogPaths(limit: limit);
  }

  static void setCurrentRoute(String? route) {
    _currentRoute = route;
  }

  static Future<void> initDebugSession({
    required String flavor,
    required String buildMode,
    required String platform,
    LogDirectoryPathProvider? logDirectoryPathProvider,
    DateTime Function()? clock,
  }) async {
    if (_isSessionInitialized) {
      return;
    }

    _isSessionInitialized = true;
    _clock = clock ?? DateTime.now;
    _sessionId = _createSessionId();

    try {
      _debugFileSink = createDebugLogFileSink(
        directoryPathProvider:
            logDirectoryPathProvider ?? _defaultLogDirectoryPathProvider,
        maxFiles: _maxDebugSessionFiles,
        clock: _clock,
      );
      await _debugFileSink!.init(sessionId: _sessionId!);
    } catch (error, stackTrace) {
      _debugFileSink = null;
      developer.log(
        'Failed to initialize debug session log file',
        name: 'chatify.warning',
        error: error,
        stackTrace: stackTrace,
      );
    }

    info(
      'Debug session started',
      event: 'session.start',
      metadata: <String, Object?>{
        'sessionId': _sessionId,
        'flavor': flavor,
        'buildMode': buildMode,
        'platform': platform,
        'logPath': currentSessionLogPath,
      },
    );
  }

  static Future<void> flushAndClose() async {
    if (!_isSessionInitialized) {
      return;
    }
    info(
      'Debug session ended',
      event: 'session.end',
      metadata: <String, Object?>{'sessionId': _sessionId},
    );
    await _debugFileSink?.close();
    _debugFileSink = null;
    _isSessionInitialized = false;
  }

  static void info(
    String message, {
    String? event,
    String? route,
    String? action,
    Map<String, Object?>? metadata,
  }) {
    _log(
      level: AppLogLevel.info,
      message: message,
      event: event,
      route: route,
      action: action,
      metadata: metadata,
    );
  }

  static void warning(
    String message, {
    String? event,
    String? route,
    String? action,
    Map<String, Object?>? metadata,
  }) {
    _log(
      level: AppLogLevel.warning,
      message: message,
      event: event,
      route: route,
      action: action,
      metadata: metadata,
    );
  }

  static void breadcrumb(
    String event, {
    String? route,
    String? action,
    Map<String, Object?>? metadata,
  }) {
    _log(
      level: AppLogLevel.breadcrumb,
      message: event,
      event: event,
      route: route,
      action: action,
      metadata: metadata,
    );
  }

  static void error(
    String message,
    Object error,
    StackTrace? stackTrace, {
    String? event,
    String? source,
    String? operation,
    String? route,
    String? action,
    Map<String, Object?>? metadata,
  }) {
    _log(
      level: AppLogLevel.error,
      message: message,
      error: error,
      stackTrace: stackTrace,
      event: event,
      route: route,
      action: action,
      metadata: <String, Object?>{
        'source': ?source,
        'operation': ?operation,
        ...?metadata,
      },
    );
  }

  static void _log({
    required AppLogLevel level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    String? event,
    String? route,
    String? action,
    Map<String, Object?>? metadata,
  }) {
    final timestamp = _clock().toUtc();
    final resolvedRoute = route ?? _currentRoute;
    final safeMetadata = metadata == null
        ? const <String, Object?>{}
        : LogRedactor.sanitizeMetadata(metadata);
    final safeError = error == null
        ? null
        : LogRedactor.sanitizeObject(error, keyHint: 'error');
    final safeMessage = LogRedactor.sanitizeObject(message, keyHint: 'message');

    developer.log(
      '$safeMessage | event=${event ?? message} | route=${resolvedRoute ?? '-'} | action=${action ?? '-'}',
      name: 'chatify.${level.name}',
      error: safeError,
      stackTrace: stackTrace,
    );

    final sink = _debugFileSink;
    if (sink == null) {
      return;
    }

    final line = _formatReadableLine(
      timestamp: timestamp,
      level: level,
      event: event ?? message,
      route: resolvedRoute,
      action: action,
      message: '$safeMessage',
      metadata: safeMetadata,
      error: safeError,
      stackTrace: stackTrace,
    );
    unawaited(sink.writeLine(line));
  }

  static String _formatReadableLine({
    required DateTime timestamp,
    required AppLogLevel level,
    required String event,
    required String? route,
    required String? action,
    required String message,
    required Map<String, Object?> metadata,
    required Object? error,
    required StackTrace? stackTrace,
  }) {
    final parts = <String>[
      timestamp.toIso8601String(),
      level.name.toUpperCase(),
      event,
      'route=${route ?? '-'}',
      'action=${action ?? '-'}',
      'message=${_singleLine(message)}',
      'metadata=${jsonEncode(metadata)}',
    ];
    if (error != null) {
      parts.add('error=${_singleLine(error.toString())}');
    }
    if (stackTrace != null) {
      parts.add('stack=${_singleLine(stackTrace.toString())}');
    }
    return parts.join(' | ');
  }

  static Future<String> _defaultLogDirectoryPathProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'chatify_debug_logs');
  }

  static String _singleLine(String value) {
    return value.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
  }

  static String _createSessionId() {
    final now = _clock().microsecondsSinceEpoch;
    return now.toRadixString(16);
  }
}
