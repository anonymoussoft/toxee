import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_ui_shell.dart';
import 'package:toxee/call/call_ui_components.dart';

void main() {
  testWidgets(
      'renders a compact business-dark call shell with top bar and dock',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CallSceneShell(
          topBar: CallTopStatusBar(
            key: ValueKey('call-top-bar'),
            title: 'Alice',
            subtitle: '00:32',
            trailingIcon: Icons.picture_in_picture_alt,
          ),
          bottomBar: CallActionDock(
            key: ValueKey('call-action-dock'),
            actions: [
              CallDockAction(icon: Icons.mic, label: 'Mute'),
              CallDockAction(
                  icon: Icons.call_end, label: 'Hang up', destructive: true),
            ],
          ),
          child: SizedBox.expand(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
  });

  testWidgets('highlights selected dock actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CallActionDock(
            actions: [
              CallDockAction(
                icon: Icons.mic_off,
                label: 'Muted',
                selected: true,
              ),
            ],
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.mic_off));

    expect(icon.color, isNot(const Color(0xFF9CA3AF)));
  });
}
