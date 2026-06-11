// Hermetic widget gates for the Batch-0 pointer-event primitives in
// lib/ui/testing/ui_drive_tools.dart. Each test mounts a REAL widget tree and
// drives the pure handler (the same function the MCP service extension wraps),
// proving the production hit-test / gesture / scroll pipeline actually runs —
// not the synthesized input shape alone.
//
// ignore_for_file: directives_ordering
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/ui_drive_tools.dart';

/// Mount [child] in a minimal real app frame (Directionality + a sized view).
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'ui_scroll_at scrolls a real ListView and fires its scroll listener',
    (tester) async {
      final controller = ScrollController();
      var notifications = 0;
      await _pump(
        tester,
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            notifications++;
            return false;
          },
          child: ListView.builder(
            key: const ValueKey('scroll_target'),
            controller: controller,
            itemCount: 200,
            itemBuilder: (_, i) =>
                SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      );

      expect(controller.offset, 0);

      final res = uiScrollAtHandler(key: 'scroll_target', dy: '300');
      await tester.pumpAndSettle();

      expect(res['ok'], true);
      expect(controller.offset, greaterThan(0),
          reason: 'mouse-wheel scroll must move the real ListView offset');
      expect(notifications, greaterThan(0),
          reason: 'a real ScrollNotification must fire from the scroll');
    },
  );

  testWidgets(
    'ui_drag scrolls a touch list (offset changes)',
    (tester) async {
      final controller = ScrollController();
      await _pump(
        tester,
        ListView.builder(
          key: const ValueKey('drag_target'),
          controller: controller,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('item $i')),
        ),
      );

      expect(controller.offset, 0);

      // Drag UP by 250px → list scrolls down (positive offset).
      final res = await uiDragHandler(
        key: 'drag_target',
        dy: '-250',
        steps: '12',
        stepDelay: Duration.zero,
      );
      // Pump live frames so the drag-end fling/settle resolves.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(res['ok'], true);
      expect(controller.offset, greaterThan(0),
          reason: 'touch drag must scroll the list');
    },
  );

  testWidgets(
    'ui_secondary_tap fires GestureDetector.onSecondaryTapDown',
    (tester) async {
      var secondaryFired = 0;
      Offset? at;
      await _pump(
        tester,
        Center(
          child: GestureDetector(
            key: const ValueKey('secondary_target'),
            onSecondaryTapDown: (details) {
              secondaryFired++;
              at = details.globalPosition;
            },
            child: Container(
              width: 200,
              height: 120,
              color: const Color(0xFF112233),
            ),
          ),
        ),
      );

      final res = uiSecondaryTapHandler(key: 'secondary_target');
      await tester.pumpAndSettle();

      expect(res['ok'], true);
      expect(secondaryFired, 1,
          reason: 'right-click must fire onSecondaryTapDown exactly once');
      // Fired at the widget center (≈ 400,300 in an 800x600 view).
      expect(at, isNotNull);
      expect(at!.dx, closeTo(400, 1));
      expect(at!.dy, closeTo(300, 1));
    },
  );

  testWidgets(
    'ui_long_press holds past the long-press timeout: onLongPress fires once, onTap never',
    (tester) async {
      var longPressFired = 0;
      var tapFired = 0;
      await _pump(
        tester,
        Center(
          child: GestureDetector(
            key: const ValueKey('lp_target'),
            onTap: () => tapFired++,
            onLongPress: () => longPressFired++,
            child: Container(
              width: 200,
              height: 120,
              color: const Color(0xFF334455),
            ),
          ),
        ),
      );

      // Start the handler WITHOUT awaiting: it dispatches the pointer-down and
      // suspends on its hold delay. tester.pump advances fake time, firing both
      // the LongPressGestureRecognizer's 500 ms deadline (→ onLongPress) and
      // the handler's hold timer (→ pointer-up, default 800 ms — sized past the
      // fork's 650 ms conversation-row recognizer), then the future completes.
      final fut = uiLongPressHandler(key: 'lp_target');
      await tester.pump(const Duration(milliseconds: 900));
      final res = await fut;
      await tester.pumpAndSettle();

      expect(res['ok'], true);
      expect(longPressFired, 1,
          reason: 'a >500 ms held press must fire onLongPress exactly once');
      expect(tapFired, 0,
          reason: 'the tap recognizer must lose the arena to the long-press');
    },
  );

  testWidgets(
    'ui_long_press with a short hold acts as a tap (negative control)',
    (tester) async {
      var longPressFired = 0;
      var tapFired = 0;
      await _pump(
        tester,
        Center(
          child: GestureDetector(
            key: const ValueKey('lp_short_target'),
            onTap: () => tapFired++,
            onLongPress: () => longPressFired++,
            child: Container(
              width: 200,
              height: 120,
              color: const Color(0xFF556677),
            ),
          ),
        ),
      );

      final fut = uiLongPressHandler(key: 'lp_short_target', holdMs: '100');
      await tester.pump(const Duration(milliseconds: 150));
      final res = await fut;
      await tester.pumpAndSettle();

      expect(res['ok'], true);
      expect(longPressFired, 0,
          reason: 'a 100 ms hold must NOT long-press');
      expect(tapFired, 1,
          reason: 'a sub-timeout press releases as a plain tap');
    },
  );

  testWidgets(
    'ui_long_press error shapes: absent key reports key_not_found',
    (tester) async {
      await _pump(tester, const Center(child: SizedBox(width: 10, height: 10)));
      final missing = await uiLongPressHandler(key: 'no_such_lp_key');
      expect(missing['ok'], false);
      expect((missing['error'] as String?), startsWith('key_not_found'));
    },
  );

  testWidgets(
    'offstage filtering: onstage duplicate is chosen over an offstage IndexedStack twin',
    (tester) async {
      // index 0 (onstage) and index 1 (offstage) both carry the same key on a
      // GestureDetector. Only the onstage one must be resolved + driven.
      var onstageFired = 0;
      var offstageFired = 0;
      Widget keyed(VoidCallback onSecondary) => GestureDetector(
            key: const ValueKey('dup_key'),
            onSecondaryTap: onSecondary,
            child: Container(
              width: 150,
              height: 80,
              color: const Color(0xFF445566),
            ),
          );
      await _pump(
        tester,
        Center(
          child: IndexedStack(
            index: 0,
            children: [
              keyed(() => onstageFired++),
              keyed(() => offstageFired++),
            ],
          ),
        ),
      );

      // Resolution must report exactly one onstage candidate.
      final resolution = resolveKeyCenter('dup_key');
      expect(resolution.ok, true);
      expect(resolution.candidates, 1,
          reason: 'the offstage IndexedStack twin must be filtered out');

      final res = uiSecondaryTapHandler(key: 'dup_key');
      await tester.pumpAndSettle();
      expect(res['ok'], true);
      expect(onstageFired, 1);
      expect(offstageFired, 0,
          reason: 'the offstage twin must never receive the gesture');
    },
  );

  testWidgets(
    'offstage filtering: an offstage-ONLY match returns ok:false',
    (tester) async {
      await _pump(
        tester,
        Center(
          child: IndexedStack(
            index: 0,
            children: [
              const SizedBox(width: 100, height: 100),
              // The keyed widget lives only in the offstage (index 1) child.
              Container(
                key: const ValueKey('offstage_only'),
                width: 100,
                height: 100,
                color: const Color(0xFF778899),
              ),
            ],
          ),
        ),
      );

      final resolution = resolveKeyCenter('offstage_only');
      expect(resolution.ok, false);
      expect(resolution.error, startsWith('key_offstage_only'));

      final res = uiSecondaryTapHandler(key: 'offstage_only');
      expect(res['ok'], false);
      expect((res['error'] as String?), startsWith('key_offstage_only'));

      // A truly absent key reports key_not_found, distinct from offstage-only.
      final missing = uiScrollAtHandler(key: 'no_such_key', dy: '100');
      expect(missing['ok'], false);
      expect((missing['error'] as String?), startsWith('key_not_found'));
    },
  );
}
