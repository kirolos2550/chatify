abstract interface class CryptoEngine {
  Future<String> encrypt({
    required String plaintext,
    required String peerDeviceId,
  });

  Future<String> decrypt({
    required String ciphertext,
    required String peerDeviceId,
  });
}
