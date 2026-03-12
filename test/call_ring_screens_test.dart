import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/incoming_call_view.dart';
import 'package:toxee/call/outgoing_call_view.dart';
import 'package:toxee/call/ringing_call_manager.dart';

class FakeRingingCallManager implements RingingCallManager {
  @override
  void acceptCall() {}

  @override
  void rejectCall() {}

  @override
  void hangUp() {}
}

Widget buildIncomingCallTestApp(CallStateNotifier callState) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: IncomingCallView(
      callState: callState,
      manager: FakeRingingCallManager(),
    ),
  );
}

Widget buildOutgoingCallTestApp(CallStateNotifier callState) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: OutgoingCallView(
      callState: callState,
      manager: FakeRingingCallManager(),
    ),
  );
}

void main() {
  testWidgets('incoming screen uses shared shell with two primary actions',
      (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.incoming,
        inviteID: 'invite-2',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      );

    await tester.pumpWidget(buildIncomingCallTestApp(callState));

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('incoming-call-actions')), findsOneWidget);
    expect(find.text('Alice'), findsAtLeast(1));
  });

  testWidgets('outgoing screen uses shared shell with one destructive action',
      (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'invite-3',
        remoteUserID: 'bob',
        remoteNickname: 'Bob',
      );

    await tester.pumpWidget(buildOutgoingCallTestApp(callState));

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('outgoing-call-actions')), findsOneWidget);
    expect(find.text('Bob'), findsAtLeast(1));
  });
}
