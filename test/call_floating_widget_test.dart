import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/call_floating_widget.dart';
import 'package:toxee/call/ringing_call_manager.dart';

class FakeRingingCallManager implements RingingCallManager {
  @override
  void acceptCall() {}

  @override
  void rejectCall() {}

  @override
  void hangUp() {}
}

Widget buildFloatingCallTestApp(CallStateNotifier callState) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Stack(
      children: [
        const SizedBox.expand(),
        CallFloatingWidget(
          callState: callState,
          manager: FakeRingingCallManager(),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('floating widget shows shared compact card and restore affordance',
      (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.outgoing,
        inviteID: 'invite-4',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      )
      ..enterCall()
      ..minimize();

    await tester.pumpWidget(buildFloatingCallTestApp(callState));

    expect(find.byKey(const ValueKey('floating-call-card')), findsOneWidget);
    expect(find.text('Alice'), findsAtLeast(1));
    expect(find.byIcon(Icons.call_end), findsOneWidget);

    callState.endCall();
    await tester.pump(const Duration(seconds: 3));
  });
}
