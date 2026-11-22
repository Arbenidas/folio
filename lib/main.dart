import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'core/first_run_config.dart';
import 'core/theme.dart';
import 'features/blog_publication/data/blog_connection.dart';
import 'features/cloud_sync/data/folio_cloud_sync_service.dart';
import 'features/editor/presentation/views/editor_screen.dart';
import 'features/mobile/folio_cross_platform_app.dart';
import 'features/onboarding/presentation/views/initial_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FolioCloudSyncService.instance.ensureInitialized();
  final isMobileOrWeb =
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (isMobileOrWeb) {
    runApp(const ProviderScope(child: FolioCrossPlatformApp()));
    return;
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.home});

  final Widget? home;
  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final appearance = AppAppearance.instance;
  AppTheme? _cachedThemeKey;
  AppStyle? _cachedStyleKey;
  late ThemeData _cachedMaterialTheme;
  late MacosThemeData _cachedMacosTheme;
  late CupertinoThemeData _cachedCupertinoTheme;

  @override
  void initState() {
    super.initState();
    _ensureThemeCache();
    appearance.addListener(_changed);
  }

  void _ensureThemeCache() {
    if (_cachedThemeKey == appearance.selected &&
        _cachedStyleKey == appearance.style) {
      return;
    }
    _cachedThemeKey = appearance.selected;
    _cachedStyleKey = appearance.style;
    _cachedMaterialTheme = buildEditorTheme(
      appearance.selected,
      appearance.style,
    );
    _cachedMacosTheme = buildEditorMacosTheme(_cachedMaterialTheme);
    _cachedCupertinoTheme = buildEditorCupertinoTheme(_cachedMaterialTheme);
  }

  void _changed() {
    if (mounted) setState(_ensureThemeCache);
  }

  @override
  void dispose() {
    appearance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (blogPublishingConfigured) ref.watch(blogConnectionProvider);
    _ensureThemeCache();
    final theme = _cachedMaterialTheme;
    final macosTheme = _cachedMacosTheme;
    final cupertinoTheme = _cachedCupertinoTheme;
    return MacosApp(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      themeMode: macosTheme.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      theme: macosTheme,
      darkTheme: macosTheme,
      builder: (context, child) {
        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        final content = CupertinoTheme(
          data: cupertinoTheme,
          child: AnimatedTheme(
            data: theme,
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        final scale = appearance.uiScale;
        if ((scale - 1.0).abs() < 0.001) return content;
        return LayoutBuilder(
          builder: (context, constraints) {
            final mediaSize = MediaQuery.sizeOf(context);
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : mediaSize.width;
            final height = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : mediaSize.height;
            return SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width / scale,
                      height: height / scale,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(width / scale, height / scale),
                        ),
                        child: content,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      // Keep the Navigator's initial route stable. StartupGate owns loading
      // state and switches to onboarding/editor after the async read completes.
      home: widget.home ?? const _StartupGate(),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  FirstRunConfig? _setup;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _setup = null;
      _startupError = null;
    });
    try {
      // Theme preferences are optional; a slow native response must not block
      // loading the first-run configuration.
      try {
        await AppAppearance.instance.load().timeout(const Duration(seconds: 3));
      } catch (_) {}

      final setup = await FirstRunConfig.load().timeout(
        const Duration(seconds: 8),
      );
      NotesStorage.directory = setup.notesDirectory;
      if (mounted) setState(() => _setup = setup);
    } catch (error) {
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  void _completeSetup() {
    final directory = NotesStorage.directory;
    if (directory == null) return;
    setState(() {
      _setup = FirstRunConfig(isComplete: true, notesDirectory: directory);
      _startupError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_setup case final setup?) {
      return setup.isComplete
          ? const EditorScreen()
          : InitialSetupScreen(
              initialDirectory: setup.notesDirectory,
              onComplete: _completeSetup,
            );
    }
    if (_startupError case final error?) {
      return CupertinoPageScaffold(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.exclamationmark_circle, size: 32),
                const SizedBox(height: 14),
                const Text(
                  'No se pudo cargar la configuración inicial.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 18),
                CupertinoButton.filled(
                  onPressed: _initialize,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const CupertinoPageScaffold(
      child: Center(child: CupertinoActivityIndicator()),
    );
  }
}
