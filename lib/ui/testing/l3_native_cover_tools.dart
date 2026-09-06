// L3 native-cover tools — `l3_native_cover_probe` / `l3_native_cover_dismiss`.
//
// WHY: on iOS a natively PRESENTED view controller — the file bubble's
// document preview (`UIDocumentInteractionController` → `QLPreviewController`),
// a share sheet, a permission alert — covers the `FlutterViewController`, and
// Flutter stops producing frames underneath it. Every frame-awaiting seam
// then times out (`flutter_skill.screenshot`, `l3_force_home_root`'s
// `endOfFrame` loop) while `l3_dump_state` still answers. Observed live
// 2026-09-05 on an iPhone pair: `chat_file_bubble_present_open`'s tap left
// the preview up and every later case in the launch cascaded ("dialog did
// not open", "home recovery failed"). The Simulator offers no touch
// injection, so the harness cannot press the preview's own Done button —
// these seams ARE that Done. iOS-only by construction: Android's cover is a
// separate ACTIVITY (the driver sends adb BACK), and a desktop file open
// routes to another process. The probe is read-only and the dismiss only
// pops what is natively presented; neither touches account state, so both
// are ungated like `l3_dump_state`. Swift side: ios/Runner/AppDelegate.swift
// (`toxee/native_cover`).

part of 'l3_debug_tools.dart';

const MethodChannel _nativeCoverChannel = MethodChannel('toxee/native_cover');

void _registerL3NativeCoverTools() {
  addMcpTool(_l3NativeCoverProbeEntry());
  addMcpTool(_l3NativeCoverDismissEntry());
}

/// Bridge one `toxee/native_cover` method into the tool result shape:
/// `supported` (false off-iOS, or when the Runner lacks the channel),
/// `presented`, `controller`, and for `dismiss` also `dismissed`.
Future<Map<String, dynamic>> _nativeCoverCall(String method) async {
  if (!Platform.isIOS) {
    return {'ok': true, 'supported': false, 'presented': false};
  }
  try {
    final raw = await _nativeCoverChannel.invokeMethod<Map<Object?, Object?>>(
      method,
    );
    return {
      'ok': true,
      'supported': true,
      for (final e in (raw ?? const {}).entries) '${e.key}': e.value,
    };
  } on Exception catch (e) {
    // MissingPluginException (Runner without the channel) or a
    // PlatformException from the Swift side: report, never throw.
    return {'ok': false, 'supported': false, 'error': '$e'};
  }
}

MCPCallEntry _l3NativeCoverProbeEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final r = await _nativeCoverCall('probe');
    return MCPCallResult(
      message: r['presented'] == true
          ? 'native cover presented: ${r['controller']}'
          : 'no native cover',
      parameters: r,
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_native_cover_probe',
    description:
        'L3 READ-ONLY (iOS): report whether a native view controller is '
        'presented over the Flutter view (presented/controller). Under such a '
        'cover Flutter frames pause and frame-awaiting seams time out.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

MCPCallEntry _l3NativeCoverDismissEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final r = await _nativeCoverCall('dismiss');
    if (r['dismissed'] == true) {
      AppLogger.info('[L3] l3_native_cover_dismiss popped ${r['controller']}');
    }
    return MCPCallResult(
      message: r['dismissed'] == true
          ? 'native cover dismissed: ${r['controller']}'
          : 'nothing to dismiss',
      parameters: r,
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_native_cover_dismiss',
    description:
        'L3 (iOS): dismiss the natively presented view controller covering the '
        'Flutter view (what its own Done button does). No-op when nothing is '
        'presented; returns dismissed/controller.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);
