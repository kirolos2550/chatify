import 'package:chatify/app/flavor.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'initGetIt',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies(AppFlavor flavor) async {
  getIt.initGetIt(environment: flavor.nameValue);
}
