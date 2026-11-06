import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import 'core/first_run_config.dart';
import 'core/theme.dart';
import 'features/editor/presentation/views/editor_screen.dart';
import 'features/onboarding/presentation/views/initial_setup_screen.dart';

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final appearance = AppAppearance.instance;

  @override
  void initState() {
    super.initState();
    appearance.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appearance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = appearance.selected;
    return MacosApp(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: buildEditorMacosTheme(selected),
      builder: (context, child) => CupertinoTheme(
        data: buildEditorCupertinoTheme(selected),
        child: Theme(
          data: buildEditorTheme(selected),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      // Keep the Navigator's initial route stable. StartupGate owns loading
      // state and switches to onboarding/editor after the async read completes.
      home: const _StartupGate(),
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
