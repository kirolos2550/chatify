import 'package:chatify/core/common/debug_log_file_sink_base.dart';

DebugLogFileSink createPlatformDebugLogFileSink({
  required LogDirectoryPathProvider directoryPathProvider,
  required int maxFiles,
  required Clock clock,
}) {
  return _NoopDebugLogFileSink();
}

class _NoopDebugLogFileSink implements DebugLogFileSink {
  @override
  String? get currentFilePath => null;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> init({required String sessionId}) async {}

  @override
  Future<List<String>> listSessionLogPaths({int limit = 10}) async {
    return const <String>[];
  }

  @override
  Future<void> writeLine(String line) async {}
}
