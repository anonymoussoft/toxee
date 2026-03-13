part of 'home_page.dart';

extension _HomePagePersistence on _HomePageState {
  /// Initialize binary replacement persistence hook.
  /// Idempotent; deferred subscription is cancelled with the page.
  void _initBinaryReplacementPersistenceHook() {
    try {
      if (_persistenceHookInstalled) return;

      final persistence = widget.service.messageHistoryPersistence;
      final selfId = widget.service.selfId;

      if (selfId.isEmpty) {
        AppLogger.debug('[HomePage] Self ID not available yet, will initialize hook after login');
        _persistenceHookSub?.cancel();
        _persistenceHookSub = widget.service.connectionStatusStream
            .where((connected) => connected && widget.service.selfId.isNotEmpty)
            .take(1)
            .listen((_) {
          _setupPersistenceHook(persistence, widget.service.selfId);
        });
        _bag.add(() => _persistenceHookSub?.cancel());
        return;
      }

      _setupPersistenceHook(persistence, selfId);
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] Error initializing persistence hook: $e', e, stackTrace);
    }
  }

  void _setupPersistenceHook(MessageHistoryPersistence persistence, String selfId) {
    try {
      if (_persistenceHookInstalled) return;

      BinaryReplacementHistoryHook.initialize(persistence, selfId);

      final currentListeners = TIMMessageManager.instance.v2TimAdvancedMsgListenerList;

      if (currentListeners.isNotEmpty) {
        final originalListener = currentListeners.first;
        final wrappedListener = BinaryReplacementHistoryHook.wrapListener(originalListener);

        TIMMessageManager.instance.removeAdvancedMsgListener(listener: originalListener);
        TIMMessageManager.instance.addAdvancedMsgListener(wrappedListener);

        _persistenceHookInstalled = true;
        AppLogger.debug('[HomePage] Binary replacement persistence hook initialized');
      } else {
        final listener = V2TimAdvancedMsgListener(
          onRecvNewMessage: (V2TimMessage message) {
            BinaryReplacementHistoryHook.saveMessage(message);
          },
        );
        TIMMessageManager.instance.addAdvancedMsgListener(listener);
        _persistenceHookInstalled = true;
        AppLogger.debug('[HomePage] Binary replacement persistence hook initialized (new listener)');
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[HomePage] Error setting up persistence hook: $e', e, stackTrace);
    }
  }
}
