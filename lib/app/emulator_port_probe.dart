import 'emulator_port_probe_stub.dart'
    if (dart.library.io) 'emulator_port_probe_io.dart';

Future<bool> isTcpPortReachable(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 350),
}) {
  return isTcpPortReachableImpl(host, port, timeout: timeout);
}
