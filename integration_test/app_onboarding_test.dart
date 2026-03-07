import 'package:chatify/app/app.dart';
import 'package:chatify/app/flavor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding flow lands on home tabs', (tester) async {
    await tester.pumpWidget(const ChatifyApp(flavor: AppFlavor.dev));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Continue in demo mode'));
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
  });
}
