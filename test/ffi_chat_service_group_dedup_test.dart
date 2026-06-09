import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

class _TestFfiChatService extends FfiChatService {
  _TestFfiChatService({MessageHistoryPersistence? persistence})
      : super(messageHistoryPersistence: persistence);

  void seedLastGroupMessageForTest({
    required String gid,
    required String from,
    required String text,
    required DateTime timestamp,
  }) {
    lastMessages[gid] = ChatMessage(
      text: text,
      fromUserId: from,
      isSelf: false,
      timestamp: timestamp,
      groupId: gid,
      msgID: 'seed-$gid',
    );
  }

  ChatMessage? lastGroupMessage(String gid) => lastMessages[gid];

  List<ChatMessage> historyFor(String gid) => getHistory(gid);
}

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService group dedup', () {
    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('ffi_group_dedup_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
          case 'getApplicationDocumentsDirectory':
            return tempRoot.path;
          case 'getApplicationCacheDirectory':
            return '${tempRoot.path}/cache';
          case 'getTemporaryDirectory':
            return '${tempRoot.path}/temp';
          case 'getDownloadsDirectory':
            return '${tempRoot.path}/downloads';
          default:
            return null;
        }
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'first inbound group text of a session is not treated as duplicate just because lastByPeer matches',
      () {
        final service = _TestFfiChatService();
        const gid = 'group_64hex_like_value';
        const sender = 'peer_pubkey_1234';
        const text = 'hello-group';

        // Simulate the state left by an earlier path updating lastByPeer
        // without a cached history row yet. The next real ingest should still
        // be accepted once, rather than being dropped as a duplicate.
        service.seedLastGroupMessageForTest(
          gid: gid,
          from: sender,
          text: text,
          timestamp: DateTime.now(),
        );

        final accepted = service.ingestInboundGroupText(
          gid: gid,
          from: sender,
          text: text,
        );

        expect(
          accepted,
          isTrue,
          reason:
              'a fresh inbound group message must not be dropped solely because lastByPeer already mirrors it',
        );
      },
      skip: skipReason,
    );

    test(
      'when history already contains the inbound group text, ingest refreshes in-memory state instead of dropping it entirely',
      () async {
        const gid = 'group_history_only';
        const sender = 'peer_pubkey_hist';
        const text = 'hello-from-history';
        final persistence = MessageHistoryPersistence(instanceId: 999001);
        addTearDown(() async {
          await persistence.clearHistory(gid);
          await persistence.dispose();
        });
        final service = _TestFfiChatService(persistence: persistence);

        final existing = ChatMessage(
          text: text,
          fromUserId: sender,
          isSelf: false,
          timestamp: DateTime.now(),
          groupId: gid,
          msgID: 'persisted-$gid',
        );
        await persistence.appendHistory(gid, existing);

        final accepted = service.ingestInboundGroupText(
          gid: gid,
          from: sender,
          text: text,
        );

        expect(
          accepted,
          isTrue,
          reason:
              'an inbound group message that already exists in persisted history still needs to refresh FfiChatService in-memory/UI state',
        );
        expect(
          service.lastGroupMessage(gid)?.text,
          text,
          reason: 'lastByPeer should be refreshed for conversation preview state',
        );
      },
      skip: skipReason,
    );
  });
}
