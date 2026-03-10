import 'package:chatify/app/app.dart';
import 'package:chatify/app/flavor.dart';
import 'package:chatify/app/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots and shows auth entry', (tester) async {
    AppRouter.router.go('/auth');
    await tester.pumpWidget(const ChatifyApp(flavor: AppFlavor.dev));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
