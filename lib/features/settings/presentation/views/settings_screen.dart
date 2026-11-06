import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText, Theme;
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../../../core/first_run_config.dart';

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
      const MethodChannel(
        'apuntes/keyboard',
      ).invokeMethod<void>('setVolume', value).catchError((_) {}),
    );
  }

  Future<void> _chooseNotesDirectory() async {
    try {
      final path = await FirstRunConfig.chooseNotesDirectory(_notesDirectory);
      if (!mounted || path == null || path == _notesDirectory) return;
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

  String _themeName(AppTheme theme) => switch (theme) {
    AppTheme.claro => 'Claro',
    AppTheme.oscuro => 'Oscuro',
    AppTheme.sepia => 'Sepia',
    AppTheme.bosque => 'Bosque',
    AppTheme.gruvbox => 'Gruvbox Dark',
  };

  String _themeDescription(AppTheme theme) => switch (theme) {
    AppTheme.claro => 'Papel limpio con acentos azul tinta',
    AppTheme.oscuro => 'Grafito con azul frío y lavanda',
    AppTheme.sepia => 'Papel cálido y acentos cobre',
    AppTheme.bosque => 'Salvia suave y verde profundo',
    AppTheme.gruvbox => 'Oscuro cálido con acento naranja Gruvbox',
  };

  Color _themeColor(AppTheme theme) => switch (theme) {
    AppTheme.claro => const Color(0xff315f91),
    AppTheme.oscuro => const Color(0xffaac8ff),
    AppTheme.sepia => const Color(0xff8e5725),
    AppTheme.bosque => const Color(0xff356449),
    AppTheme.gruvbox => const Color(0xffd65d0e),
  };

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('Ajustes')),
    child: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('ALMACENAMIENTO'),
                backgroundColor: CupertinoTheme.of(
                  context,
                ).scaffoldBackgroundColor,
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
                                _notesDirectory,
                                maxLines: 2,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                header: const Text('APARIENCIA'),
                backgroundColor: CupertinoTheme.of(
                  context,
                ).scaffoldBackgroundColor,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                children: [
                  for (final theme in AppTheme.values)
                    CupertinoListTile(
                      leading: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _themeColor(theme),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      title: Text(_themeName(theme)),
                      subtitle: Text(_themeDescription(theme)),
                      trailing: AppAppearance.instance.selected == theme
                          ? const Icon(CupertinoIcons.check_mark, size: 18)
                          : null,
                      onTap: () => AppAppearance.instance.choose(theme),
                    ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('SONIDO'),
                backgroundColor: CupertinoTheme.of(
                  context,
                ).scaffoldBackgroundColor,
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
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
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
    ),
  );
}
