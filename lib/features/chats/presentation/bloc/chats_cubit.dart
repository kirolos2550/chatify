import 'dart:async';

import 'package:chatify/core/domain/entities/conversation.dart';
import 'package:chatify/core/domain/repositories/conversation_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class ChatsState {
  const ChatsState({
    this.items = const [],
    this.loading = true,
    this.errorMessage,
  });

  final List<Conversation> items;
  final bool loading;
  final String? errorMessage;

  ChatsState copyWith({
    List<Conversation>? items,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

@injectable
class ChatsCubit extends Cubit<ChatsState> {
  ChatsCubit(this._repository) : super(const ChatsState()) {
    _subscription = _repository.watchConversations().listen(
      (items) => emit(
        state.copyWith(
          items: items,
          loading: false,
          clearError: true,
        ),
      ),
      onError: (Object error, StackTrace stackTrace) {
        emit(
          state.copyWith(
            items: const [],
            loading: false,
            errorMessage: error.toString(),
          ),
        );
      },
    );
  }

  final ConversationRepository _repository;
  StreamSubscription<List<Conversation>>? _subscription;

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
