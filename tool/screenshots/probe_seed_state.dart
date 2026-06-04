// One-off diagnostic: dump the seed-relevant state of running Shot*
// instances (conversations incl. showName/type, knownGroups, member lists).
// Usage: dart run tool/screenshots/probe_seed_state.dart <seed-root> [names…]

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final seedRoot = args.first;
  final names = args.length > 1 ? args.sublist(1) : ['ShotA', 'ShotB'];
  for (final name in names) {
    final info = jsonDecode(
      await File('$seedRoot/$name/instance.json').readAsString(),
    ) as Map<String, dynamic>;
    final vm = await vmServiceConnectUri(info['ws_uri'] as String);
    final v = await vm.getVM();
    final iso = (v.isolates ?? [])
        .firstWhere((i) => (i.name ?? '').contains('main'),
            orElse: () => v.isolates!.first)
        .id!;
    Future<Map<String, dynamic>> call(String m, Map<String, String> a) async =>
        ((await vm.callServiceExtension(m, isolateId: iso, args: a)).json ??
                {})
            .cast<String, dynamic>();

    final st = await call('ext.mcp.toolkit.l3_dump_state', {});
    final convs = (st['conversations'] as List?) ?? [];
    final kg = (st['knownGroups'] as List?) ?? [];
    print('═══ $name selfNick=${st['nickname']} ready=${st['sessionReady']} '
        'connected=${st['isConnected']}');
    print('  knownGroups: $kg');
    for (final c in convs) {
      if (c is! Map) continue;
      print('  conv id=${c['conversationID']} type=${c['type']} '
          'showName="${c['showName']}" unread=${c['unreadCount']} '
          'pinned=${c['isPinned']}');
    }
    // C2C histories: surface receipt/system pollution (raw texts).
    for (final c in convs) {
      if (c is! Map) continue;
      final id = c['conversationID']?.toString() ?? '';
      if (!id.startsWith('c2c_')) continue;
      final h = await call('ext.mcp.toolkit.l3_dump_state', {
        'userId': id.substring(4),
      });
      final msgs = (h['messages'] as List?) ?? [];
      print('  c2c "${c['showName']}": ${msgs.length} msgs');
      for (final m in msgs) {
        if (m is! Map) continue;
        final t = (m['text'] ?? '').toString();
        print('    self=${m['isSelf']} '
            '"${t.length > 72 ? '${t.substring(0, 72)}…' : t}"');
      }
    }
    for (final gid in kg) {
      final ml = await call('ext.mcp.toolkit.l3_group_member_list', {
        'groupId': '$gid',
      });
      print('  members[$gid]: count=${ml['memberCount']} ok=${ml['ok']} '
          '${(ml['members'] as List?)?.map((m) => (m as Map)['nickName']).toList()}');
      final h = await call('ext.mcp.toolkit.l3_dump_state', {
        'conversationId': 'group_$gid',
      });
      final msgs = (h['messages'] as List?) ?? [];
      print('  history[$gid]: ${msgs.length} msgs: '
          '${msgs.map((m) => '"${(m as Map)['text']}"(self=${m['isSelf']})').join(', ')}');
    }
    await vm.dispose();
  }
}
