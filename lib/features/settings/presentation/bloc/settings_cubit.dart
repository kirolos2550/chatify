import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

class SettingsState {
  const SettingsState({
    this.readReceiptsEnabled = true,
    this.lastSeenVisible = true,
  });

  final bool readReceiptsEnabled;
  final bool lastSeenVisible;

  SettingsState copyWith({bool? readReceiptsEnabled, bool? lastSeenVisible}) {
    return SettingsState(
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      lastSeenVisible: lastSeenVisible ?? this.lastSeenVisible,
    );
  }
}

@injectable
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(const SettingsState());

  void toggleReadReceipts(bool value) {
    emit(state.copyWith(readReceiptsEnabled: value));
  }
}
