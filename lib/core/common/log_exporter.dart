import 'log_exporter_base.dart';
import 'log_exporter_stub.dart'
    if (dart.library.io) 'log_exporter_io.dart'
    as platform;

export 'log_exporter_base.dart';

Future<PreparedLogExport?> prepareLatestSessionExport({int maxSessions = 4}) {
  return platform.prepareLatestSessionExport(maxSessions: maxSessions);
}
