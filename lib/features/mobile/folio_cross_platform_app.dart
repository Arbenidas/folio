import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/widgets/folio_brand_icon.dart';
import '../cloud_sync/data/folio_cloud_sync_service.dart';
import '../cloud_sync/presentation/cloud_sync_dialog.dart';
import '../finance/domain/finance_models.dart';
import '../finance/presentation/controllers/finance_controller.dart';
import '../finance/presentation/views/finance_workspace.dart';
import '../onboarding/presentation/views/welcome_onboarding_screen.dart';
import '../updates/data/patch_notes_service.dart';
import '../updates/presentation/patch_notes_dialog.dart';
import 'cross_platform_notes_workspace.dart';

enum _CrossPlatformMode { finance, notes }

/// Unified Mobile (Android / iOS) and Web app shell for Folio.
/// Zero `dart:io` dependencies so the exact same experience runs on
/// Android, iOS, and Web browsers with responsive desktop/mobile layouts.
class FolioCrossPlatformApp extends StatefulWidget {
  const FolioCrossPlatformApp({super.key});

  @override
  State<FolioCrossPlatformApp> createState() => _FolioCrossPlatformAppState();
}

class _FolioCrossPlatformAppState extends State<FolioCrossPlatformApp> {
  static const _themePrefKey = 'folio_cross_platform_theme';
  static const _onboardedPrefKey = 'folio_web_mobile_onboarded_v1';

  final FinanceController _financeController = FinanceController();
  AppTheme _theme = AppTheme.noche;
  bool _prefsLoaded = false;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _financeController.attachCloudSync(FolioCloudSyncService.instance);
    unawaited(FolioCloudSyncService.instance.ensureInitialized());
    unawaited(_financeController.load());
    unawaited(_loadPrefs());
  }

  @override
  void dispose() {
    _financeController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themePrefKey);
      final done = prefs.getBool(_onboardedPrefKey) ?? false;
      if (mounted) {
        setState(() {
          if (savedTheme != null) {
            final found = AppTheme.values
                .where((t) => t.name == savedTheme)
                .firstOrNull;
            if (found != null) _theme = found;
          }
          _showOnboarding = !done;
          _prefsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _showOnboarding = false;
          _prefsLoaded = true;
        });
      }
    }
  }

  Future<void> _selectTheme(AppTheme next) async {
    setState(() => _theme = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themePrefKey, next.name);
    } catch (_) {}
  }

  Future<void> _completeOnboarding() async {
    setState(() => _showOnboarding = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardedPrefKey, true);
    } catch (_) {}
  }

  void _replayOnboarding() {
    setState(() => _showOnboarding = true);
  }

  @override
  Widget build(BuildContext context) {
    final materialTheme = buildEditorTheme(_theme, AppStyle.clasico);
    final cupertinoTheme = buildEditorCupertinoTheme(materialTheme);
    return MaterialApp(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: materialTheme,
      builder: (context, child) => CupertinoTheme(
        data: cupertinoTheme,
        child: child ?? const SizedBox.shrink(),
      ),
      home: !_prefsLoaded
          ? Scaffold(
              backgroundColor: materialTheme.colorScheme.surface,
              body: const Center(child: CupertinoActivityIndicator()),
            )
          : _showOnboarding
          ? WelcomeOnboardingScreen(
              selectedTheme: _theme,
              onSelectTheme: (t) => unawaited(_selectTheme(t)),
              onComplete: () => unawaited(_completeOnboarding()),
              financeController: _financeController,
            )
          : _FolioCrossPlatformHome(
              financeController: _financeController,
              selectedTheme: _theme,
              onSelectTheme: (t) => unawaited(_selectTheme(t)),
              onReplayOnboarding: _replayOnboarding,
            ),
    );
  }
}

class _FolioCrossPlatformHome extends StatefulWidget {
  const _FolioCrossPlatformHome({
    required this.financeController,
    required this.selectedTheme,
    required this.onSelectTheme,
    required this.onReplayOnboarding,
  });

  final FinanceController financeController;
  final AppTheme selectedTheme;
  final ValueChanged<AppTheme> onSelectTheme;
  final VoidCallback onReplayOnboarding;

  @override
  State<_FolioCrossPlatformHome> createState() =>
      _FolioCrossPlatformHomeState();
}

class _FolioCrossPlatformHomeState extends State<_FolioCrossPlatformHome> {
  final ValueNotifier<int> _financeTourTrigger = ValueNotifier<int>(0);
  final ValueNotifier<int> _notesTourTrigger = ValueNotifier<int>(0);

  _CrossPlatformMode _mode = _CrossPlatformMode.finance;
  RemoteUpdateManifest? _pendingUpdate;
  bool _dismissedBanner = false;

  @override
  void initState() {
    super.initState();
    FolioCloudSyncService.instance.addListener(_onAuthChanged);
    unawaited(_checkRemoteUpdates());
  }

  @override
  void dispose() {
    FolioCloudSyncService.instance.removeListener(_onAuthChanged);
    _financeTourTrigger.dispose();
    _notesTourTrigger.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _replayCurrentSectionTour() {
    if (_mode == _CrossPlatformMode.finance) {
      _financeTourTrigger.value++;
    } else {
      _notesTourTrigger.value++;
    }
  }

  Future<void> _checkRemoteUpdates() async {
    try {
      final res = await PatchNotesService.instance.checkForUpdates();
      if (mounted && res.hasUpdate && res.manifest != null) {
        setState(() => _pendingUpdate = res.manifest);
      }
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: _CrossPlatformSettingsDialog(
            financeController: widget.financeController,
            selectedTheme: widget.selectedTheme,
            currentModeLabel: _mode == _CrossPlatformMode.finance
                ? 'Finanzas'
                : 'Notas',
            onSelectTheme: widget.onSelectTheme,
            onOpenPatchNotes: () {
              Navigator.of(dialogContext).pop();
              unawaited(showPatchNotesDialog(context));
            },
            onReplaySectionTour: () {
              Navigator.of(dialogContext).pop();
              _replayCurrentSectionTour();
            },
            onReplayOnboarding: () {
              Navigator.of(dialogContext).pop();
              widget.onReplayOnboarding();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      body: Column(
        children: [
          // Slim universal top switcher: Folio icon + Finanzas | Notas + Ajustes
          SafeArea(
            bottom: false,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  const FolioBrandIcon(size: 24, borderRadius: 7),
                  const SizedBox(width: 8),
                  Text(
                    'Folio',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 14),
                  CupertinoSlidingSegmentedControl<_CrossPlatformMode>(
                    groupValue: _mode,
                    onValueChanged: (v) {
                      if (v != null) setState(() => _mode = v);
                    },
                    children: const {
                      _CrossPlatformMode.finance: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        child: Text(
                          'Finanzas',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      _CrossPlatformMode.notes: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        child: Text('Notas', style: TextStyle(fontSize: 12)),
                      ),
                    },
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Ajustes y cuenta',
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(9),
                      onPressed: () => unawaited(_openSettings()),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 17,
                                color: colors.onSurface,
                              ),
                              if (_pendingUpdate != null ||
                                  FolioCloudSyncService.instance.isSignedIn)
                                Positioned(
                                  right: -3,
                                  top: -3,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _pendingUpdate != null
                                          ? palette.accent
                                          : palette.positive,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (MediaQuery.sizeOf(context).width >= 480) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Ajustes',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Live Update Notification Banner
          if (_pendingUpdate != null && !_dismissedBanner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: palette.accent.withValues(alpha: 0.14),
              child: Row(
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 17,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Actualización v${_pendingUpdate!.version} disponible — toca para ver cambios e instalar.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(7),
                    onPressed: () => unawaited(showPatchNotesDialog(context)),
                    child: const Text(
                      'Actualizar',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    onPressed: () => setState(() => _dismissedBanner = true),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // Main Content (both Finance & Notes have live interactive section tours!)
          Expanded(
            child: _mode == _CrossPlatformMode.finance
                ? FinanceWorkspace(
                    controller: widget.financeController,
                    enableSectionTour: true,
                    replayTourTrigger: _financeTourTrigger,
                    onBudgetWarning: (msg) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    },
                  )
                : CrossPlatformNotesWorkspace(
                    enableSectionTour: true,
                    replayTourTrigger: _notesTourTrigger,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CrossPlatformSettingsDialog extends StatelessWidget {
  const _CrossPlatformSettingsDialog({
    required this.financeController,
    required this.selectedTheme,
    required this.currentModeLabel,
    required this.onSelectTheme,
    required this.onOpenPatchNotes,
    required this.onReplaySectionTour,
    required this.onReplayOnboarding,
  });

  final FinanceController financeController;
  final AppTheme selectedTheme;
  final String currentModeLabel;
  final ValueChanged<AppTheme> onSelectTheme;
  final VoidCallback onOpenPatchNotes;
  final VoidCallback onReplaySectionTour;
  final VoidCallback onReplayOnboarding;

  static const _themes = <(AppTheme, String)>[
    (AppTheme.noche, 'Noche'),
    (AppTheme.crema, 'Crema'),
    (AppTheme.oscuro, 'Oscuro'),
    (AppTheme.claro, 'Claro'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sync = FolioCloudSyncService.instance;

    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final signedIn = sync.isSignedIn;
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 19, color: colors.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Ajustes',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.all(6),
                      minimumSize: Size.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Account & Cloud Sign-In Section (inside Ajustes!)
                Text(
                  'CUENTA Y SINCRONIZACIÓN',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            signedIn
                                ? Icons.cloud_done_rounded
                                : Icons.person_outline_rounded,
                            size: 20,
                            color: signedIn ? palette.positive : palette.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signedIn
                                      ? (sync.userEmail ?? 'Cuenta conectada')
                                      : 'Sin sesión iniciada',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  signedIn
                                      ? 'Sincronizado en tiempo real con folio-2b7e3'
                                      : 'Inicia sesión con Google o correo para sincronizar tus dispositivos.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () {
                          Navigator.of(context).pop();
                          unawaited(
                            showCloudSyncDialog(
                              context,
                              financeController: financeController,
                            ),
                          );
                        },
                        child: Text(
                          signedIn
                              ? 'Administrar cuenta y nube'
                              : 'Iniciar sesión (Google o correo)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Theme Section
                Text(
                  'TEMA VISUAL',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _themes)
                      GestureDetector(
                        onTap: () => onSelectTheme(item.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selectedTheme == item.$1
                                ? palette.accent.withValues(alpha: 0.16)
                                : palette.cardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedTheme == item.$1
                                  ? palette.accent
                                  : palette.border,
                            ),
                          ),
                          child: Text(
                            item.$2,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: selectedTheme == item.$1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selectedTheme == item.$1
                                  ? palette.accent
                                  : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Patch Notes & Tours
                _SettingsActionRow(
                  icon: Icons.explore_rounded,
                  title: 'Recorrido interactivo de $currentModeLabel',
                  subtitle: 'Explicación paso a paso de cada sección',
                  onTap: onReplaySectionTour,
                ),
                const SizedBox(height: 8),
                _SettingsActionRow(
                  icon: Icons.waving_hand_rounded,
                  title: 'Ver recorrido de bienvenida',
                  subtitle: 'Repasar bienvenida, tema y cuenta',
                  onTap: onReplayOnboarding,
                ),
                const SizedBox(height: 8),
                _SettingsActionRow(
                  icon: Icons.new_releases_rounded,
                  title: 'Notas de parche y actualizaciones',
                  subtitle:
                      'v${AppVersionInfo.currentVersion} (build ${AppVersionInfo.currentBuild})',
                  onTap: onOpenPatchNotes,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: palette.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
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
              Icons.chevron_right_rounded,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
