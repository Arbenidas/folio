import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../../core/first_run_config.dart';
import '../../../../core/theme.dart';
import '../../../editor/data/file_repository.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({
    super.key,
    required this.initialDirectory,
    required this.onComplete,
  });

  final Directory initialDirectory;
  final VoidCallback onComplete;

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  late String _directoryPath = widget.initialDirectory.path;
  AppTheme _theme = AppAppearance.instance.selected;
  bool _busy = false;
  String? _error;

  Future<void> _chooseDirectory() async {
    try {
      final path = await FirstRunConfig.chooseNotesDirectory(_directoryPath);
      if (!mounted || path == null) return;
      setState(() {
        _directoryPath = path;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir esa carpeta: $error');
      }
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final directory = Directory(_directoryPath);
      await FileRepository.preserveDefaultNotesIn(directory);
      await directory.create(recursive: true);
      NotesStorage.directory = directory;
      await FirstRunConfig.finish(_directoryPath);
      if (mounted) widget.onComplete();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo preparar la carpeta de notas: $error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(34),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.12),
                      blurRadius: 34,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/branding/markdown-icon.png',
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BIENVENIDO A FOLIO',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Preparemos tu espacio',
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Elige dónde guardar tus apuntes y el tema con el que quieres escribir. Puedes cambiar ambas opciones más adelante.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Container(
                        height: 1,
                        color: colors.outlineVariant.withValues(alpha: 0.75),
                      ),
                    ),
                    Row(
                      children: [
                        _SectionGlyph(
                          icon: CupertinoIcons.folder,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionTitle(title: 'Carpeta de notas'),
                              const SizedBox(height: 3),
                              Text(
                                'Tus apuntes se guardarán aquí como archivos locales.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.folder_fill,
                            color: colors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SelectableText(
                              _directoryPath,
                              maxLines: 2,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            onPressed: _busy ? null : _chooseDirectory,
                            child: const Text('Elegir carpeta'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _SectionGlyph(
                          icon: CupertinoIcons.sun_max,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(title: 'Tema'),
                            const SizedBox(height: 3),
                            Text(
                              'Elige el aspecto que prefieras.',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: AppTheme.values.map((theme) {
                        final selected = theme == _theme;
                        return _ThemeChoice(
                          theme: theme,
                          selected: selected,
                          onTap: () {
                            setState(() => _theme = theme);
                            AppAppearance.instance.choose(theme);
                          },
                        );
                      }).toList(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_circle,
                              color: colors.error,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tus preferencias se guardan en este Mac.',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          CupertinoButton.filled(
                            onPressed: _busy ? null : _finish,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_busy)
                                  const CupertinoActivityIndicator(
                                    color: CupertinoColors.white,
                                  )
                                else ...[
                                  const Text('Empezar a escribir'),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    CupertinoIcons.arrow_right,
                                    size: 14,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _SectionGlyph extends StatelessWidget {
  const _SectionGlyph({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 17, color: color),
  );
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, background, foreground, accent) = switch (theme) {
      AppTheme.claro => (
        'Claro',
        const Color(0xfffbfaf7),
        const Color(0xff252a30),
        const Color(0xff315f91),
      ),
      AppTheme.oscuro => (
        'Oscuro',
        const Color(0xff202126),
        const Color(0xffeeeef2),
        const Color(0xffaac8ff),
      ),
      AppTheme.sepia => (
        'Sepia',
        const Color(0xfff5ecdd),
        const Color(0xff433729),
        const Color(0xff8e5725),
      ),
      AppTheme.bosque => (
        'Bosque',
        const Color(0xfff0f5ef),
        const Color(0xff26382e),
        const Color(0xff356449),
      ),
      AppTheme.gruvbox => (
        'Gruvbox Dark',
        const Color(0xff282828),
        const Color(0xffebdbb2),
        const Color(0xffd65d0e),
      ),
    };
    return MacosTooltip(
      message: 'Usar tema $label',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 156,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(CupertinoIcons.check_mark, size: 13, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Aa',
                    style: TextStyle(
                      color: foreground,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 4,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 79,
                          height: 3,
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
