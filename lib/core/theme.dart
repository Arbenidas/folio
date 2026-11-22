import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

enum AppTheme {
  claro('Claro', 'Papel limpio con acentos azul tinta'),
  oscuro('Oscuro', 'Grafito sereno con azul suave y lavanda'),
  crema('Crema', 'Papel cálido y tinta verde petróleo · Flexoki'),
  papel('Papel Cálido', 'Marfil suave con tinta cálida y acento terracota'),
  noche('Noche Cálida', 'Carbón suave de bajo contraste y ámbar cálido'),
  sepia('Sepia', 'Papel editorial cálido y acentos cobre'),
  bosque('Bosque', 'Salvia serena y verde profundo'),
  dawn('Rosé Pine Dawn', 'Crema rosado con acentos malva y terracota'),
  nord('Nord', 'Pizarra nórdica con acentos glaciales'),
  gruvbox('Gruvbox Dark', 'Oscuro cálido con acento naranja suave'),
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

enum EditorTypography {
  mono('Mono suave', 'Precisa para Markdown y código', 'Menlo'),
  serif('Literaria', 'Cálida para ensayos y escritura larga', 'Georgia'),
  sans('Moderna', 'Limpia y directa para notas diarias', null);

  const EditorTypography(this.label, this.description, this.fontFamily);

  final String label;
  final String description;
  final String? fontFamily;
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
  FolioStyle lerp(FolioStyle? other, double t) {
    if (other == null) return this;
    return FolioStyle(
      t < 0.5 ? kind : other.kind,
      t < 0.5 ? theme : other.theme,
      ColorScheme.lerp(colors, other.colors, t),
    );
  }
}

class AppAppearance extends ChangeNotifier {
  AppAppearance._();
  static final AppAppearance instance = AppAppearance._();
  static const _channel = MethodChannel('apuntes/keyboard');

  AppTheme selected = AppTheme.crema;
  AppStyle style = AppStyle.clasico;
  double uiScale = 1;
  EditorTypography editorTypography = EditorTypography.mono;
  double editorFontSize = 14.5;
  bool focusMode = false;

  Future<void> load() async {
    try {
      final saved = await _channel.invokeMapMethod<String, String>(
        'getAppearance',
      );
      if (saved != null) {
        final name = saved['theme'];
        final (theme, fallbackStyle) = switch (name) {
          'retro' => (AppTheme.crema, AppStyle.retro),
          'pop' => (AppTheme.vivo, AppStyle.pop),
          _ => (
            AppTheme.values.firstWhere(
              (theme) => theme.name == name,
              orElse: () => name == null ? AppTheme.crema : AppTheme.claro,
            ),
            AppStyle.clasico,
          ),
        };
        selected = theme;
        style = AppStyle.values.firstWhere(
          (style) => style.name == saved['style'],
          orElse: () => fallbackStyle,
        );
        final savedFont = saved['editorTypography'];
        if (savedFont != null) {
          editorTypography = EditorTypography.values.firstWhere(
            (item) => item.name == savedFont,
            orElse: () => EditorTypography.mono,
          );
        }
        final savedSize = double.tryParse(saved['editorFontSize'] ?? '');
        if (savedSize != null && savedSize >= 12 && savedSize <= 22) {
          editorFontSize = savedSize;
        }
        if (saved['focusMode'] == 'true') {
          focusMode = true;
        }
      }
      final scale = await _channel.invokeMethod<double>('getUiScale');
      if (scale != null && scale >= 0.8 && scale <= 1.2) uiScale = scale;
      notifyListeners();
    } catch (_) {}
  }

  void toggleFocusMode([bool? value]) {
    final next = value ?? !focusMode;
    if (focusMode == next) return;
    focusMode = next;
    notifyListeners();
    unawaited(_save());
  }

  void choose(AppTheme theme) {
    if (selected == theme) return;
    selected = theme;
    notifyListeners();
    unawaited(_save());
  }

  void chooseStyle(AppStyle value) {
    if (style == value) return;
    style = value;
    notifyListeners();
    unawaited(_save());
  }

  void chooseTypography(EditorTypography value) {
    if (editorTypography == value) return;
    editorTypography = value;
    notifyListeners();
    unawaited(_save());
  }

  void chooseEditorFontSize(double value) {
    final clamped = (value.clamp(12.0, 22.0) * 2).round() / 2;
    if ((editorFontSize - clamped).abs() < 0.01) return;
    editorFontSize = clamped;
    notifyListeners();
    unawaited(_save());
  }

  void adjustEditorFontSize(double delta) =>
      chooseEditorFontSize(editorFontSize + delta);

  void chooseUiScale(double value) {
    final clamped = value.clamp(0.8, 1.2).toDouble();
    if ((uiScale - clamped).abs() < 0.001) return;
    uiScale = clamped;
    notifyListeners();
    unawaited(
      _channel.invokeMethod<void>('setUiScale', uiScale).catchError((_) {}),
    );
  }

  Future<void> _save() async {
    try {
      await _channel.invokeMethod<void>('setAppearance', {
        'theme': selected.name,
        'style': style.name,
        if (editorTypography != EditorTypography.mono)
          'editorTypography': editorTypography.name,
        if ((editorFontSize - 14.5).abs() > 0.01)
          'editorFontSize': editorFontSize.toStringAsFixed(1),
        if (focusMode) 'focusMode': 'true',
      });
    } catch (_) {}
  }
}

ThemeData buildEditorTheme([
  AppTheme theme = AppTheme.claro,
  AppStyle kind = AppStyle.clasico,
]) {
  final palette = _ThemePalette.forTheme(theme);
  final seeded = ColorScheme.fromSeed(
    seedColor: palette.primary,
    brightness: palette.brightness,
  );
  final scheme = seeded.copyWith(
    primary: palette.primary,
    onPrimary: palette.onPrimary,
    primaryContainer: palette.primaryContainer ?? seeded.primaryContainer,
    onPrimaryContainer: palette.onPrimaryContainer ?? seeded.onPrimaryContainer,
    secondary: palette.secondary,
    onSecondary: palette.onSecondary,
    secondaryContainer: palette.secondaryContainer,
    onSecondaryContainer: palette.onSecondaryContainer,
    tertiary: palette.tertiary ?? seeded.tertiary,
    onTertiary: palette.onTertiary ?? seeded.onTertiary,
    tertiaryContainer: palette.tertiaryContainer ?? seeded.tertiaryContainer,
    onTertiaryContainer:
        palette.onTertiaryContainer ?? seeded.onTertiaryContainer,
    error: palette.error ?? seeded.error,
    surface: palette.surface,
    onSurface: palette.onSurface,
    onSurfaceVariant: Color.lerp(palette.onSurface, palette.surface, 0.35),
    surfaceContainerLowest: palette.surfaceLowest,
    surfaceContainerLow: palette.surfaceLow,
    surfaceContainer: palette.surfaceMid,
    surfaceContainerHigh: palette.surfaceHigh,
    surfaceContainerHighest: palette.surfaceHighest,
    outline: palette.outline,
    outlineVariant: Color.lerp(palette.outline, palette.surface, 0.25),
  );
  final style = FolioStyle(kind, theme, scheme);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    hoverColor: scheme.onSurface.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.06 : 0.04,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.34 : 0.22,
      ),
      selectionHandleColor: scheme.primary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: scheme.outlineVariant,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    extensions: [style],
    dialogTheme: style.isGraphic
        ? DialogThemeData(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: style.outline,
          )
        : DialogThemeData(
            backgroundColor: scheme.surfaceContainerLow,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
    popupMenuTheme: style.isGraphic
        ? PopupMenuThemeData(shape: style.outline, elevation: 0)
        : PopupMenuThemeData(
            color: scheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            elevation: 6,
          ),
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
    this.primaryContainer,
    this.onPrimaryContainer,
    this.tertiary,
    this.onTertiary,
    this.tertiaryContainer,
    this.onTertiaryContainer,
    this.error,
    this.graphicAccents,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color? primaryContainer;
  final Color? onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color? tertiary;
  final Color? onTertiary;
  final Color? tertiaryContainer;
  final Color? onTertiaryContainer;
  final Color? error;
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
    // 1. Claro — Crisp Alabaster canvas + pure white cards + refined Royal Indigo accent
    AppTheme.claro => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff2563eb),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffdbeafe),
      onPrimaryContainer: Color(0xff1e3a8a),
      secondary: Color(0xff475569),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffe2e8f0),
      onSecondaryContainer: Color(0xff0f172a),
      tertiary: Color(0xff0d9488),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffccfbf1),
      onTertiaryContainer: Color(0xff134e4a),
      error: Color(0xffdc2626),
      surface: Color(0xfff5f7fa),
      onSurface: Color(0xff0f172a),
      surfaceLowest: Color(0xffffffff),
      surfaceLow: Color(0xffeef2f6),
      surfaceMid: Color(0xffe2e8f0),
      surfaceHigh: Color(0xffcbd5e1),
      surfaceHighest: Color(0xff94a3b8),
      outline: Color(0xffcbd5e1),
    ),
    // 2. Papel — Warm Editorial Ivory + Terracotta & Sage (Craft / Bear feel)
    AppTheme.papel => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xffc25e3e),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xfffce8e1),
      onPrimaryContainer: Color(0xff692814),
      secondary: Color(0xff3f6a5b),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffdfece7),
      onSecondaryContainer: Color(0xff1c3b30),
      tertiary: Color(0xff7c5c94),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffefe6f6),
      onTertiaryContainer: Color(0xff3d274f),
      error: Color(0xffc93b37),
      surface: Color(0xfff7f4ee),
      onSurface: Color(0xff1f1c18),
      surfaceLowest: Color(0xfffffdf9),
      surfaceLow: Color(0xfff0ebe1),
      surfaceMid: Color(0xffe7e0d3),
      surfaceHigh: Color(0xffdcd3c4),
      surfaceHighest: Color(0xffcec3b2),
      outline: Color(0xffd6cdc0),
    ),
    // 3. Noche — Deep Obsidian Warm Dark + Luminous Amber & Emerald
    AppTheme.noche => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xfff59e0b),
      onPrimary: Color(0xff1c1305),
      primaryContainer: Color(0xff3b2a10),
      onPrimaryContainer: Color(0xfffde68a),
      secondary: Color(0xff34d399),
      onSecondary: Color(0xff08261c),
      secondaryContainer: Color(0xff163329),
      onSecondaryContainer: Color(0xffd1fae5),
      tertiary: Color(0xffa78bfa),
      onTertiary: Color(0xff1e1538),
      tertiaryContainer: Color(0xff2c224a),
      onTertiaryContainer: Color(0xffede9fe),
      error: Color(0xfff87171),
      surface: Color(0xff111214),
      onSurface: Color(0xfff3f1ed),
      surfaceLowest: Color(0xff0c0d0e),
      surfaceLow: Color(0xff18191c),
      surfaceMid: Color(0xff202226),
      surfaceHigh: Color(0xff292b30),
      surfaceHighest: Color(0xff35383f),
      outline: Color(0xff33363d),
    ),
    // 4. Oscuro — Linear / Raycast Carbon Slate + Crisp Sky Indigo
    AppTheme.oscuro => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xff60a5fa),
      onPrimary: Color(0xff0b192c),
      primaryContainer: Color(0xff1e3354),
      onPrimaryContainer: Color(0xffdbeafe),
      secondary: Color(0xffa78bfa),
      onSecondary: Color(0xff1f1638),
      secondaryContainer: Color(0xff282c3e),
      onSecondaryContainer: Color(0xffe2e8f0),
      tertiary: Color(0xff34d399),
      onTertiary: Color(0xff07291e),
      tertiaryContainer: Color(0xff15382c),
      onTertiaryContainer: Color(0xffd1fae5),
      error: Color(0xfff87171),
      surface: Color(0xff0f1117),
      onSurface: Color(0xfff1f5f9),
      surfaceLowest: Color(0xff0a0c10),
      surfaceLow: Color(0xff161922),
      surfaceMid: Color(0xff1e222e),
      surfaceHigh: Color(0xff262b3a),
      surfaceHighest: Color(0xff32384a),
      outline: Color(0xff2e3446),
    ),
    // 5. Sepia — Comfortable Daylight Reader + Copper Accent
    AppTheme.sepia => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff9a5822),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xfff5e3d0),
      onPrimaryContainer: Color(0xff4e290b),
      secondary: Color(0xff6b563f),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffefe2cf),
      onSecondaryContainer: Color(0xff3b2d1d),
      tertiary: Color(0xff3c6e57),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffdcece3),
      onTertiaryContainer: Color(0xff1b3a2b),
      error: Color(0xffbf3b32),
      surface: Color(0xfff6efe4),
      onSurface: Color(0xff2c241b),
      surfaceLowest: Color(0xfffffbf4),
      surfaceLow: Color(0xffefe6d8),
      surfaceMid: Color(0xffe7dccb),
      surfaceHigh: Color(0xffddd0bc),
      surfaceHighest: Color(0xffd1c2ab),
      outline: Color(0xffd2c3ad),
    ),
    // 6. Bosque — Botanical Mist + Deep Emerald Forest
    AppTheme.bosque => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff15803d),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffdcfce7),
      onPrimaryContainer: Color(0xff14532d),
      secondary: Color(0xff0f766e),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffccfbf1),
      onSecondaryContainer: Color(0xff134e4a),
      tertiary: Color(0xff854d0e),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xfffef3c7),
      onTertiaryContainer: Color(0xff422006),
      error: Color(0xffdc2626),
      surface: Color(0xfff2f6f3),
      onSurface: Color(0xff132219),
      surfaceLowest: Color(0xfffcfefd),
      surfaceLow: Color(0xffe8f0ea),
      surfaceMid: Color(0xffdde8e0),
      surfaceHigh: Color(0xffd0dfd4),
      surfaceHighest: Color(0xffbfd2c4),
      outline: Color(0xffc5d6c9),
    ),
    // 7. Gruvbox — Modernized Warm Retro Dark
    AppTheme.gruvbox => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xfffe8019),
      onPrimary: Color(0xff1d2021),
      primaryContainer: Color(0xff4c331e),
      onPrimaryContainer: Color(0xfffad7b8),
      secondary: Color(0xff8ec07c),
      onSecondary: Color(0xff1d2021),
      secondaryContainer: Color(0xff32382e),
      onSecondaryContainer: Color(0xffebdbb2),
      tertiary: Color(0xffd3869b),
      onTertiary: Color(0xff1d2021),
      tertiaryContainer: Color(0xff463038),
      onTertiaryContainer: Color(0xfff7dce4),
      error: Color(0xfffb4934),
      surface: Color(0xff1d2021),
      onSurface: Color(0xffebdbb2),
      surfaceLowest: Color(0xff161819),
      surfaceLow: Color(0xff262423),
      surfaceMid: Color(0xff32302f),
      surfaceHigh: Color(0xff3c3836),
      surfaceHighest: Color(0xff504945),
      outline: Color(0xff504945),
    ),
    // 8. Crema — Luminous Warm Linen + Deep Teal Petrol (Default Light Theme)
    AppTheme.crema => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff0f766e),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffd4f1ed),
      onPrimaryContainer: Color(0xff0c3d39),
      secondary: Color(0xff4f5d73),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffe6e3d8),
      onSecondaryContainer: Color(0xff202421),
      tertiary: Color(0xffb45309),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xfffde8d3),
      onTertiaryContainer: Color(0xff522404),
      error: Color(0xffc83a32),
      surface: Color(0xfff5f2ea),
      onSurface: Color(0xff1c1b18),
      surfaceLowest: Color(0xfffffefa),
      surfaceLow: Color(0xffede9df),
      surfaceMid: Color(0xffe5e0d4),
      surfaceHigh: Color(0xffdad4c6),
      surfaceHighest: Color(0xffccc5b5),
      outline: Color(0xffd8d2c5),
    ),
    // 9. Rosé Pine Dawn — Soft Blush Alabaster + Plum & Rose
    AppTheme.dawn => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff7e5794),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffede4f3),
      onPrimaryContainer: Color(0xff392347),
      secondary: Color(0xffb4637a),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xfff6e2e7),
      onSecondaryContainer: Color(0xff4f212e),
      tertiary: Color(0xff286983),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffd9ebf2),
      onTertiaryContainer: Color(0xff143947),
      error: Color(0xffb44b5e),
      surface: Color(0xfff9f5f0),
      onSurface: Color(0xff2c283e),
      surfaceLowest: Color(0xfffffdfb),
      surfaceLow: Color(0xfff2ece5),
      surfaceMid: Color(0xffebe3db),
      surfaceHigh: Color(0xffe2d9d0),
      surfaceHighest: Color(0xffd6cbc1),
      outline: Color(0xffdcd1c8),
    ),
    // 10. Nord — Arctic Midnight Slate + Frost Cyan
    AppTheme.nord => const _ThemePalette(
      brightness: Brightness.dark,
      primary: Color(0xff88c0d0),
      onPrimary: Color(0xff182029),
      primaryContainer: Color(0xff2a3b4c),
      onPrimaryContainer: Color(0xffe5f3f7),
      secondary: Color(0xffa3be8c),
      onSecondary: Color(0xff182029),
      secondaryContainer: Color(0xff2c3747),
      onSecondaryContainer: Color(0xffeceff4),
      tertiary: Color(0xffebcb8b),
      onTertiary: Color(0xff241f14),
      tertiaryContainer: Color(0xff3f392c),
      onTertiaryContainer: Color(0xfff9efd8),
      error: Color(0xffbf616a),
      surface: Color(0xff1e222a),
      onSurface: Color(0xffeceff4),
      surfaceLowest: Color(0xff171a21),
      surfaceLow: Color(0xff252a34),
      surfaceMid: Color(0xff2e3440),
      surfaceHigh: Color(0xff3b4252),
      surfaceHighest: Color(0xff434c5e),
      outline: Color(0xff3b4252),
    ),
    // 11. Vivo — Crisp Playful Pop
    AppTheme.vivo => const _ThemePalette(
      brightness: Brightness.light,
      primary: Color(0xff5b21b6),
      onPrimary: Color(0xffffffff),
      primaryContainer: Color(0xffede9fe),
      onPrimaryContainer: Color(0xff2e1065),
      secondary: Color(0xffbe185d),
      onSecondary: Color(0xffffffff),
      secondaryContainer: Color(0xffffe066),
      onSecondaryContainer: Color(0xff17131d),
      tertiary: Color(0xff15803d),
      onTertiary: Color(0xffffffff),
      tertiaryContainer: Color(0xffdcfce7),
      onTertiaryContainer: Color(0xff14532d),
      surface: Color(0xfffaf7f0),
      onSurface: Color(0xff17131d),
      surfaceLowest: Color(0xffffffff),
      surfaceLow: Color(0xfff3effb),
      surfaceMid: Color(0xffffefb3),
      surfaceHigh: Color(0xfffaf7f0),
      surfaceHighest: Color(0xffe9d5ff),
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
