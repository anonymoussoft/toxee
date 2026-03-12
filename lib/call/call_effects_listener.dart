import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../i18n/app_localizations.dart';
import '../i18n/app_localizations_en.dart';
import '../ui/widgets/app_snackbar.dart';
import 'call_service_manager.dart';
import 'call_state_notifier.dart';

class CallWakePolicy {
  const CallWakePolicy._();

  static bool shouldKeepScreenAwake(CallUIState state) =>
      state == CallUIState.ringing || state == CallUIState.inCall;
}

class CallEffectsListener extends StatefulWidget {
  const CallEffectsListener({
    super.key,
    required this.callState,
    required this.manager,
    required this.child,
  });

  final CallStateNotifier callState;
  final CallServiceManager manager;
  final Widget child;

  @override
  State<CallEffectsListener> createState() => _CallEffectsListenerState();
}

class _CallEffectsListenerState extends State<CallEffectsListener> {
  bool _wakelockEnabled = false;
  int _lastNoticeId = -1;
  CallUIState? _lastManagedState;

  @override
  void initState() {
    super.initState();
    widget.callState.addListener(_handleCallStateChanged);
    widget.manager.uiNotice.addListener(_handleNoticeChanged);
    scheduleMicrotask(_handleCallStateChanged);
  }

  @override
  void didUpdateWidget(covariant CallEffectsListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callState != widget.callState) {
      oldWidget.callState.removeListener(_handleCallStateChanged);
      widget.callState.addListener(_handleCallStateChanged);
      scheduleMicrotask(_handleCallStateChanged);
    }
    if (oldWidget.manager.uiNotice != widget.manager.uiNotice) {
      oldWidget.manager.uiNotice.removeListener(_handleNoticeChanged);
      widget.manager.uiNotice.addListener(_handleNoticeChanged);
    }
  }

  @override
  void dispose() {
    widget.callState.removeListener(_handleCallStateChanged);
    widget.manager.uiNotice.removeListener(_handleNoticeChanged);
    if (_wakelockEnabled) {
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }

  void _handleCallStateChanged() {
    final currentState = widget.callState.state;
    if (_lastManagedState != currentState) {
      _lastManagedState = currentState;
      unawaited(widget.manager.syncPlatformEffectsForState(currentState));
    }

    final shouldEnable = CallWakePolicy.shouldKeepScreenAwake(currentState);
    if (shouldEnable == _wakelockEnabled) {
      return;
    }

    _wakelockEnabled = shouldEnable;
    unawaited(WakelockPlus.toggle(enable: shouldEnable));
  }

  void _handleNoticeChanged() {
    final notice = widget.manager.uiNotice.value;
    if (!mounted || notice == null || notice.id == _lastNoticeId) {
      return;
    }
    _lastNoticeId = notice.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
      AppSnackBar.show(
        context,
        notice.resolveMessage(l10n),
        isError: notice.isError,
        actionLabel: notice.offerSettings ? l10n.settings : null,
        onAction: notice.offerSettings
            ? () {
                unawaited(openAppSettings());
              }
            : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
