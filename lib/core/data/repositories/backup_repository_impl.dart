import 'dart:convert';

import 'package:chatify/core/common/failure.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/backup_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: BackupRepository)
class BackupRepositoryImpl implements BackupRepository {
  BackupRepositoryImpl(this._secureStorage);

  static const _backupKey = 'chatify_backup_config';
  final FlutterSecureStorage _secureStorage;

  @override
  Future<Result<void>> enableBackup({required String password}) async {
    try {
      await _secureStorage.write(
        key: _backupKey,
        value: base64Encode(utf8.encode(password)),
      );
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }

  @override
  Future<Result<void>> restoreBackup({required String password}) async {
    try {
      final data = await _secureStorage.read(key: _backupKey);
      if (data == null) {
        return const FailureResult(Failure('No backup configured'));
      }
      final decoded = utf8.decode(base64Decode(data));
      if (decoded != password) {
        return const FailureResult(Failure('Invalid backup password'));
      }
      return const Success(null);
    } catch (e) {
      return FailureResult(Failure(e.toString()));
    }
  }
}
