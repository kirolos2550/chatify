import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

@injectable
class SearchCubit extends Cubit<String> {
  SearchCubit() : super('');

  void updateQuery(String value) => emit(value);
}
