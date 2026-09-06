// L3 IRC tools — the deterministic local-IRC state seams
// (`l3_irc_set_state`, `l3_irc_add_channel_local`,
// `l3_irc_remove_channel_local`) and the read-only native-library probe
// (`l3_irc_native_library_probe`).
//
// Split out of `l3_debug_tools.dart` (which is pinned in
// `tool/.complexity_baseline.txt`) so the IRC surface can grow — the probe
// was the entry that no longer fit — without pushing the tool file past its
// pin. A `part` rather than its own library on purpose: the handlers read the
// library-private `_activeAccountIsTest` / `_readIrcChannelGroups` /
// `_removeLocalIrcGroupMapping` helpers that stay in `l3_debug_tools.dart`.

part of 'l3_debug_tools.dart';

void _registerL3IrcTools() {
  addMcpTool(_l3IrcSetStateEntry());
  addMcpTool(_l3IrcAddChannelLocalEntry());
  addMcpTool(_l3IrcRemoveChannelLocalEntry());
  addMcpTool(_l3IrcNativeLibraryProbeEntry());
}

/// Read-only capability probe for the native IRC client library: can THIS
/// build `dlopen` `libirc_client` at the path `IrcAppManager` resolves? The
/// real-UI `irc_join_channel_loopback_live` case gates on the answer so it
/// SKIPs — never vacuously passes, never reds for a missing artefact — where
/// the library is not bundled (today iOS and Android: `run_toxee.sh`'s
/// macOS-only `make irc_client` is the only thing that produces one).
/// Ungated: nothing here reads or writes account state.
MCPCallEntry _l3IrcNativeLibraryProbeEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final probe = IrcAppManager().nativeLibraryProbe();
    return MCPCallResult(
      message: probe.available
          ? 'native IRC library loadable'
          : 'native IRC library NOT loadable',
      parameters: {
        'ok': true,
        'available': probe.available,
        'path': probe.path,
        'error': probe.error,
      },
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_irc_native_library_probe',
    description:
        'L3 READ-ONLY: report whether the native libirc_client library can be '
        'loaded on this build (available/path/error). Drivers gate the live '
        'loopback IRC JOIN case on it instead of a platform list.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

MCPCallEntry _l3IrcSetStateEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_irc_set_state: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final reset = _parseOptionalBool(request['reset']) ?? false;
    if (request.containsKey('reset') &&
        _parseOptionalBool(request['reset']) == null) {
      return MCPCallResult(
        message: 'l3_irc_set_state: reset must be true|false',
        parameters: {'ok': false, 'error': 'bad_reset'},
      );
    }
    final installed = _parseOptionalBool(request['installed']);
    final useSasl = _parseOptionalBool(request['useSasl']);
    final localAddOverride = _parseOptionalBool(request['localAddOverride']);
    if (request.containsKey('installed') && installed == null) {
      return MCPCallResult(
        message: 'l3_irc_set_state: installed must be true|false',
        parameters: {'ok': false, 'error': 'bad_installed'},
      );
    }
    if (request.containsKey('useSasl') && useSasl == null) {
      return MCPCallResult(
        message: 'l3_irc_set_state: useSasl must be true|false',
        parameters: {'ok': false, 'error': 'bad_use_sasl'},
      );
    }
    if (request.containsKey('localAddOverride') && localAddOverride == null) {
      return MCPCallResult(
        message: 'l3_irc_set_state: localAddOverride must be true|false',
        parameters: {'ok': false, 'error': 'bad_local_add_override'},
      );
    }
    final portRaw = request['port'];
    final port = portRaw == null
        ? null
        : int.tryParse(portRaw.toString().trim());
    if (portRaw != null && (port == null || port <= 0)) {
      return MCPCallResult(
        message: 'l3_irc_set_state: port must be a positive integer',
        parameters: {'ok': false, 'error': 'bad_port'},
      );
    }
    try {
      if (reset) {
        await Prefs.setIrcAppInstalled(false);
        await Prefs.setIrcChannels(const <String>[]);
        await Prefs.setIrcServer('.invalid');
        await Prefs.setIrcPort(6667);
        await Prefs.setIrcUseSasl(false);
        _ircLocalAddOverrideEnabled = false;
      }
      if (installed != null) await Prefs.setIrcAppInstalled(installed);
      final server = (request['server'] as Object?)?.toString().trim();
      if (server != null) await Prefs.setIrcServer(server);
      if (port != null) await Prefs.setIrcPort(port);
      if (useSasl != null) await Prefs.setIrcUseSasl(useSasl);
      if (localAddOverride != null) {
        _ircLocalAddOverrideEnabled = localAddOverride;
      }
      final channels = _parseOptionalStringList(request['channels']);
      if (channels != null) {
        await Prefs.setIrcChannels([
          for (final channel in channels) _normalizeIrcChannelName(channel),
        ]);
      }
      // Sync the IN-MEMORY IrcAppManager from the prefs we just wrote. The
      // Applications page surfaces the Add-Channel button from
      // `IrcAppManager().isInstalled` (in-memory) + lists `IrcAppManager().channels`,
      // NOT from Prefs directly — so without this re-init the page never reflects
      // an l3-set `installed:true` (the add button stays hidden, and an
      // l3-seeded channel list stays empty) even though dump_state (which reads
      // Prefs) shows the new values. `init()` re-reads installed + channels from
      // Prefs WITHOUT loading the native libirc_client (the localAddOverride path
      // needs no native lib). Surfaced live on Windows by irc_join_channel_real_controls.
      await IrcAppManager().init();
      // Tell the (already-built, IndexedStack-cached) Applications page to reload
      // its install-state + channel list so this mutation surfaces in the UI.
      debugApplicationsIrcReloadSignal.value =
          debugApplicationsIrcReloadSignal.value + 1;
      final params = projectIrcState(
        installed: await Prefs.getIrcAppInstalled(),
        channels: await Prefs.getIrcChannels(),
        server: await Prefs.getIrcServer(),
        port: await Prefs.getIrcPort(),
        useSasl: await Prefs.getIrcUseSasl(),
        channelGroups: await _readIrcChannelGroups(),
      );
      AppLogger.info('[L3] l3_irc_set_state MUTATED $params');
      return MCPCallResult(
        message: 'IRC local state updated',
        parameters: {
          'ok': true,
          ...params,
          'ircLocalAddOverride': _ircLocalAddOverrideEnabled,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_irc_set_state failed', e, st);
      return MCPCallResult(
        message: 'l3_irc_set_state: failed: $e',
        parameters: {'ok': false, 'error': 'set_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_irc_set_state',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): set deterministic local IRC '
        'Prefs without loading libirc_client or contacting an IRC server. '
        'Optional fields: installed=true|false, server, port, useSasl=true|false, '
        'channels as JSON array/List/comma-separated string, '
        'localAddOverride=true|false for real-control no-network add.',
    inputSchema: ObjectSchema(
      properties: {
        'reset': StringSchema(
          description: 'true | false; reset local IRC prefs to .invalid/empty.',
        ),
        'installed': StringSchema(description: 'true | false'),
        'server': StringSchema(description: 'IRC server string to persist.'),
        'port': StringSchema(description: 'Positive integer port.'),
        'useSasl': StringSchema(description: 'true | false'),
        'channels': StringSchema(
          description: 'JSON array, List, or comma-separated IRC channels.',
        ),
        'localAddOverride': StringSchema(
          description:
              'true | false; route Applications add-channel through local prefs.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3IrcAddChannelLocalEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_irc_add_channel_local: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final channel = _normalizeIrcChannelName(
      (request['channel'] as Object?)?.toString() ?? '',
    );
    if (channel.isEmpty) {
      return MCPCallResult(
        message: 'l3_irc_add_channel_local: need "channel"',
        parameters: {'ok': false, 'error': 'missing_channel'},
      );
    }
    final groupId =
        ((request['groupId'] as Object?)?.toString().trim().isNotEmpty ?? false)
        ? (request['groupId'] as Object).toString().trim()
        : _defaultL3IrcGroupId(channel);
    try {
      await Prefs.addIrcChannel(channel);
      await Prefs.setGroupName(groupId, 'IRC: $channel');
      final groups = await Prefs.getGroups();
      if (groups.add(groupId)) await Prefs.setGroups(groups);
      await Prefs.removeQuitGroup(groupId);
      final ffi = FakeUIKit.instance.im?.ffi;
      var liveStateUpdated = false;
      if (ffi != null) {
        await ffi.registerJoinedGroupState(groupId);
        liveStateUpdated = true;
      }
      final channelGroups = await _readIrcChannelGroups();
      AppLogger.info(
        '[L3] l3_irc_add_channel_local MUTATED channel=$channel group=$groupId',
      );
      return MCPCallResult(
        message: 'IRC channel mapped locally',
        parameters: {
          'ok': true,
          'channel': channel,
          'groupId': groupId,
          'liveStateUpdated': liveStateUpdated,
          'ircChannels': await Prefs.getIrcChannels(),
          'ircChannelGroups': channelGroups,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_irc_add_channel_local failed', e, st);
      return MCPCallResult(
        message: 'l3_irc_add_channel_local: failed: $e',
        parameters: {'ok': false, 'error': 'add_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_irc_add_channel_local',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): create a deterministic local '
        'IRC channel-to-group mapping without IrcAppManager.addChannel, '
        'libirc_client, or connectIrcChannel. Persists irc_channels, group name '
        '"IRC: <channel>", and live joined-group state when a session exists.',
    inputSchema: ObjectSchema(
      properties: {
        'channel': StringSchema(description: 'IRC channel, e.g. #toxee-l3.'),
        'groupId': StringSchema(
          description:
              'Optional deterministic local group id. Defaults from channel.',
        ),
      },
      required: ['channel'],
    ),
  ),
);

MCPCallEntry _l3IrcRemoveChannelLocalEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_irc_remove_channel_local: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final channel = _normalizeIrcChannelName(
      (request['channel'] as Object?)?.toString() ?? '',
    );
    if (channel.isEmpty) {
      return MCPCallResult(
        message: 'l3_irc_remove_channel_local: need "channel"',
        parameters: {'ok': false, 'error': 'missing_channel'},
      );
    }
    try {
      final beforeGroups = await _readIrcChannelGroups();
      final groupId =
          (request['groupId'] as Object?)?.toString().trim().isNotEmpty == true
          ? (request['groupId'] as Object).toString().trim()
          : beforeGroups[channel];
      await Prefs.removeIrcChannel(channel);
      if (groupId != null && groupId.isNotEmpty) {
        await _removeLocalIrcGroupMapping(groupId);
        await FakeUIKit.instance.im?.ffi.cleanupGroupState(groupId);
      }
      final channelGroups = await _readIrcChannelGroups();
      AppLogger.info(
        '[L3] l3_irc_remove_channel_local MUTATED channel=$channel group=$groupId',
      );
      return MCPCallResult(
        message: 'IRC channel removed locally',
        parameters: {
          'ok': true,
          'channel': channel,
          'groupId': groupId,
          'ircChannels': await Prefs.getIrcChannels(),
          'ircChannelGroups': channelGroups,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_irc_remove_channel_local failed', e, st);
      return MCPCallResult(
        message: 'l3_irc_remove_channel_local: failed: $e',
        parameters: {'ok': false, 'error': 'remove_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_irc_remove_channel_local',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): remove deterministic local '
        'IRC channel state from prefs/group mapping without disconnecting IRC or '
        'quitting a live group. Optional groupId clears a specific local mapping.',
    inputSchema: ObjectSchema(
      properties: {
        'channel': StringSchema(description: 'IRC channel, e.g. #toxee-l3.'),
        'groupId': StringSchema(
          description:
              'Optional local group id whose IRC display mapping is cleared.',
        ),
      },
      required: ['channel'],
    ),
  ),
);
