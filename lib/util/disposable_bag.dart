/// Centralizes cleanup registration for timers, subscriptions, and other
/// disposable resources. Call [dispose] in reverse order of registration.
class DisposableBag {
  final List<void Function()> _disposers = [];

  void add(void Function() disposer) {
    _disposers.add(disposer);
  }

  void dispose() {
    for (final d in _disposers.reversed) {
      try {
        d();
      } catch (_) {}
    }
    _disposers.clear();
  }
}
