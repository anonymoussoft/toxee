// One-off: does tapping sidebar_settings_tab actually switch the tab?
// Usage: dart run tool/screenshots/probe_tap_settings.dart <seed-root>

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final info = jsonDecode(
    await File('${args.first}/ShotA/instance.json').readAsString(),
  ) as Map<String, dynamic>;
  final vm = await vmServiceConnectUri(info['ws_uri'] as String);
  final pid = (info['pid'] as num).toInt();
  final v = await vm.getVM();
  final iso = v.isolates!.first.id!;
  Future<Map<String, dynamic>> call(String m, Map<String, String> a) async =>
      ((await vm.callServiceExtension(m, isolateId: iso, args: a)).json ?? {})
          .cast<String, dynamic>();
  Future<void> shot(String path) async {
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final r = await call('ext.flutter.flutter_skill.screenshot', {});
    final b64 = r['image'] as String? ?? '';
    if (b64.isNotEmpty) await File(path).writeAsBytes(base64Decode(b64));
    print('shot -> $path (${b64.length ~/ 1024}KB b64)');
  }

  for (final probe in [
    ('waitForElement', {'key': 'sidebar_settings_tab', 'timeout': '10'}),
    ('tap', {'key': 'sidebar_settings_tab'}),
  ]) {
    final r = await call('ext.flutter.flutter_skill.${probe.$1}', probe.$2);
    print('${probe.$1}(${probe.$2}) -> $r');
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  await shot('/tmp/probe_settings_tap.png');
  await vm.dispose();
}
