// L1 deterministic gate for S94 — the file-transfer progress EXPOSURE path,
// end to end through the REAL provider (not a synthetic map). The percent math
// is gated separately (test/ui/testing/file_transfers_projection_test.dart);
// this closes the remaining wiring: a recv-progress entry written into
// FakeChatMessageProvider's store surfaces via the read-only `fileProgress`
// getter and projects into the `l3_dump_state.fileTransfers` shape. The live
// 0→100 curve stays racy (entries vanish at completion), so the
// `debugSetFileProgress` seam injects a deterministic mid-flight sample.
//
// FakeChatMessageProvider constructs cleanly here: the ffi-progress
// subscriptions are skipped because `FakeUIKit.instance.im` is null (no UIKit
// init), and `_listenForMessageDeletions()` is a no-op — only the constructor's
// `Prefs.getAvatarPath()` needs the SharedPreferences mock.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'S94: an injected mid-flight progress entry surfaces in fileProgress and '
      'projects to the dump shape (floored percent)', () {
    final provider = FakeChatMessageProvider();
    addTearDown(provider.dispose);

    // A realistic mid-flight RECEIVE: 1/3 of the file (= 33%, floored).
    provider.debugSetFileProgress(
      'msg-xfer',
      received: 1,
      total: 3,
      path: '/tmp/recv.bin',
    );

    // The read-only getter exposes exactly what was written...
    final fp = provider.fileProgress;
    expect(fp['msg-xfer']?.received, 1);
    expect(fp['msg-xfer']?.total, 3);
    expect(fp['msg-xfer']?.path, '/tmp/recv.bin');
    // ...as an UNMODIFIABLE snapshot (Map.unmodifiable per call — callers can't
    // mutate the live store through it).
    expect(
      () => fp['x'] = (received: 0, total: 0, path: '/tmp/x.bin'),
      throwsUnsupportedError,
    );

    // ...and the l3_dump_state projection floors it into a 0-100 percent.
    final dump = projectFileTransfers(provider.fileProgress);
    expect(dump['msg-xfer']?['percent'], 33);
    expect(dump['msg-xfer']?['received'], 1);
    expect(dump['msg-xfer']?['total'], 3);
    expect(dump['msg-xfer']?['path'], '/tmp/recv.bin');
  });

  test(
      'S94: multiple concurrent transfers each project independently; an empty '
      'store projects empty', () {
    final provider = FakeChatMessageProvider();
    addTearDown(provider.dispose);

    expect(projectFileTransfers(provider.fileProgress), isEmpty);

    // Realistic mid-flight RECEIVE entries (the real `_onFileProgress` recv path
    // always carries a non-null path and received<total — codex), not synthetic
    // done/null states.
    provider.debugSetFileProgress('a', received: 99, total: 100, path: '/tmp/a.bin');
    provider.debugSetFileProgress('b', received: 1, total: 4, path: '/tmp/b.bin'); // 25%

    final dump = projectFileTransfers(provider.fileProgress);
    expect(dump['a']?['percent'], 99);
    expect(dump['b']?['percent'], 25);
    expect(dump.length, 2);
  });
}
