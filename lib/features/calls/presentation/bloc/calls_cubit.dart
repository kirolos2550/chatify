import 'dart:async';

import 'package:chatify/core/common/app_logger.dart';
import 'package:chatify/core/common/result.dart';
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
        AppLogger.error(
          'Calls stream failed',
          error,
          stackTrace,
          event: 'calls.stream.failure',
          action: 'calls.watch',
          source: 'CallsCubit',
          operation: 'watchCalls',
        );
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
      AppLogger.warning(
        'Start call rejected due to empty participant list',
        event: 'calls.start.validation_failed',
        action: 'calls.start',
      );
      emit(state.copyWith(errorMessage: 'Select at least one participant'));
      return;
    }
    AppLogger.breadcrumb(
      'calls.start',
      action: 'calls.start',
      metadata: <String, Object?>{
        'participantCount': participantIds.length,
        'type': type.name,
      },
    );
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.startCall(
      participantIds: participantIds,
      type: type,
    );
    if (result.error != null) {
      result.logIfFailure(
        event: 'calls.start.failure',
        action: 'calls.start',
        source: 'CallsCubit',
        operation: 'startCall',
        metadata: <String, Object?>{
          'participantCount': participantIds.length,
          'type': type.name,
        },
      );
      emit(state.copyWith(busy: false, errorMessage: result.error!.message));
      return;
    }
    AppLogger.info(
      'Start call succeeded',
      event: 'calls.start.success',
      action: 'calls.start',
      metadata: <String, Object?>{
        'participantCount': participantIds.length,
        'type': type.name,
      },
    );
    emit(state.copyWith(busy: false, clearError: true));
  }

  Future<void> endCall(String callId) async {
    AppLogger.breadcrumb(
      'calls.end',
      action: 'calls.end',
      metadata: <String, Object?>{'callId': callId},
    );
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.endCall(callId: callId);
    if (result.error != null) {
      result.logIfFailure(
        event: 'calls.end.failure',
        action: 'calls.end',
        source: 'CallsCubit',
        operation: 'endCall',
        metadata: <String, Object?>{'callId': callId},
      );
      emit(state.copyWith(busy: false, errorMessage: result.error!.message));
      return;
    }
    AppLogger.info(
      'End call succeeded',
      event: 'calls.end.success',
      action: 'calls.end',
      metadata: <String, Object?>{'callId': callId},
    );
    emit(state.copyWith(busy: false, clearError: true));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
