import 'dart:async';

import 'package:chatify/core/domain/entities/status_item.dart';
import 'package:chatify/core/domain/repositories/status_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class StatusState {
  const StatusState({
    this.items = const [],
    this.loading = true,
    this.errorMessage,
  });

  final List<StatusItem> items;
  final bool loading;
  final String? errorMessage;

  StatusState copyWith({
    List<StatusItem>? items,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return StatusState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

@injectable
class StatusCubit extends Cubit<StatusState> {
  StatusCubit(this._repository) : super(const StatusState()) {
    _subscription = _repository.watchStatusFeed().listen(
      (items) =>
          emit(state.copyWith(items: items, loading: false, clearError: true)),
      onError: (Object error, StackTrace stackTrace) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          emit(state.copyWith(loading: false, clearError: true));
          return;
        }
        emit(state.copyWith(loading: false, errorMessage: error.toString()));
      },
    );
  }

  final StatusRepository _repository;
  StreamSubscription<List<StatusItem>>? _subscription;

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
