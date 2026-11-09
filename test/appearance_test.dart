import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/theme.dart';
import 'package:folio/features/settings/presentation/views/settings_screen.dart';
import 'package:folio/main.dart';

void main() {
  testWidgets('Settings saves the style and palette independently', (
    tester,
  ) async {
    final appearance = AppAppearance.instance;
    final originalTheme = appearance.selected;
    final originalStyle = appearance.style;
    const channel = MethodChannel('apuntes/keyboard');
    final messenger = tester.binding.defaultBinaryMessenger;
    var saved = <String, String>{'theme': 'retro'};
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAppearance') return saved;
      if (call.method == 'setAppearance') {
        saved = Map<String, String>.from(call.arguments as Map);
      }
      return null;
    });
    addTearDown(() {
      appearance.selected = originalTheme;
      appearance.style = originalStyle;
      messenger.setMockMethodCallHandler(channel, null);
    });

    await appearance.load();
    expect(appearance.selected, AppTheme.crema);
    expect(appearance.style, AppStyle.retro);

    await tester.pumpWidget(
      MyApp(
        home: SettingsScreen(
          initialVolume: 0.68,
          onVolumeChanged: (_) {},
          initialNotesDirectory: Directory('/tmp'),
          onNotesDirectoryChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ESTILO'), findsOneWidget);
    expect(find.text('TEMAS DE COLOR'), findsOneWidget);
    final swatches = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.message?.contains('Acento principal  #315F91') == true,
    );
    expect(swatches, findsOneWidget);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(saved, {'theme': 'oscuro', 'style': 'retro'});
    final heading = tester.element(find.text('ESTILO'));
    expect(FolioStyle.of(heading).isRetro, isTrue);
    final darkColors = Theme.of(heading).colorScheme;
    expect(darkColors.brightness, Brightness.dark);

    await tester.tap(find.text('Pop'));
    await tester.pumpAndSettle();
    expect(saved, {'theme': 'oscuro', 'style': 'pop'});
    final updatedHeading = tester.element(find.text('ESTILO'));
    expect(FolioStyle.of(updatedHeading).isPop, isTrue);
    expect(Theme.of(updatedHeading).colorScheme, darkColors);

    appearance.selected = AppTheme.claro;
    appearance.style = AppStyle.clasico;
    await appearance.load();
    expect(appearance.selected, AppTheme.oscuro);
    expect(appearance.style, AppStyle.pop);

    saved = {'theme': 'pop'};
    await appearance.load();
    expect(appearance.selected, AppTheme.vivo);
    expect(appearance.style, AppStyle.pop);
    await tester.pumpWidget(const SizedBox());
  });
}
