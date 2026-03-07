import 'package:chatify/app/bootstrap.dart';
import 'package:chatify/app/flavor.dart';

Future<void> main() async {
  await bootstrap(AppFlavor.prod);
}
