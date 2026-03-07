import 'dart:io';

Future<bool> isTcpPortReachableImpl(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 350),
}) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    await socket?.close();
  }
}
