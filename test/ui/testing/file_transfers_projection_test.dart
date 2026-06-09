// L1 deterministic gate for S94 — file-transfer progress EXPOSURE. The live
// 0→100 curve is racy (entries are added per recv chunk and removed on
// completion), but the projection that `l3_dump_state.fileTransfers` exposes —
// byte counts → a floored 0-100 percent — is pure and is gated here. This is the
// math a runner reads while polling a transfer; the live timing is the only
// irreducible part (codex).
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  test('S94: projectFileTransfers floors received/total into a 0-100 percent',
      () {
    final out = projectFileTransfers({
      // 1/3 = 33.3% → floor 33 (proves it floors, not rounds — codex trap).
      'm-third': (received: 1, total: 3, path: '/tmp/a.bin'),
      // 99/100 → 99 (just-before-done; proves it doesn't prematurely read 100).
      'm-99': (received: 99, total: 100, path: null),
      // mid-transfer exact half.
      'm-half': (received: 50, total: 100, path: '/tmp/b.bin'),
    });

    expect(out['m-third']!['percent'], 33);
    expect(out['m-third']!['received'], 1);
    expect(out['m-third']!['total'], 3);
    expect(out['m-third']!['path'], '/tmp/a.bin');

    expect(out['m-99']!['percent'], 99);
    expect(out['m-99']!['path'], isNull);

    expect(out['m-half']!['percent'], 50);
  });

  test('S94: total <= 0 yields percent 0 (no divide-by-zero, no negatives)', () {
    final out = projectFileTransfers({
      'm-zero': (received: 0, total: 0, path: null),
      // A genuinely NEGATIVE total (not just 0) must hit the same guard — the
      // `total > 0` check, not `total != 0` (codex).
      'm-neg': (received: 5, total: -5, path: null),
    });
    expect(out['m-zero']!['percent'], 0);
    expect(out['m-neg']!['percent'], 0);
  });

  test('S94: a completed (received==total) entry projects 100 — the live path '
      'removes it first, but the projection itself does not cap', () {
    final out = projectFileTransfers({
      'm-done': (received: 100, total: 100, path: '/tmp/done.bin'),
    });
    expect(out['m-done']!['percent'], 100);
  });

  test('S94: an empty progress map projects to an empty fileTransfers map', () {
    expect(projectFileTransfers(const {}), isEmpty);
  });
}
