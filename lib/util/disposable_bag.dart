import 'package:flutter/foundation.dart';

/// Centralizes cleanup registration for timers, subscriptions, and other
/// disposable resources. Call [dispose] in reverse order of registration.
class DisposableBag {
  DisposableBag();

  final List<void Function()> _disposers = [];
  bool _disposed = false;

  void add(void Function() disposer) {
    if (_disposed) {
      throw StateError('Cannot add disposer after DisposableBag.dispose()');
    }
    _disposers.add(disposer);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final d in _disposers.reversed) {
      try {
        d();
      } catch (e, stackTrace) {
        debugPrint('DisposableBag: disposer threw $e');
        debugPrint(stackTrace.toString());
      }
    }
    _disposers.clear();
  }
}
