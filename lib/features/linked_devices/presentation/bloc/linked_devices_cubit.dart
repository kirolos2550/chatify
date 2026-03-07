import 'dart:async';

import 'package:chatify/core/domain/entities/device.dart';
import 'package:chatify/core/domain/repositories/device_link_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class LinkedDevicesState {
  const LinkedDevicesState({
    this.items = const [],
    this.loading = true,
    this.busy = false,
    this.pendingLinkCode,
    this.errorMessage,
  });

  final List<Device> items;
  final bool loading;
  final bool busy;
  final String? pendingLinkCode;
  final String? errorMessage;

  LinkedDevicesState copyWith({
    List<Device>? items,
    bool? loading,
    bool? busy,
    String? pendingLinkCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LinkedDevicesState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      pendingLinkCode: pendingLinkCode ?? this.pendingLinkCode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

@injectable
class LinkedDevicesCubit extends Cubit<LinkedDevicesState> {
  LinkedDevicesCubit(this._repository) : super(const LinkedDevicesState()) {
    _subscription = _repository.watchLinkedDevices().listen(
      (items) =>
          emit(state.copyWith(items: items, loading: false, clearError: true)),
      onError: (Object error, StackTrace stackTrace) {
        emit(state.copyWith(loading: false, errorMessage: error.toString()));
      },
    );
  }

  final DeviceLinkRepository _repository;
  StreamSubscription<List<Device>>? _subscription;

  Future<void> startLinkFlow() async {
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.linkDeviceStart();
    if (result.error != null) {
      emit(state.copyWith(busy: false, errorMessage: result.error!.message));
      return;
    }
    emit(
      state.copyWith(
        busy: false,
        pendingLinkCode: result.data,
        clearError: true,
      ),
    );
  }

  Future<void> confirmLinkCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(errorMessage: 'Link code is required'));
      return;
    }
    emit(state.copyWith(busy: true, clearError: true));
    final result = await _repository.linkDeviceConfirm(linkCode: trimmed);
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
