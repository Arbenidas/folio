import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show ColorScheme, Colors, SelectableText, Theme, Tooltip;
import 'package:flutter/services.dart';

import '../../../../core/first_run_config.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/folio_dialogs.dart';
import '../../../../core/widgets/folio_window_chrome.dart';
import '../../../blog_publication/presentation/blog_account.dart';
import '../../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../../../cloud_sync/presentation/cloud_sync_dialog.dart';
import '../../../editor/presentation/widgets/editor_motion.dart';
import '../../../updates/data/patch_notes_service.dart';
import '../../../updates/presentation/patch_notes_dialog.dart';

class SettingsQuickActions {
  const SettingsQuickActions({
    required this.onSearch,
    required this.onDailyNote,
    required this.onTemplates,
    required this.onOpenOutline,
    required this.onImportMarkdown,
    required this.onExportMarkdown,
    required this.onExportHtml,
    required this.onExportPdf,
    required this.onRecoveredDrafts,
    required this.recoveredCount,
    required this.onTrash,
    required this.onHelp,
  });

  final VoidCallback onSearch;
  final VoidCallback onDailyNote;
  final VoidCallback onTemplates;
  final VoidCallback onOpenOutline;
  final VoidCallback onImportMarkdown;
  final VoidCallback onExportMarkdown;
  final VoidCallback onExportHtml;
  final VoidCallback onExportPdf;
  final VoidCallback onRecoveredDrafts;
  final int recoveredCount;
  final VoidCallback onTrash;
  final VoidCallback onHelp;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initialVolume,
    required this.onVolumeChanged,
    required this.initialNotesDirectory,
    required this.onNotesDirectoryChanged,
    this.embedded = false,
    this.onClose,
    this.quickActions,
  });

  final double initialVolume;
  final ValueChanged<double> onVolumeChanged;
  final Directory initialNotesDirectory;
  final Future<void> Function(Directory directory) onNotesDirectoryChanged;
  final bool embedded;
  final VoidCallback? onClose;
  final SettingsQuickActions? quickActions;

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
      final confirmed = await showFolioConfirmDialog(
        context,
        title: 'Cambiar carpeta de Folio',
        message:
            'Se copiará tu cuaderno a $path/Folio y se conservará el actual como respaldo.',
        actionLabel: 'Copiar y cambiar',
        destructive: false,
      );
      if (!mounted || !confirmed) return;
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppAppearance.instance,
    builder: (context, _) {
      if (widget.embedded) return _embeddedInspector(context);

      final content = SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
              children: [
                _cloudAccountBannerButton(context),
                const SizedBox(height: 10),
                _patchNotesBannerButton(context),
                const SizedBox(height: 14),
                const BlogIntegrationSection(),
                _styleSection(context),
                _uiScaleSection(context),
                _themesSection(context),
                _writingSection(context),
                _storageSection(context),
                _soundSection(context),
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
    },
  );

  Widget _cloudAccountBannerButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: FolioCloudSyncService.instance,
      builder: (context, _) {
        final sync = FolioCloudSyncService.instance;
        final signedIn = sync.isSignedIn;
        return CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => unawaited(showCloudSyncDialog(context)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: signedIn
                    ? colors.primary.withValues(alpha: 0.45)
                    : colors.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  signedIn
                      ? CupertinoIcons.cloud_fill
                      : CupertinoIcons.person_crop_circle_badge_plus,
                  size: 17,
                  color: colors.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signedIn ? 'Cuenta conectada' : 'Iniciar sesión',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        signedIn
                            ? (sync.userEmail ?? 'Sincronizado en folio-2b7e3')
                            : 'Google o correo · Sincroniza Mac, móvil y Web',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _patchNotesBannerButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => unawaited(showPatchNotesDialog(context)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.sparkles,
              size: 16,
              color: colors.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notas de parche y actualizaciones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    'v${AppVersionInfo.currentVersion} (build ${AppVersionInfo.currentBuild})',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Live right-hand inspector sidebar so users watch their real editor update
  /// immediately while switching themes, style, typography, and scale.
  Widget _embeddedInspector(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FolioStyle.of(context);
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            decoration: BoxDecoration(
              color: style.isGraphic ? colors.surfaceContainer : null,
              border: Border(
                bottom: BorderSide(
                  color: style.isGraphic ? style.ink : colors.outlineVariant,
                  width: style.isGraphic ? style.lineWidth : 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.slider_horizontal_3,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  'AJUSTES',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: style.isRetro ? 'Menlo' : null,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'En vivo',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Cerrar ajustes (⌘,)',
                  child: AppIconButton(
                    semanticLabel: 'Cerrar ajustes',
                    icon: CupertinoIcons.xmark,
                    size: 15,
                    padding: const EdgeInsets.all(5),
                    onPressed: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _cloudAccountBannerButton(context),
                const SizedBox(height: 10),
                _patchNotesBannerButton(context),
                const SizedBox(height: 16),
                if (widget.quickActions case final actions?) ...[
                  _embeddedSectionTitle(
                    'ACCIONES Y ARCHIVO',
                    'Herramientas rápidas, exportación y cuaderno.',
                    colors,
                  ),
                  const SizedBox(height: 10),
                  _quickActionsSection(actions, colors),
                  const SizedBox(height: 20),
                ],
                _embeddedSectionTitle(
                  'TEMAS DE COLOR',
                  'Toca un tema y mira el cambio en tu editor al instante.',
                  colors,
                ),
                const SizedBox(height: 10),
                _embeddedThemesGrid(colors),
                const SizedBox(height: 20),
                _embeddedSectionTitle(
                  'ESTILO',
                  'Elige la forma de la interfaz.',
                  colors,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final kind in AppStyle.values) ...[
                      if (kind != AppStyle.values.first)
                        const SizedBox(width: 8),
                      Expanded(child: _StyleChoice(kind, compact: true)),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _embeddedSectionTitle(
                  'ESCRITURA',
                  'Atajos rápidos: ⌘+ / ⌘− para tamaño, ⌘⇧F Modo Enfoque.',
                  colors,
                ),
                const SizedBox(height: 10),
                _embeddedCard(
                  colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          for (final font in EditorTypography.values) ...[
                            if (font != EditorTypography.values.first)
                              const SizedBox(width: 6),
                            Expanded(child: _TypographyChoice(font)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Modo Enfoque',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  'Atenúa otros párrafos y añade margen inferior.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            value: AppAppearance.instance.focusMode,
                            activeTrackColor: colors.primary,
                            onChanged: AppAppearance.instance.toggleFocusMode,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Tamaño del texto',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${AppAppearance.instance.editorFontSize.toStringAsFixed(1)} pt',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      CupertinoSlider(
                        min: 12,
                        max: 22,
                        divisions: 20,
                        value: AppAppearance.instance.editorFontSize,
                        onChanged:
                            AppAppearance.instance.chooseEditorFontSize,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _embeddedSectionTitle('INTERFAZ Y SONIDO', null, colors),
                const SizedBox(height: 10),
                _embeddedCard(
                  colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Escala de interfaz',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(AppAppearance.instance.uiScale * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      CupertinoSlider(
                        min: 0.8,
                        max: 1.2,
                        divisions: 8,
                        value: AppAppearance.instance.uiScale,
                        onChanged: AppAppearance.instance.chooseUiScale,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.keyboard,
                            size: 15,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'Sonido de teclas',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_volume * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      CupertinoSlider(value: _volume, onChanged: _setVolume),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _embeddedSectionTitle('ALMACENAMIENTO', null, colors),
                const SizedBox(height: 10),
                _embeddedCard(
                  colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.folder,
                            color: colors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Carpeta de notas',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            onPressed: _changingDirectory
                                ? null
                                : _chooseNotesDirectory,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            child: _changingDirectory
                                ? const CupertinoActivityIndicator()
                                : const Text(
                                    'Cambiar…',
                                    style: TextStyle(fontSize: 12),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        '$_notesDirectory/Folio',
                        maxLines: 2,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                      if (_directoryError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _directoryError!,
                          style: TextStyle(color: colors.error, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const BlogIntegrationSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsSection(
    SettingsQuickActions actions,
    ColorScheme colors,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _QuickActionTile(
              icon: CupertinoIcons.search,
              label: 'Buscar',
              shortcut: '⌘K',
              onTap: actions.onSearch,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _QuickActionTile(
              icon: CupertinoIcons.calendar_today,
              label: 'Hoy',
              shortcut: '⌘D',
              onTap: actions.onDailyNote,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _QuickActionTile(
              icon: CupertinoIcons.doc_on_doc,
              label: 'Plantillas',
              onTap: actions.onTemplates,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _embeddedCard(
        colors,
        child: Column(
          children: [
            _ActionRowItem(
              icon: CupertinoIcons.list_bullet_indent,
              label: 'Índice, etiquetas y enlaces',
              trailing: '⌘⇧O',
              onTap: actions.onOpenOutline,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.doc_richtext,
              label: 'Exportar como PDF (tema actual)',
              onTap: actions.onExportPdf,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.globe,
              label: 'Exportar como HTML (tema actual)',
              onTap: actions.onExportHtml,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.arrow_up_to_line,
              label: 'Exportar nota como .md',
              onTap: actions.onExportMarkdown,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.arrow_down_to_line,
              label: 'Importar .md / .txt',
              onTap: actions.onImportMarkdown,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.clock,
              label: 'Notas recuperadas',
              trailing: actions.recoveredCount > 0
                  ? '${actions.recoveredCount}'
                  : null,
              onTap: actions.onRecoveredDrafts,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.trash,
              label: 'Papelera',
              onTap: actions.onTrash,
            ),
            _rowDivider(colors),
            _ActionRowItem(
              icon: CupertinoIcons.question_circle,
              label: 'Guía rápida y atajos',
              trailing: 'F1',
              onTap: actions.onHelp,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _rowDivider(ColorScheme colors) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 2),
    color: colors.outlineVariant.withValues(alpha: 0.45),
  );

  Widget _embeddedSectionTitle(
    String title,
    String? subtitle,
    ColorScheme colors,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: colors.onSurfaceVariant,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11.5,
            color: colors.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ],
    ],
  );

  Widget _embeddedCard(ColorScheme colors, {required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: child,
      );

  Widget _embeddedThemesGrid(ColorScheme colors) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 300 ? 2 : 1;
      const spacing = 8.0;
      final itemWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final theme in AppTheme.values)
            SizedBox(
              width: itemWidth,
              child: _CompactThemeTile(theme),
            ),
        ],
      );
    },
  );

  Widget _styleSection(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ESTILO',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
              if (kind != AppStyle.values.first) const SizedBox(width: 12),
              Expanded(child: _StyleChoice(kind)),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _uiScaleSection(BuildContext context) =>
      CupertinoListSection.insetGrouped(
        header: const Text('TAMAÑO DE INTERFAZ'),
        footer: const Text(
          'Ajusta el tamaño de botones, paneles y texto en Folio.',
        ),
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Escala de la interfaz')),
                    Text('${(AppAppearance.instance.uiScale * 100).round()}%'),
                  ],
                ),
                CupertinoSlider(
                  min: 0.8,
                  max: 1.2,
                  divisions: 8,
                  value: AppAppearance.instance.uiScale,
                  onChanged: AppAppearance.instance.chooseUiScale,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Más pequeña',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Más grande',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _themesSection(BuildContext context) =>
      CupertinoListSection.insetGrouped(
        header: const Text('TEMAS DE COLOR'),
        footer: const Text(
          'Los colores se aplican al estilo que tengas seleccionado.',
        ),
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        children: [for (final theme in AppTheme.values) _PaletteChoice(theme)],
      );

  Widget _writingSection(BuildContext context) =>
      CupertinoListSection.insetGrouped(
        header: const Text('ESCRITURA'),
        footer: const Text(
          'Atajos rápidos en el editor: ⌘+ y ⌘− cambian el tamaño del texto, ⌘0 lo restablece.',
        ),
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tipografía al escribir',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final font in EditorTypography.values) ...[
                      if (font != EditorTypography.values.first)
                        const SizedBox(width: 8),
                      Expanded(child: _TypographyChoice(font)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Tamaño de texto del editor')),
                    Text(
                      '${AppAppearance.instance.editorFontSize.toStringAsFixed(1)} pt',
                    ),
                  ],
                ),
                CupertinoSlider(
                  min: 12,
                  max: 22,
                  divisions: 20,
                  value: AppAppearance.instance.editorFontSize,
                  onChanged: AppAppearance.instance.chooseEditorFontSize,
                ),
              ],
            ),
          ),
        ],
      );

  Widget _storageSection(BuildContext context) =>
      CupertinoListSection.insetGrouped(
        header: const Text('ALMACENAMIENTO'),
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  onPressed: _changingDirectory ? null : _chooseNotesDirectory,
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
      );

  Widget _soundSection(BuildContext context) =>
      CupertinoListSection.insetGrouped(
        header: const Text('SONIDO'),
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      );

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

class _QuickActionTile extends StatefulWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 130),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.secondaryContainer
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? colors.primary.withValues(alpha: 0.45)
                  : colors.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(widget.icon, size: 17, color: colors.primary),
              const SizedBox(height: 5),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              if (widget.shortcut != null)
                Text(
                  widget.shortcut!,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRowItem extends StatefulWidget {
  const _ActionRowItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  State<_ActionRowItem> createState() => _ActionRowItemState();
}

class _ActionRowItemState extends State<_ActionRowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onTap,
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 110),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.surfaceContainerHigh.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 14.5,
                color: _hovered ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (widget.trailing != null)
                Text(
                  widget.trailing!,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactThemeTile extends StatefulWidget {
  const _CompactThemeTile(this.theme);

  final AppTheme theme;

  @override
  State<_CompactThemeTile> createState() => _CompactThemeTileState();
}

class _CompactThemeTileState extends State<_CompactThemeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final current = FolioStyle.of(context);
    final preview = buildEditorTheme(widget.theme).colorScheme;
    final selected = current.theme == widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => AppAppearance.instance.choose(widget.theme),
        child: AnimatedContainer(
          duration: EditorMotion.duration(context, 150),
          curve: EditorMotion.curve,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: preview.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? current.colors.primary
                  : _hovered
                  ? preview.primary.withValues(alpha: 0.7)
                  : preview.outlineVariant,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: current.colors.primary.withValues(alpha: 0.16),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini editor mockup bar inside the theme tile
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: preview.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: preview.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 4,
                      decoration: BoxDecoration(
                        color: preview.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 22,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: preview.onSurface.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: preview.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: preview.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.theme.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: preview.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      size: 14,
                      color: preview.primary,
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

class _TypographyChoice extends StatelessWidget {
  const _TypographyChoice(this.typography);

  final EditorTypography typography;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = AppAppearance.instance.editorTypography == typography;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => AppAppearance.instance.chooseTypography(typography),
      child: AnimatedContainer(
        duration: EditorMotion.duration(context, 150),
        curve: EditorMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontFamily: typography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              typography.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurface,
              ),
            ),
          ],
        ),
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
  const _StyleChoice(this.kind, {this.compact = false});

  final AppStyle kind;
  final bool compact;

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
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
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
                height: compact ? 60 : 83,
                padding: compact
                    ? const EdgeInsets.fromLTRB(8, 7, 10, 9)
                    : const EdgeInsets.fromLTRB(14, 12, 18, 16),
                decoration: panel(colors.surface),
                child: Container(
                  padding: EdgeInsets.all(compact ? 4 : 6),
                  decoration: panel(colors.surface, lift: compact ? 2.5 : 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: compact ? 8 : 11,
                        decoration: BoxDecoration(
                          color: style.isPop
                              ? style.accent
                              : colors.surfaceContainerLow,
                          border: Border(bottom: BorderSide(color: style.ink)),
                        ),
                        alignment: Alignment.topLeft,
                        child: Icon(
                          CupertinoIcons.ellipsis,
                          size: compact ? 8 : 10,
                          color: style.isPop ? style.onAccent : style.ink,
                        ),
                      ),
                      SizedBox(height: compact ? 3 : 5),
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
                            SizedBox(width: compact ? 3 : 5),
                            Expanded(
                              flex: 2,
                              child: DecoratedBox(
                                decoration: panel(
                                  colors.surfaceContainerLowest,
                                ),
                              ),
                            ),
                            if (style.isPop) ...[
                              SizedBox(width: compact ? 3 : 5),
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
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    size: compact ? 14 : 17,
                    color: colors.primary,
                  ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 3),
              Text(
                kind.description,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
