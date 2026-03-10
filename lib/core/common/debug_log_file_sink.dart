import 'debug_log_file_sink_base.dart';
import 'debug_log_file_sink_stub.dart'
    if (dart.library.io) 'debug_log_file_sink_io.dart'
    as platform;

export 'debug_log_file_sink_base.dart';

DebugLogFileSink createDebugLogFileSink({
  required LogDirectoryPathProvider directoryPathProvider,
  required int maxFiles,
  required Clock clock,
}) {
  return platform.createPlatformDebugLogFileSink(
    directoryPathProvider: directoryPathProvider,
    maxFiles: maxFiles,
    clock: clock,
  );
}
