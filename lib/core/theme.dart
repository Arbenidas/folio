import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

enum AppTheme { claro, oscuro, sepia, bosque, gruvbox }

class AppAppearance extends ChangeNotifier {
  AppAppearance._();
  static final AppAppearance instance = AppAppearance._();
  AppTheme selected = AppTheme.claro;

  Future<void> load() async {
    try {
      final name = await const MethodChannel(
        'apuntes/keyboard',
      ).invokeMethod<String>('getTheme');
      selected = AppTheme.values.firstWhere(
        (theme) => theme.name == name,
        orElse: () => AppTheme.claro,
      );
      notifyListeners();
    } catch (_) {}
  }

  void choose(AppTheme theme) {
    selected = theme;
    notifyListeners();
    const MethodChannel(
      'apuntes/keyboard',
    ).invokeMethod<void>('setTheme', theme.name);
  }
}

ThemeData buildEditorTheme([AppTheme theme = AppTheme.claro]) {
  final palette = _ThemePalette.forTheme(theme);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: palette.brightness,
      ).copyWith(
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        secondary: palette.secondary,
        onSecondary: palette.onSecondary,
        secondaryContainer: palette.secondaryContainer,
        onSecondaryContainer: palette.onSecondaryContainer,
        surface: palette.surface,
        onSurface: palette.onSurface,
        surfaceContainerLowest: palette.surfaceLowest,
        surfaceContainerLow: palette.surfaceLow,
        surfaceContainer: palette.surfaceMid,
        surfaceContainerHigh: palette.surfaceHigh,
        surfaceContainerHighest: palette.surfaceHighest,
        outlineVariant: palette.outline,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
  );
}

class _ThemePalette {
  const _ThemePalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceLowest,
    required this.surfaceLow,
    required this.surfaceMid,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.outline,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color surface;
  final Color onSurface;
  final Color surfaceLowest;
  final Color surfaceLow;
  final Color surfaceMid;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color outline;

  static _ThemePalette forTheme(AppTheme theme) => switch (theme) {
    AppTheme.claro => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff315f91),
      onPrimary: Color(0xffffffff),
      secondary: Color(0xff65798e),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffdce9f6),
      onSecondaryContainer: Color(0xff263e58),
      surface: Color(0xfffbfaf7),
      onSurface: Color(0xff252a30),
      surfaceLowest: Color(0xffffffff),
      surfaceLow: Color(0xfff2f2ef),
      surfaceMid: Color(0xffeeefec),
      surfaceHigh: Color(0xffe7e9e6),
      surfaceHighest: Color(0xffdfe2e0),
      outline: Color(0xffd1d5d6),
    ),
    AppTheme.oscuro => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xffaac8ff),
      onPrimary: Color(0xff1c3452),
      secondary: Color(0xffd2b9f3),
      onSecondary: Color(0xff382b4b),
      secondaryContainer: Color(0xff344054),
      onSecondaryContainer: Color(0xffe0eaff),
      surface: Color(0xff202126),
      onSurface: Color(0xffeeeef2),
      surfaceLowest: Color(0xff191a1f),
      surfaceLow: Color(0xff25272d),
      surfaceMid: Color(0xff2a2c33),
      surfaceHigh: Color(0xff30333a),
      surfaceHighest: Color(0xff3a3e47),
      outline: Color(0xff484c56),
    ),
    AppTheme.sepia => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff8e5725),
      onPrimary: Color(0xffffffff),
      secondary: Color(0xff795e42),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xfff1dfc4),
      onSecondaryContainer: Color(0xff4d3821),
      surface: Color(0xfff5ecdd),
      onSurface: Color(0xff433729),
      surfaceLowest: Color(0xfffff8ec),
      surfaceLow: Color(0xfff2e6d3),
      surfaceMid: Color(0xffeddfc9),
      surfaceHigh: Color(0xffe7d8c0),
      surfaceHighest: Color(0xffddcdb4),
      outline: Color(0xffd2bea2),
    ),
    AppTheme.bosque => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff356449),
      onPrimary: Color(0xffffffff),
      secondary: Color(0xff55766b),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffd4e8d8),
      onSecondaryContainer: Color(0xff244233),
      surface: Color(0xfff0f5ef),
      onSurface: Color(0xff26382e),
      surfaceLowest: Color(0xfffbfdf9),
      surfaceLow: Color(0xffe9f0e8),
      surfaceMid: Color(0xffe2ebe1),
      surfaceHigh: Color(0xffd9e5d9),
      surfaceHighest: Color(0xffcdddcf),
      outline: Color(0xffc2d2c5),
    ),
    AppTheme.gruvbox => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xffd65d0e),
      onPrimary: Color(0xff282828),
      secondary: Color(0xff83a598),
      onSecondary: Color(0xff282828),
      secondaryContainer: Color(0xff504945),
      onSecondaryContainer: Color(0xffebdbb2),
      surface: Color(0xff282828),
      onSurface: Color(0xffebdbb2),
      surfaceLowest: Color(0xff1d2021),
      surfaceLow: Color(0xff32302f),
      surfaceMid: Color(0xff3c3836),
      surfaceHigh: Color(0xff504945),
      surfaceHighest: Color(0xff665c54),
      outline: Color(0xff665c54),
    ),
  };
}

CupertinoThemeData buildEditorCupertinoTheme([
  AppTheme theme = AppTheme.claro,
]) {
  final material = buildEditorTheme(theme);
  final colorScheme = material.colorScheme;
  return CupertinoThemeData(
    brightness: material.brightness,
    primaryColor: colorScheme.primary,
    scaffoldBackgroundColor: material.scaffoldBackgroundColor,
    barBackgroundColor: material.scaffoldBackgroundColor.withValues(
      alpha: 0.96,
    ),
    textTheme: CupertinoTextThemeData(
      primaryColor: colorScheme.primary,
      // Cupertino's default label follows the macOS system appearance. Folio
      // themes are independent from that setting, so bind text to Folio's own
      // surface colors instead.
      textStyle: const CupertinoTextThemeData().textStyle.copyWith(
        color: colorScheme.onSurface,
      ),
    ),
  );
}

MacosThemeData buildEditorMacosTheme([AppTheme theme = AppTheme.claro]) {
  final material = buildEditorTheme(theme);
  final colorScheme = material.colorScheme;
  return MacosThemeData(
    brightness: colorScheme.brightness,
    primaryColor: colorScheme.primary,
    canvasColor: colorScheme.surface,
    dividerColor: colorScheme.outlineVariant,
  );
}
