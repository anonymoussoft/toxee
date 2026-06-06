// Lightweight VM service probe for the Fixture C spike harness.
//
// Goal: prove the announced ws:// URI is attachable *at all* before the pair
// launcher hands it to marionette / MCP / scenario runners. This is strictly a
// transport-level probe: connect and call getVM(), nothing more.
//
// Usage:
//   dart run tool/mcp_test/probe_vm_service.dart <ws_uri>
//
// Exit 0 on success, non-zero on any connect/getVM failure.

// `vm_service` is a transitive dep of the project (same rationale as the
// other tool/mcp_test scripts).
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

class _LocalVmServiceHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(
    Uri url,
    Map<String, String>? environment,
  ) {
    final host = url.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return 'DIRECT';
    }
    return super.findProxyFromEnvironment(url, environment);
  }
}

Future<void> main(List<String> args) async {
  exitCode = await HttpOverrides.runWithHttpOverrides(
    () => _main(args),
    _LocalVmServiceHttpOverrides(),
  );
}

Future<int> _main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: probe_vm_service.dart <ws_uri>');
    return 64;
  }
  final wsUri = args[0];
  Object? lastError;
  for (var attempt = 1; attempt <= 15; attempt++) {
    try {
      final vm = await vmServiceConnectUri(wsUri);
      await vm.getVM();
      await vm.dispose();
      stdout.writeln('OK: vm service attachable at $wsUri');
      return 0;
    } catch (e) {
      lastError = e;
      if (attempt < 15) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }
  stderr.writeln(
    'probe_vm_service.dart: attach failed for $wsUri after 15 attempts: '
    '$lastError',
  );
  return 1;
}
