import 'dart:convert';

import 'package:chatify/core/crypto/crypto_engine.dart';
import 'package:injectable/injectable.dart';

/// Temporary adapter point for Signal protocol integration.
/// Replace internals with libsignal bindings while keeping interface stable.
@LazySingleton(as: CryptoEngine)
class SignalCryptoEngine implements CryptoEngine {
  @override
  Future<String> decrypt({
    required String ciphertext,
    required String peerDeviceId,
  }) async {
    return utf8.decode(base64Decode(ciphertext));
  }

  @override
  Future<String> encrypt({
    required String plaintext,
    required String peerDeviceId,
  }) async {
    return base64Encode(utf8.encode(plaintext));
  }
}
