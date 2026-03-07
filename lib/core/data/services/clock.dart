import 'package:injectable/injectable.dart';

@lazySingleton
class Clock {
  DateTime now() => DateTime.now().toUtc();
}
