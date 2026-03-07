import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/repositories/backup_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

enum BackupStatus { idle, loading, success, error }

class BackupState {
  const BackupState({this.status = BackupStatus.idle, this.message});

  final BackupStatus status;
  final String? message;

  BackupState copyWith({BackupStatus? status, String? message}) {
    return BackupState(status: status ?? this.status, message: message);
  }
}

@injectable
class BackupCubit extends Cubit<BackupState> {
  BackupCubit(this._repository) : super(const BackupState());

  final BackupRepository _repository;

  Future<void> enable(String password) async {
    emit(state.copyWith(status: BackupStatus.loading));
    final result = await _repository.enableBackup(password: password);
    if (result is Success<void>) {
      emit(
        state.copyWith(status: BackupStatus.success, message: 'Backup enabled'),
      );
    } else {
      emit(
        state.copyWith(
          status: BackupStatus.error,
          message: result.error?.message ?? 'Backup failed',
        ),
      );
    }
  }

  Future<void> restore(String password) async {
    emit(state.copyWith(status: BackupStatus.loading));
    final result = await _repository.restoreBackup(password: password);
    if (result is Success<void>) {
      emit(
        state.copyWith(
          status: BackupStatus.success,
          message: 'Backup restored',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: BackupStatus.error,
        message: result.error?.message ?? 'Restore failed',
      ),
    );
  }
}
