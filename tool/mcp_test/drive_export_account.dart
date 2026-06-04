// Minimal driver for S43 export-account (.tox) on a single logged-in instance.
//
// Usage:
//   dart run tool/mcp_test/drive_export_account.dart <ws_uri> <output_path>
//
// Assumes the instance is already on HomePage with a signed-in test account.

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<int> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: drive_export_account.dart <ws_uri> <output_path>');
    return 64;
  }
  final wsUri = args[0];
  final outputPath = args[1];
  final outFile = File(outputPath);
  if (await outFile.exists()) {
    await outFile.delete();
  }

  try {
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final d = _Driver(vm, isolateId);
    await d.waitForExtension('ext.flutter.marionette.tap', timeoutSecs: 60);
    await d.waitForExtension('ext.mcp.toolkit.l3_set_export_save_path',
        timeoutSecs: 60);

    await d.setExportSavePath(outputPath);
    await d.tapKey('sidebar_settings_tab');
    await _retry(() => d.tapKey('settings_export_account_button'),
        attempts: 20, intervalMs: 500, label: 'tap export account');
    await _retry(() => d.tapKey('settings_export_profile_tox_option'),
        attempts: 20, intervalMs: 500, label: 'tap profile tox option');

    await _retry(() async {
      if (!await outFile.exists()) {
        throw Exception('export file not written yet');
      }
    }, attempts: 30, intervalMs: 1000, label: 'wait export file');

    final bytes = await outFile.readAsBytes();
    final prefix = bytes.length >= 8
        ? String.fromCharCodes(bytes.take(8))
        : '<short:${bytes.length}>';
    stdout.writeln('OK: export written to $outputPath');
    stdout.writeln('bytes=${bytes.length} prefix=$prefix');
    await vm.dispose();
    return 0;
  } catch (e) {
    stderr.writeln('drive_export_account.dart: $e');
    return 1;
  }
}

class _Driver {
  _Driver(this.vm, this.isolateId);
  final VmService vm;
  final String isolateId;

  Future<void> waitForExtension(String name, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      final ext = iso.extensionRPCs ?? const <String>[];
      if (ext.contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('extension $name not registered');
  }

  Future<Response> _call(String method, Map<String, Object?> args) {
    final stringArgs = <String, String>{
      for (final entry in args.entries) entry.key: entry.value.toString(),
    };
    return vm.callServiceExtension(method, isolateId: isolateId, args: stringArgs);
  }

  Future<void> tapKey(String key) async {
    await _call('ext.flutter.marionette.tap', <String, Object?>{'key': key});
  }

  Future<void> setExportSavePath(String path) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_export_save_path',
      <String, Object?>{'path': path},
    );
    final json = (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    if (json['ok'] != true) {
      throw Exception('l3_set_export_save_path failed: ${json['error']}');
    }
  }
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final vmObj = await vm.getVM();
    final isolates = vmObj.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) {
          return iso.id!;
        }
      }
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('no isolate appeared');
}

Future<T> _retry<T>(
  Future<T> Function() body, {
  required int attempts,
  required int intervalMs,
  required String label,
}) async {
  Object? lastErr;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e) {
      lastErr = e;
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }
  throw Exception('retry exhausted ($label): $lastErr');
}
