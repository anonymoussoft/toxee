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

Future<int> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: probe_vm_service.dart <ws_uri>');
    return 64;
  }
  final wsUri = args[0];
  try {
    final vm = await vmServiceConnectUri(wsUri);
    await vm.getVM();
    await vm.dispose();
    stdout.writeln('OK: vm service attachable at $wsUri');
    return 0;
  } catch (e) {
    stderr.writeln('probe_vm_service.dart: attach failed for $wsUri: $e');
    return 1;
  }
}
