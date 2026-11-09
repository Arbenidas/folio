import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

enum AppTheme {
  claro('Claro', 'Papel limpio con acentos azul tinta'),
  oscuro('Oscuro', 'Grafito con azul frío y lavanda'),
  sepia('Sepia', 'Papel cálido y acentos cobre'),
  bosque('Bosque', 'Salvia suave y verde profundo'),
  gruvbox('Gruvbox Dark', 'Oscuro cálido con acento naranja Gruvbox'),
  crema('Crema', 'Papel crema con acentos verde oliva'),
  vivo('Vivo', 'Amarillo, violeta, verde lima y rosa');

  const AppTheme(this.label, this.description);

  final String label;
  final String description;
}

enum AppStyle {
  clasico('Clásico', 'Líneas finas y superficies limpias'),
  retro('Retro', 'Marcos de tinta y árbol de carpetas'),
  pop('Pop', 'Tarjetas redondeadas y sombras marcadas');

  const AppStyle(this.label, this.description);

  final String label;
  final String description;
}

class FolioStyle extends ThemeExtension<FolioStyle> {
  const FolioStyle(this.kind, this.theme, this.colors);

  static FolioStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FolioStyle>() ??
        FolioStyle(AppStyle.clasico, AppTheme.claro, theme.colorScheme);
  }

  final AppStyle kind;
  final AppTheme theme;
  final ColorScheme colors;
  bool get isGraphic => kind != AppStyle.clasico;
  bool get isRetro => kind == AppStyle.retro;
  bool get isPop => kind == AppStyle.pop;

  Color get ink => colors.onSurface;
  Color get shadow =>
      colors.brightness == Brightness.dark ? colors.shadow : ink;
  Color get accent => folderAccent(0);
  Color get onAccent => folderForeground(0);
  double get radius => isRetro ? 7 : 13;
  double get lineWidth => isRetro ? 2 : 2.5;

  RoundedRectangleBorder get outline => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: BorderSide(color: ink, width: lineWidth),
  );

  BoxDecoration panel(Color color, {double lift = 0}) => BoxDecoration(
    color: color,
    border: Border.all(color: ink, width: lineWidth),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      if (lift > 0) BoxShadow(color: shadow, offset: Offset(lift, lift)),
    ],
  );

  (Color, Color) _folderColors(int index) {
    final slot = index % 4;
    if (_ThemePalette.forTheme(theme).graphicAccents case final accents?) {
      return (accents[slot], colors.onSurface);
    }
    return switch (slot) {
      0 => (colors.secondaryContainer, colors.onSecondaryContainer),
      1 => (colors.primaryContainer, colors.onPrimaryContainer),
      2 => (colors.tertiaryContainer, colors.onTertiaryContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurface),
    };
  }

  Color folderAccent(int index) => _folderColors(index).$1;
  Color folderForeground(int index) => _folderColors(index).$2;

  @override
  FolioStyle copyWith({AppStyle? kind, AppTheme? theme, ColorScheme? colors}) =>
      FolioStyle(kind ?? this.kind, theme ?? this.theme, colors ?? this.colors);

  @override
  FolioStyle lerp(FolioStyle? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

class AppAppearance extends ChangeNotifier {
  AppAppearance._();
  static final AppAppearance instance = AppAppearance._();
  static const _channel = MethodChannel('apuntes/keyboard');

  AppTheme selected = AppTheme.claro;
  AppStyle style = AppStyle.clasico;

  Future<void> load() async {
    try {
      final saved = await _channel.invokeMapMethod<String, String>(
        'getAppearance',
      );
      if (saved == null) return;
      final name = saved['theme'];
      final (theme, fallbackStyle) = switch (name) {
        'retro' => (AppTheme.crema, AppStyle.retro),
        'pop' => (AppTheme.vivo, AppStyle.pop),
        _ => (
          AppTheme.values.firstWhere(
            (theme) => theme.name == name,
            orElse: () => AppTheme.claro,
          ),
          AppStyle.clasico,
        ),
      };
      selected = theme;
      style = AppStyle.values.firstWhere(
        (style) => style.name == saved['style'],
        orElse: () => fallbackStyle,
      );
      notifyListeners();
    } catch (_) {}
  }

  void choose(AppTheme theme) {
    selected = theme;
    notifyListeners();
    unawaited(_save());
  }

  void chooseStyle(AppStyle value) {
    style = value;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _channel.invokeMethod<void>('setAppearance', {
        'theme': selected.name,
        'style': style.name,
      });
    } catch (_) {}
  }
}

ThemeData buildEditorTheme([
  AppTheme theme = AppTheme.claro,
  AppStyle kind = AppStyle.clasico,
]) {
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
  final style = FolioStyle(kind, theme, scheme);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
    extensions: [style],
    dialogTheme: style.isGraphic
        ? DialogThemeData(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: style.outline,
          )
        : null,
    popupMenuTheme: style.isGraphic
        ? PopupMenuThemeData(shape: style.outline, elevation: 0)
        : null,
    filledButtonTheme: style.isGraphic
        ? FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: style.accent,
              foregroundColor: style.onAccent,
              shape: style.outline.copyWith(side: BorderSide.none),
              side: style.outline.side,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        : null,
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
    this.graphicAccents,
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
  final List<Color>? graphicAccents;

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
      primary: Color(0xfffe9c55),
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
    AppTheme.crema => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff28592f),
      onPrimary: Color(0xffffffff),
      secondary: Color(0xff4c5a39),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffbae5a2),
      onSecondaryContainer: Color(0xff232b1e),
      surface: Color(0xfff7f1e2),
      onSurface: Color(0xff292a22),
      surfaceLowest: Color(0xfffffbef),
      surfaceLow: Color(0xfff1ead7),
      surfaceMid: Color(0xffede5d0),
      surfaceHigh: Color(0xfff7f1e2),
      surfaceHighest: Color(0xffe4dbc3),
      outline: Color(0xff292a22),
    ),
    AppTheme.vivo => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff513393),
      onPrimary: Color(0xffffffff),
      secondary: Color(0xff7d2250),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffffda53),
      onSecondaryContainer: Color(0xff17131d),
      surface: Color(0xfffffaf1),
      onSurface: Color(0xff17131d),
      surfaceLowest: Color(0xffffffff),
      surfaceLow: Color(0xfff7f0ff),
      surfaceMid: Color(0xffffedab),
      surfaceHigh: Color(0xfffffaf1),
      surfaceHighest: Color(0xffe8daff),
      outline: Color(0xff17131d),
      graphicAccents: [
        Color(0xffffd430),
        Color(0xffa3e958),
        Color(0xffff87b3),
        Color(0xffc8b6ff),
      ],
    ),
  };
}

CupertinoThemeData buildEditorCupertinoTheme(ThemeData material) {
  final colorScheme = material.colorScheme;
  return CupertinoThemeData(
    brightness: material.brightness,
    primaryColor: colorScheme.primary,
    primaryContrastingColor: colorScheme.onPrimary,
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

MacosThemeData buildEditorMacosTheme(ThemeData material) {
  final colorScheme = material.colorScheme;
  return MacosThemeData(
    brightness: colorScheme.brightness,
    primaryColor: colorScheme.primary,
    typography: MacosTypography(color: colorScheme.onSurface),
    canvasColor: colorScheme.surface,
    dividerColor: colorScheme.outlineVariant,
  );
}
