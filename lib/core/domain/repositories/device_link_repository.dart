import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/device.dart';

abstract interface class DeviceLinkRepository {
  Stream<List<Device>> watchLinkedDevices();

  Future<Result<String>> linkDeviceStart();

  Future<Result<void>> linkDeviceConfirm({required String linkCode});
}
