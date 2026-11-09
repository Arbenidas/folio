import 'dart:async';

import '../domain/document_repository.dart';
import '../domain/notebook_snapshot.dart';

class NotebookSyncUpdate {
  const NotebookSyncUpdate({this.snapshot, this.error});

  final NotebookSnapshot? snapshot;
  final Object? error;
}

class NotebookSyncService {
  NotebookSyncService(
    this._repository, {
    this.debounce = const Duration(milliseconds: 220),
    this.restartDelay = const Duration(seconds: 1),
  });

  final DocumentRepository _repository;
  final Duration debounce;
  final Duration restartDelay;
  final StreamController<NotebookSyncUpdate> _updates =
      StreamController<NotebookSyncUpdate>.broadcast();

  StreamSubscription<void>? _subscription;
  Timer? _debounceTimer;
  Timer? _restartTimer;
  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  Stream<NotebookSyncUpdate> get updates => _updates.stream;

  void start() {
    if (_disposed || _subscription != null) return;
    try {
      _subscription = _repository.watch().listen(
        (_) => _queueScan(),
        onError: _watchFailed,
        onDone: _watchEnded,
      );
    } catch (error) {
      _watchFailed(error);
    }
  }

  void _queueScan() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(reconcile()));
  }

  Future<void> reconcile() async {
    if (_disposed) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    do {
      _pending = false;
      try {
        _updates.add(NotebookSyncUpdate(snapshot: await _repository.scan()));
      } catch (error) {
        _updates.add(NotebookSyncUpdate(error: error));
      }
    } while (_pending && !_disposed);
    _running = false;
  }

  void _watchFailed(Object error) {
    if (_disposed) return;
    _updates.add(NotebookSyncUpdate(error: error));
    _restart();
  }

  void _watchEnded() {
    if (_disposed) return;
    _updates.add(
      const NotebookSyncUpdate(
        error: 'La vigilancia de la carpeta terminó inesperadamente.',
      ),
    );
    _restart();
  }

  void _restart() {
    _subscription = null;
    _restartTimer?.cancel();
    _restartTimer = Timer(restartDelay, () {
      if (_disposed) return;
      unawaited(reconcile());
      start();
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _restartTimer?.cancel();
    await _subscription?.cancel();
    await _updates.close();
  }
}
