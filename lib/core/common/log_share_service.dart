import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/log_exporter.dart';
import 'package:share_plus/share_plus.dart';

enum LogShareStatus { shared, dismissed, unavailable, failed }

class LogShareResult {
  const LogShareResult({
    required this.status,
    required this.message,
    this.exportPath,
  });

  final LogShareStatus status;
  final String message;
  final String? exportPath;
}

Future<LogShareResult> shareLatestDebugLogs({
  required String action,
  int maxSessions = 4,
}) async {
  try {
    final prepared = await prepareLatestSessionExport(maxSessions: maxSessions);
    if (prepared == null) {
      AppLogger.warning(
        'No debug session logs available for sharing',
        event: 'debug.logs.share.unavailable',
        action: action,
      );
      return const LogShareResult(
        status: LogShareStatus.unavailable,
        message: 'No debug session logs were found yet.',
      );
    }

    AppLogger.info(
      'Debug logs prepared for sharing',
      event: 'debug.logs.share.prepared',
      action: action,
      metadata: <String, Object?>{
        'exportPath': prepared.filePath,
        'sourceSessionCount': prepared.sourceSessionPaths.length,
      },
    );

    final shareResult = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(prepared.filePath)],
        subject: 'Chatify debug logs',
        text:
            'Chatify debug logs (${prepared.sourceSessionPaths.length} sessions)',
      ),
    );

    if (shareResult.status == ShareResultStatus.success) {
      AppLogger.info(
        'Debug logs shared successfully',
        event: 'debug.logs.share.success',
        action: action,
        metadata: <String, Object?>{
          'exportPath': prepared.filePath,
          'sourceSessionCount': prepared.sourceSessionPaths.length,
        },
      );
      return LogShareResult(
        status: LogShareStatus.shared,
        message: 'Debug logs ready to share.',
        exportPath: prepared.filePath,
      );
    }

    AppLogger.warning(
      'Debug log sharing was dismissed',
      event: 'debug.logs.share.dismissed',
      action: action,
    );
    return LogShareResult(
      status: LogShareStatus.dismissed,
      message: 'Sharing canceled.',
      exportPath: prepared.filePath,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Failed to share debug logs',
      error,
      stackTrace,
      event: 'debug.logs.share.failure',
      action: action,
      source: 'LogShareService',
      operation: 'shareLatestDebugLogs',
    );
    return const LogShareResult(
      status: LogShareStatus.failed,
      message: 'Failed to export debug logs.',
    );
  }
}
