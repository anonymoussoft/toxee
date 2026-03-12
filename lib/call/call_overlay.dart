import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import 'call_state_notifier.dart';
import 'call_overlay_manager.dart';
import 'call_floating_widget.dart';
import 'incoming_call_view.dart';
import 'outgoing_call_view.dart';
import 'in_call_view.dart';

/// Full-screen call overlay that shows incoming, in-call, or ended UI on top of [child].
class CallOverlay extends StatelessWidget {
  const CallOverlay({
    super.key,
    required this.callState,
    required this.manager,
    required this.child,
  });

  final CallStateNotifier callState;
  final CallOverlayManager manager;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: callState,
      builder: (context, _) {
        if (callState.state == CallUIState.idle) return child;

        // Minimized: show floating widget, child is fully interactive
        if (callState.isMinimized &&
            (callState.state == CallUIState.ringing ||
             callState.state == CallUIState.inCall)) {
          return Stack(
            children: [
              child,
              _NoUnderlineScope(
                child: CallFloatingWidget(callState: callState, manager: manager),
              ),
            ],
          );
        }

        // Full-screen call views
        return Stack(
          children: [
            child,
            _NoUnderlineScope(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildCallView(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallView() {
    switch (callState.state) {
      case CallUIState.ringing:
        return callState.direction == CallDirection.incoming
            ? IncomingCallView(key: const ValueKey('incoming'), callState: callState, manager: manager)
            : OutgoingCallView(key: const ValueKey('outgoing'), callState: callState, manager: manager);
      case CallUIState.inCall:
        return InCallView(key: const ValueKey('inCall'), callState: callState, manager: manager);
      case CallUIState.ended:
        return _CallEndedView(key: const ValueKey('ended'), callState: callState);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Wraps call UI so inherited text style does not show underline (e.g. from theme).
class _NoUnderlineScope extends StatelessWidget {
  const _NoUnderlineScope({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(
      decoration: TextDecoration.none,
      decorationColor: null,
      decorationStyle: null,
    );
    return DefaultTextStyle(style: style, child: child);
  }
}

class _CallEndedView extends StatelessWidget {
  const _CallEndedView({super.key, required this.callState});

  final CallStateNotifier callState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: Text(
            l10n.callEnded,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ),
      ),
    );
  }
}
