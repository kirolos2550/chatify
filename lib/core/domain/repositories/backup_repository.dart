import 'package:chatify/core/common/result.dart';

abstract interface class BackupRepository {
  Future<Result<void>> enableBackup({required String password});

  Future<Result<void>> restoreBackup({required String password});
}
