import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum PomodoroPhase { focus, breakTime }

class PomodoroController extends ChangeNotifier {
  PomodoroController() {
    _preferencesLoaded = _loadPreferences();
    _publishTime();
  }

  static const _channel = MethodChannel('folio/pomodoro');
  File? _preferences;
  late final Future<void> _preferencesLoaded;
  Timer? _ticker;
  int focusMinutes = 25;
  int breakMinutes = 5;
  PomodoroPhase phase = PomodoroPhase.focus;
  Duration remaining = const Duration(minutes: 25);
  DateTime? _deadline;
  Timer? _completionTimer;
  bool intervalComplete = false;
  bool _ready = false;
  bool _starting = false;
  bool _disposed = false;

  bool get isRunning => _deadline != null;
  String get phaseLabel => intervalComplete
      ? 'Intervalo terminado'
      : phase == PomodoroPhase.focus
      ? 'Enfoque'
      : 'Descanso';
  String get display => intervalComplete
      ? '¡Listo!'
      : '${remaining.inMinutes.toString().padLeft(2, '0')}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Future<void> _loadPreferences() async {
    try {
      final support = await getApplicationSupportDirectory();
      _preferences = File(p.join(support.path, 'folio-pomodoro.json'));
      final values = jsonDecode(await _preferences!.readAsString());
      if (values is! Map<String, dynamic> || values['version'] != 1) return;
      focusMinutes = _bounded(values['focusMinutes'], focusMinutes, 90);
      breakMinutes = _bounded(values['breakMinutes'], breakMinutes, 30);
      remaining = Duration(minutes: _minutesForPhase);
      _emit();
      _publishTime();
    } on FileSystemException {
      // Missing preferences leave the standard intervals in place.
    } on FormatException {
      // Invalid timer preferences do not prevent opening tasks or notes.
    } catch (_) {
      // The timer remains usable with in-memory defaults if storage is unavailable.
    } finally {
      _ready = true;
      _emit();
    }
  }

  int get _minutesForPhase =>
      phase == PomodoroPhase.focus ? focusMinutes : breakMinutes;

  Future<void> configure({int? focus, int? rest}) async {
    await _preferencesLoaded;
    if (focus != null) focusMinutes = _bounded(focus, focusMinutes, 90);
    if (rest != null) breakMinutes = _bounded(rest, breakMinutes, 30);
    if (!isRunning) remaining = Duration(minutes: _minutesForPhase);
    _publishTime();
    _emit();
    await _savePreferences();
  }

  Future<void> _savePreferences() async {
    final file = _preferences;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final temp = File(
      p.join(
        file.parent.path,
        '.folio-write-pomodoro-${pid}-${Random.secure().nextInt(1 << 32)}',
      ),
    );
    try {
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'focusMinutes': focusMinutes,
          'breakMinutes': breakMinutes,
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  void toggle() {
    if (!isRunning && !_ready) {
      if (_starting) return;
      _starting = true;
      unawaited(_startWhenReady());
      return;
    }
    _completionTimer?.cancel();
    intervalComplete = false;
    if (isRunning) {
      _syncRemaining();
      _ticker?.cancel();
      _ticker = null;
      _deadline = null;
    } else {
      _deadline = DateTime.now().add(remaining);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    _publishTime();
    _emit();
  }

  Future<void> _startWhenReady() async {
    await _preferencesLoaded;
    _starting = false;
    if (_disposed || isRunning) return;
    toggle();
  }

  void reset() {
    _completionTimer?.cancel();
    intervalComplete = false;
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    remaining = Duration(minutes: _minutesForPhase);
    _publishTime();
    _emit();
  }

  void refreshAfterResume() => _tick();

  void _tick() {
    if (!isRunning) return;
    _syncRemaining();
    if (remaining == Duration.zero) {
      _ticker?.cancel();
      _ticker = null;
      _deadline = null;
      phase = phase == PomodoroPhase.focus
          ? PomodoroPhase.breakTime
          : PomodoroPhase.focus;
      remaining = Duration(minutes: _minutesForPhase);
      intervalComplete = true;
      _completionTimer?.cancel();
      _completionTimer = Timer(const Duration(seconds: 5), () {
        intervalComplete = false;
        _publishTime();
        _emit();
      });
    }
    _publishTime();
    _emit();
  }

  void _syncRemaining() {
    final deadline = _deadline;
    if (deadline != null) {
      remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) remaining = Duration.zero;
    }
  }

  void _publishTime() {
    unawaited(
      _channel
          .invokeMethod<void>('update', {
            'display': display,
            'running': isRunning,
            'deadline': _deadline?.millisecondsSinceEpoch.toDouble(),
          })
          .catchError((_) {}),
    );
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  static int _bounded(Object? value, int fallback, int maximum) =>
      value is int && value >= 1 && value <= maximum ? value : fallback;

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _completionTimer?.cancel();
    unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    super.dispose();
  }
}
