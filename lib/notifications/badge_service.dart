import 'dart:async';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

import '../sdk_fake/fake_event_bus.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_models.dart';
import '../util/logger.dart';

/// OS-level dock/launcher badge for unread conversations.
///
/// Per-platform support (via `app_badge_plus`):
/// - macOS:   full — NSDockTile badge label
/// - iOS:     full — UIApplication.applicationIconBadgeNumber
/// - Android: best-effort — depends on launcher (Samsung TouchWiz, Xiaomi
///            MIUI, Pixel Launcher each implement ShortcutBadger-style
///            counts differently; no-op on launchers that don't support it)
/// - Linux:   not supported by the plugin (silently skipped)
/// - Windows: no native count badge API; the plugin reports
///            `isSupported() == false`. TODO: investigate taskbar overlay
///            icons via win32 channel if user-facing requirement justifies
///            the extra surface.
///
/// Architecture notes:
/// - Subscribes to [FakeIM.topicUnread] on the [FakeEventBus] — the same
///   stream UIKit's conversation listener uses (see
///   `FakeConversationManager._unreadSub` in
///   `lib/sdk_fake/fake_managers.dart`). The total is already summed by
///   [FakeIM.refreshUnreadTotal] across all C2C + groups, so this service
///   never has to re-walk conversations itself.
/// - Updates are debounced to 200ms so a burst of incoming messages from
///   multiple peers in the same poll cycle results in one badge write,
///   not one per peer.
/// - The badge API is always invoked via [scheduleMicrotask] on the root
///   isolate's event loop — bus events may originate from the FFI poll
///   thread (via Tim2Tox callbacks), and platform channel calls must run
///   on the platform thread/main isolate.
/// - All `AppBadgePlus` calls are wrapped in try/catch so an unsupported
///   launcher (Android) or platform never surfaces as an uncaught error.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  static const Duration _debounce = Duration(milliseconds: 200);

  StreamSubscription<FakeUnreadTotal>? _sub;
  Timer? _debounceTimer;
  int _pendingTotal = 0;
  int _lastWrittenTotal = -1;
  bool _started = false;

  /// Cached result of [AppBadgePlus.isSupported] so we don't bounce across
  /// the platform channel on every write. Null until first probe completes;
  /// once known, fixed for the lifetime of the process.
  bool? _supported;

  /// Coarse static gate: platforms where the plugin definitely has no
  /// implementation. Avoids a platform-channel round-trip just to learn it
  /// isn't there. Final word still belongs to [AppBadgePlus.isSupported].
  bool get _platformPlausible {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS || Platform.isAndroid;
  }

  /// Idempotent. Subscribes the service to [FakeIM.topicUnread] on [bus] and
  /// asks [im] to emit the current total once so the badge reflects state
  /// from the moment startup completes (instead of waiting for the first
  /// message-triggered emit).
  void start({required FakeEventBus bus, required FakeIM im}) {
    if (_started) return;
    _started = true;
    if (!_platformPlausible) {
      AppLogger.debug(
          '[BadgeService] Platform not supported (${Platform.operatingSystem}); skipping');
      return;
    }
    _sub = bus.on<FakeUnreadTotal>(FakeIM.topicUnread).listen((u) {
      _scheduleWrite(u.total);
    });
    AppLogger.debug('[BadgeService] started');
    // Prime the badge with the current total. The emit is async (walks the
    // friend list); we don't await — the bus listener above will pick it up.
    im.refreshUnreadTotal();
  }

  /// Schedules a badge write with [_debounce] coalescing. Multiple unread
  /// totals arriving within the window collapse to a single write of the
  /// latest value.
  void _scheduleWrite(int total) {
    _pendingTotal = total < 0 ? 0 : total;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _flush);
  }

  void _flush() {
    final value = _pendingTotal;
    if (value == _lastWrittenTotal) return;
    _lastWrittenTotal = value;
    // Always hop onto the root isolate's microtask queue before calling the
    // platform channel. Bus events can originate from a polling callback.
    scheduleMicrotask(() => unawaited(_writeBadge(value)));
  }

  Future<void> _writeBadge(int count) async {
    try {
      // Probe once — cache the answer for the rest of the process lifetime.
      _supported ??= await AppBadgePlus.isSupported();
      if (_supported != true) return;
      await AppBadgePlus.updateBadge(count);
      AppLogger.debug('[BadgeService] badge written: $count');
    } catch (e, st) {
      // Unsupported launchers (Android) and Windows / Linux throw here.
      // Swallow — this is best-effort UX, not a correctness gate.
      AppLogger.debug('[BadgeService] writeBadge failed (best-effort): $e');
      if (kDebugMode) {
        AppLogger.debug('[BadgeService] stack: $st');
      }
    }
  }

  /// Force the badge to zero immediately (skips the debounce). Use when the
  /// app gains focus / a conversation is opened that drops the total to 0.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _pendingTotal = 0;
    _lastWrittenTotal = 0;
    if (!_platformPlausible) return;
    try {
      _supported ??= await AppBadgePlus.isSupported();
      if (_supported != true) return;
      await AppBadgePlus.updateBadge(0);
    } catch (e) {
      AppLogger.debug('[BadgeService] clear failed (best-effort): $e');
    }
  }

  /// Tear down on session teardown (logout / account switch). The subscription
  /// would otherwise hold the previous session's FakeEventBus alive.
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _sub?.cancel();
    _sub = null;
    _pendingTotal = 0;
    _lastWrittenTotal = -1;
    _started = false;
    if (!_platformPlausible) return;
    try {
      if (_supported == true) {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (e) {
      AppLogger.warn('[BadgeService] clearing badge during dispose failed: $e');
    }
  }
}
