import 'dart:async';

import 'package:chatify/core/domain/entities/call_session.dart';
import 'package:chatify/core/domain/enums/chat_enums.dart';
import 'package:chatify/core/domain/repositories/call_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class CallsState {
  const CallsState({
    this.calls = const [],
    this.loading = true,
    this.busy = false,
    this.errorMessage,
  });

  final List<CallSession> calls;
  final bool loading;
  final bool busy;
  final String? errorMessage;

  CallsState copyWith({
    List<CallSession>? calls,
    bool? loading,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CallsState(
      calls: calls ?? this.calls,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

@injectable
class CallsCubit extends Cubit<CallsState> {
  CallsCubit(this._repository) : super(const CallsState()) {
    _subscription = _repository.watchCalls().listen(
      (calls) =>
          emit(state.copyWith(calls: calls, loading: false, clearError: true)),
      onError: (Object error, StackTrace stackTrace) {
        emit(state.copyWith(loading: false, errorMessage: error.toString()));
      },
    );
  }

  final CallRepository _repository;
  StreamSubscription<List<CallSession>>? _subscription;

  Future<void> startCall({
    required List<String> participantIds,
    required CallType type,
  }) async {
    if (participantIds.isEmpty) {
      emit(state.copyWith(errorMessage: 'Select at least one participant'));
      return;
    }
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.startCall(
      participantIds: participantIds,
      type: type,
    );
    if (result.error != null) {
      emit(state.copyWith(busy: false, errorMessage: result.error!.message));
      return;
    }
    emit(state.copyWith(busy: false, clearError: true));
  }

  Future<void> endCall(String callId) async {
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.endCall(callId: callId);
    if (result.error != null) {
      emit(state.copyWith(busy: false, errorMessage: result.error!.message));
      return;
    }
    emit(state.copyWith(busy: false, clearError: true));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
