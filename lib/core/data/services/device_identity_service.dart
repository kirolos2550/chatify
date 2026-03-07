import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

@lazySingleton
class DeviceIdentityService {
  DeviceIdentityService(this._storage, this._uuid);

  static const _deviceIdKey = 'device_id';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final value = _uuid.v4();
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }
}
