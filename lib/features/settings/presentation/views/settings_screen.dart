import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText, Theme, Tooltip;
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../../../core/first_run_config.dart';
import '../../../../core/widgets/folio_window_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initialVolume,
    required this.onVolumeChanged,
    required this.initialNotesDirectory,
    required this.onNotesDirectoryChanged,
  });

  final double initialVolume;
  final ValueChanged<double> onVolumeChanged;
  final Directory initialNotesDirectory;
  final Future<void> Function(Directory directory) onNotesDirectoryChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _volume;
  late String _notesDirectory = widget.initialNotesDirectory.path;
  bool _changingDirectory = false;
  String? _directoryError;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume.clamp(0, 1);
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    widget.onVolumeChanged(value);
    unawaited(
      const MethodChannel('apuntes/keyboard')
          .invokeMethod<void>('setVolume', value)
          .catchError((_) {}),
    );
  }

  Future<void> _chooseNotesDirectory() async {
    try {
      final path = await FirstRunConfig.chooseNotesDirectory(_notesDirectory);
      if (!mounted || path == null || path == _notesDirectory) return;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Cambiar carpeta de Folio'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Se copiará tu cuaderno a $path/Folio y se conservará el actual como respaldo.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Copiar y cambiar'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      setState(() {
        _changingDirectory = true;
        _directoryError = null;
      });
      await widget.onNotesDirectoryChanged(Directory(path));
      if (mounted) {
        setState(() {
          _notesDirectory = path;
          _directoryError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _directoryError = 'No se pudo cambiar la carpeta: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _changingDirectory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESTILO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Elige la forma de la interfaz.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final kind in AppStyle.values) ...[
                          if (kind != AppStyle.values.first)
                            const SizedBox(width: 12),
                          Expanded(child: _StyleChoice(kind)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('TEMAS DE COLOR'),
                footer: const Text(
                  'Los colores se aplican al estilo que tengas seleccionado.',
                ),
                backgroundColor: CupertinoTheme.of(context)
                    .scaffoldBackgroundColor,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  for (final theme in AppTheme.values) _PaletteChoice(theme),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('ALMACENAMIENTO'),
                backgroundColor: CupertinoTheme.of(context)
                    .scaffoldBackgroundColor,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.folder,
                          color: Theme.of(context).colorScheme.primary,
                          size: 19,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Carpeta de notas',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                '$_notesDirectory/Folio',
                                maxLines: 2,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 10,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          onPressed: _changingDirectory
                              ? null
                              : _chooseNotesDirectory,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          minimumSize: Size.zero,
                          child: _changingDirectory
                              ? const CupertinoActivityIndicator()
                              : const Text('Cambiar…'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      'Folio copia tus notas a la nueva carpeta y conserva la carpeta anterior como respaldo.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_directoryError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(
                        _directoryError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('SONIDO'),
                backgroundColor: CupertinoTheme.of(context)
                    .scaffoldBackgroundColor,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(CupertinoIcons.keyboard, size: 18),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Sonido de teclas')),
                            Text('${(_volume * 100).round()}%'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CupertinoSlider(value: _volume, onChanged: _setVolume),
                        Text(
                          'Ajusta el volumen del sonido que acompaña al escribir.',
                          style: CupertinoTheme.of(context).textTheme.textStyle
                              .copyWith(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (FolioWindowChrome.isSupported) {
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            _windowToolbar(context),
            Expanded(child: content),
          ],
        ),
      );
    }
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Ajustes')),
      child: content,
    );
  }

  Widget _windowToolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    final foreground = style.isPop ? style.onAccent : colors.onSurface;
    return Container(
      width: double.infinity,
      height: FolioWindowChrome.toolbarHeight,
      decoration: BoxDecoration(
        color: style.isPop ? style.accent : colors.surface,
        border: Border(
          bottom: BorderSide(
            color: style.isGraphic ? style.ink : colors.outlineVariant,
            width: style.isGraphic ? style.lineWidth : 1,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Ajustes',
            style: TextStyle(
              color: foreground,
              fontFamily: style.isRetro ? 'Menlo' : null,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          PositionedDirectional(
            start: FolioWindowChrome.trafficLightInset,
            top: 0,
            bottom: 0,
            child: Tooltip(
              message: 'Volver',
              child: CupertinoButton(
                padding: const EdgeInsets.all(8),
                minimumSize: Size.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                child: Semantics(
                  label: 'Volver',
                  button: true,
                  child: Icon(CupertinoIcons.back, size: 18, color: foreground),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteChoice extends StatelessWidget {
  const _PaletteChoice(this.theme);

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final current = FolioStyle.of(context);
    final palette = buildEditorTheme(theme).extension<FolioStyle>()!;
    final colors = palette.colors;
    final selected = current.theme == theme;
    final roles = [
      ('Fondo', colors.surface),
      ('Editor', colors.surfaceContainerLowest),
      ('Panel lateral', colors.surfaceContainerLow),
      ('Barras', colors.surfaceContainer),
      ('Menús', colors.surfaceContainerHigh),
      ('Resaltado', colors.surfaceContainerHighest),
      ('Texto y tinta', colors.onSurface),
      ('Texto secundario', colors.onSurfaceVariant),
      ('Bordes', colors.outlineVariant),
      ('Sombra', palette.shadow),
      ('Acento principal', colors.primary),
      ('Texto sobre acento principal', colors.onPrimary),
      ('Acento suave', colors.primaryContainer),
      ('Texto sobre acento suave', colors.onPrimaryContainer),
      ('Acento secundario', colors.secondary),
      ('Texto sobre acento secundario', colors.onSecondary),
      ('Selección', colors.secondaryContainer),
      ('Texto sobre selección', colors.onSecondaryContainer),
      ('Soltar en carpeta', colors.tertiaryContainer),
      ('Texto al soltar', colors.onTertiaryContainer),
      ('Error', colors.error),
      ('Fondo de error', colors.errorContainer),
      ('Texto sobre fondo de error', colors.onErrorContainer),
      for (var index = 0; index < 4; index++) ...[
        ('Acento de tarjeta ${index + 1}', palette.folderAccent(index)),
        ('Texto de tarjeta ${index + 1}', palette.folderForeground(index)),
      ],
    ];
    final swatches = <Color, List<String>>{};
    for (final (role, color) in roles) {
      swatches.putIfAbsent(color, () => []).add(role);
    }
    return Semantics(
      selected: selected,
      child: CupertinoButton(
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
        minimumSize: Size.zero,
        onPressed: () => AppAppearance.instance.choose(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme.label,
                    style: TextStyle(
                      color: current.colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 17,
                    color: current.colors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              theme.description,
              style: TextStyle(
                color: current.colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final entry in swatches.entries)
                  Tooltip(
                    message: '${entry.value.join(' · ')}  ${_hex(entry.key)}',
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: entry.key,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: current.colors.onSurface.withValues(
                            alpha: 0.24,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _hex(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice(this.kind);

  final AppStyle kind;

  @override
  Widget build(BuildContext context) {
    final currentStyle = FolioStyle.of(context);
    final style = currentStyle.copyWith(kind: kind);
    final colors = style.colors;
    final selected = currentStyle.kind == kind;
    BoxDecoration panel(Color color, {double lift = 0}) => style.isGraphic
        ? style.panel(color, lift: lift)
        : BoxDecoration(
            color: color,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(7),
          );
    return Semantics(
      selected: selected,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => AppAppearance.instance.chooseStyle(kind),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Container(
                height: 83,
                padding: const EdgeInsets.fromLTRB(14, 12, 18, 16),
                decoration: panel(colors.surface),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: panel(colors.surface, lift: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 11,
                        decoration: BoxDecoration(
                          color: style.isPop
                              ? style.accent
                              : colors.surfaceContainerLow,
                          border: Border(bottom: BorderSide(color: style.ink)),
                        ),
                        alignment: Alignment.topLeft,
                        child: Icon(
                          CupertinoIcons.ellipsis,
                          size: 10,
                          color: style.isPop ? style.onAccent : style.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: DecoratedBox(
                                decoration: panel(
                                  style.isPop
                                      ? style.folderAccent(1)
                                      : colors.surfaceContainerLow,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              flex: 2,
                              child: DecoratedBox(
                                decoration: panel(
                                  colors.surfaceContainerLowest,
                                ),
                              ),
                            ),
                            if (style.isPop) ...[
                              const SizedBox(width: 5),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: panel(style.folderAccent(2)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind.label,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: 17,
                    color: colors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              kind.description,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
