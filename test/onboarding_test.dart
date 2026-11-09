import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/main.dart';
import 'package:folio/features/onboarding/presentation/views/initial_setup_screen.dart';

void main() {
  testWidgets('setup presents welcome, location preview, and back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        home: InitialSetupScreen(
          initialDirectory: Directory('/Users/example'),
          onComplete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido a Folio'), findsOneWidget);
    expect(find.text('PASO 1 DE 3'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/Users/example/Folio'), findsOneWidget);
    expect(find.text('PASO 2 DE 3'), findsOneWidget);

    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido a Folio'), findsOneWidget);
  });
}
