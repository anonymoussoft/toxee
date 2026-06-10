// Real-UI L1 WidgetTester coverage for the sticker / emoji panel (S22 + S23).
//
// These exercise the REAL vendored, user-owned `tencent_cloud_chat_sticker`
// panel widget (third_party/chat-uikit-flutter/tencent_cloud_chat_sticker,
// mapped via pubspec_overrides.yaml) wired to the REAL fork message-input
// composer, driving the REAL production routing through real taps + the real
// UIKit event bus. No production logic is re-implemented in this file.
//
// The two defining invariants under test:
//   * S22 (emoji, type 0): tapping an emoji cell INSERTS its token into the
//     composer text (with the empty-field leading space). The real path is
//     panel GestureDetector.onTap -> sendStickerMessage -> emitUIKitListener
//     -> the desktop input's real `uikitListener` (input_desktop.dart:86-100,
//     type==0 branch).
//   * S23 (custom face, type 1): tapping a custom-face cell MUST NOT touch the
//     composer text, and the panel MUST emit the `stickClick{type:1}` event
//     that `TencentCloudChatMessageSeparateData.uikitListener`
//     (separate_data.dart:300-310) consumes to call `sendFaceMessage` (the
//     `__face__:{json}` wire send). The desktop input's real listener for
//     type==1 only calls closeSticker(), leaving text untouched.
//
// We install a minimal fake SDK platform whose addUIKit/emitUIKit/removeUIKit
// methods are an in-memory listener registry with the SAME semantics as the
// production `Tim2ToxSdkPlatform` registry (tim2tox_sdk_platform.dart:3542+).
// That registry fires listeners synchronously in-process, so a real tap on the
// real panel really drives the real composer listener — that is the seam the
// production code uses, not a re-implementation of routing.
//
// Mobile parity: the type-0 insertion lives identically in the desktop AND
// mobile inputs (input_mobile.dart:93-105 has the same `space + name` branch),
// and the type-1 face SEND is routed by the platform-agnostic shared
// `separate_data.uikitListener`. Neither input inserts text for type 1. So the
// behavior under test is shared Dart and covers iOS/Android identically; the
// only platform difference (desktop closes the panel on a custom-face tap,
// mobile keeps it open) is not the subject of these gates.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_init_data.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_model.dart';
import 'package:tencent_cloud_chat_sticker/tencent_cloud_chat_sticker_widget.dart';

// The real names from the vendored default packs. A type-0 (default emoji)
// item and a type-1 (custom face) item — exactly the two the specs name.
const String _kEmojiName = '[TUIEmoji_Smile]';
const String _kFaceName = '[gcs00]';

// A minimal 1x1 transparent PNG so AssetImage resolution in the grid cells
// succeeds instead of logging a missing-asset FlutterError under the binding.
final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

// An asset bundle that answers any sticker `.png` key with the 1x1 PNG above
// and delegates everything else (manifests, fonts) to the default test
// rootBundle. Installed via DefaultAssetBundle so the panel's real
// Image(AssetImage(..., package: 'tencent_cloud_chat_sticker')) cells resolve
// to a valid image instead of throwing a missing-asset error under the binding
// (the bundled stickers are not present in the test asset bundle).
class _StickerTestAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.png')) {
      return ByteData.view(_kTransparentPng.buffer);
    }
    return rootBundle.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    return rootBundle.loadString(key, cache: cache);
  }
}

/// In-memory UIKit-listener registry that matches the production
/// `Tim2ToxSdkPlatform` semantics (synchronous dispatch, UUID-keyed map). This
/// is the bus the real panel + real composer talk over; it is NOT routing
/// logic.
class _FakeStickerSdkPlatform extends TencentCloudChatSdkPlatform {
  final Map<String, V2TimUIKitListener> _listeners = {};
  int _seq = 0;

  @override
  bool get isCustomPlatform => true;

  @override
  String addUIKitListener({required V2TimUIKitListener listener}) {
    final uuid = 'fake-uikit-${_seq++}';
    _listeners[uuid] = listener;
    return uuid;
  }

  @override
  void removeUIKitListener({String? uuid}) {
    if (uuid != null) _listeners.remove(uuid);
  }

  @override
  void emitUIKitListener({required Map<String, dynamic> data}) {
    // Snapshot to tolerate listeners that (de)register during dispatch.
    for (final l in _listeners.values.toList()) {
      l.onUiKitEventEmit(data);
    }
  }
}

// Wrap a child so the fork's i18n singleton (`tL10n`) is initialized from a
// real Localizations ancestor before the child builds — the fork composer
// reads `tL10n` during build and throws if it is uninitialized. (Copied from
// chat_core_real_ui_test.dart per the campaign's harness rule — do not import
// another test file's private helpers.)
Widget _localized({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          // Provide the sticker-PNG asset bundle in scope so the panel's
          // AssetImage cells resolve (the bundled stickers aren't in the test
          // asset bundle). AssetImage reads DefaultAssetBundle.of(context).
          return DefaultAssetBundle(
            bundle: _StickerTestAssetBundle(),
            child: child,
          );
        },
      ),
    ),
  );
}

// The stub input methods (same shape as chat_core's). For S23 we record the
// closeSticker() call: the desktop input's real type==1 branch invokes it,
// proving the custom-face tap was routed (and that no text insertion happened).
MessageInputBuilderMethods _stubMethods({
  List<String>? sentSink,
  VoidCallback? onCloseSticker,
}) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
      sentSink?.add(text);
    },
    sendImageMessage: ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage: ({String? filePath, String? fileName, dynamic inputElement}) {},
    sendVoiceMessage: ({required String voicePath, required int duration}) {},
    onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
    controller: Object(),
    clearRepliedMessage: () {},
    setDesktopMentionBoxPositionX: (_) {},
    setDesktopMentionBoxPositionY: (_) {},
    setActiveMentionIndex: (_) {},
    setCurrentFilteredMembersListForMention: (_) {},
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder: Object(),
    closeSticker: () => onCloseSticker?.call(),
  );
}

MessageInputBuilderData _data() {
  return MessageInputBuilderData(
    userID: 'friend1',
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    desktopMentionBoxPositionX: 0,
    desktopMentionBoxPositionY: 0,
    isGroupAdmin: false,
    activeMentionIndex: -1,
    currentFilteredMembersListForMention: const [],
    groupMemberList: const [],
    currentConversationShowName: 'Friend One',
    hasStickerPlugin: true,
    stickerPluginInstance: null,
  );
}

// Seed the panel's static initData with one default-emoji pack (type 0,
// index 0) and one custom-face pack (type 1, index 1), each with a single
// item. The panel reads `TencentCloudChatStickerPlugin.initData` directly, so
// this drives the real panel build + the real onTap payloads (the names + type
// + stickerIndex are what `sendStickerMessage` emits).
void _seedStickerInitData() {
  TencentCloudChatStickerPlugin.initData = TencentCloudChatStickerInitData(
    userID: 'me',
    customStickerLists: <TencentCloudChatCustomSticker>[
      // index 0 in the list = the default-emoji pack (type 0). Its grid cell
      // emits type:0 -> the composer inserts the token. The tab iconPath is
      // deliberately DISTINCT from the grid item path so the grid-cell finder
      // (matched by asset name) is unambiguous (the tab uses the same Image
      // widget type with its iconPath).
      TencentCloudChatCustomSticker(
        name: 'All Stickers',
        type: 0,
        index: 0,
        // A multi-column grid keeps the single cell small (W/4) so it fits
        // inside the panel's ~220px-tall content area and stays hit-testable.
        rowNum: 4,
        iconPath: 'assets/stickers/_tab_emoji.png',
        stickers: <TencentCloudChatCustomStickerItem>[
          TencentCloudChatCustomStickerItem(
            name: _kEmojiName,
            path: 'assets/stickers/emoji_0.png',
          ),
        ],
      ),
      // index 1 in the list = a custom-face pack (type 1). Its grid cell emits
      // type:1 -> routed to sendFaceMessage; composer text untouched.
      TencentCloudChatCustomSticker(
        name: '',
        type: 1,
        index: 1,
        rowNum: 4,
        iconPath: 'assets/stickers/_tab_face.png',
        stickers: <TencentCloudChatCustomStickerItem>[
          TencentCloudChatCustomStickerItem(
            name: _kFaceName,
            path: 'assets/custom_face_resource/4352/gcs00@2x.png',
          ),
        ],
      ),
    ],
  );
}

// Reads the live composer text out of the real ExtendedTextField controller.
String _composerText(WidgetTester tester) {
  final field = tester.widget<ExtendedTextField>(find.byType(ExtendedTextField));
  return field.controller?.text ?? '';
}

// Finds the GestureDetector whose subtree shows the AssetImage for [assetName]
// (used for both a grid cell, matched by the item path, and a tab, matched by
// the tab iconPath — the tab/grid asset names are kept distinct so a match is
// unambiguous).
Finder _cellForAsset(String assetName) {
  return find.ancestor(
    of: find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == assetName),
    matching: find.byType(GestureDetector),
  );
}

Future<void> _pumpPanelAndComposer(
  WidgetTester tester, {
  List<String>? sentSink,
  VoidCallback? onCloseSticker,
}) async {
  // A modest width keeps the 4-column grid's single cell small enough (W/4) to
  // fit inside the panel's ~220px content area so it stays hit-testable.
  tester.view.physicalSize = const Size(760, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final provider = TencentCloudChatMessageSeparateDataProvider();
  await tester.pumpWidget(
    _localized(
      child: TencentCloudChatMessageDataProviderInherited(
        dataProvider: provider,
        // The real composer (registers its real type==0/type==1 uikitListener
        // in initState) AND the real sticker panel, in one tree.
        child: Column(
          children: [
            TencentCloudChatMessageInputDesktop(
              inputData: _data(),
              inputMethods:
                  _stubMethods(sentSink: sentSink, onCloseSticker: onCloseSticker),
            ),
            const SizedBox(
              height: 320,
              child: TencentCloudChatStickerPanel(),
            ),
          ],
        ),
      ),
    ),
  );
  // The panel body is behind a 60ms FutureBuilder ease-in (delay300()); pump
  // past it so the tabs + grid mount.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Install the fake platform that provides the UIKit-listener registry; the
  // real composer + real panel talk over it. Restore the previous platform
  // after each test so the suite stays order-independent.
  late TencentCloudChatSdkPlatform previousPlatform;
  setUp(() {
    previousPlatform = TencentCloudChatSdkPlatform.instance;
    TencentCloudChatSdkPlatform.instance = _FakeStickerSdkPlatform();
    _seedStickerInitData();
  });
  tearDown(() {
    TencentCloudChatSdkPlatform.instance = previousPlatform;
  });

  // -------------------------------------------------------------------------
  // S22 — emoji panel (type 0) tap INSERTS the token into the composer.
  // -------------------------------------------------------------------------
  testWidgets(
    'S22 tapping a default-emoji cell inserts the token into the real composer',
    (tester) async {
      final sent = <String>[];
      await _pumpPanelAndComposer(tester, sentSink: sent);

      // The real panel mounted (no "暂无表情" error node).
      expect(find.byType(TencentCloudChatStickerPanel), findsOneWidget);
      expect(find.byType(TencentCloudChatStickerError), findsNothing);

      // Composer starts empty (non-vacuous baseline for the insertion below).
      expect(_composerText(tester), '');

      final emojiCell = _cellForAsset('assets/stickers/emoji_0.png');
      expect(emojiCell, findsOneWidget,
          reason: 'the default-emoji grid cell should render on the active tab');

      // REAL tap -> real sendStickerMessage -> real emitUIKitListener -> the
      // composer's real type==0 uikitListener inserts the token.
      await tester.tap(emojiCell.first);
      await tester.pumpAndSettle();

      // A4: the empty-field branch fires the leading space -> " [TUIEmoji_Smile]".
      expect(_composerText(tester), ' $_kEmojiName',
          reason:
              'type-0 stickClick must insert "<space>$_kEmojiName" into the composer');
      // Emoji insertion must NOT send a text message (it only edits the field).
      expect(sent, isEmpty, reason: 'inserting an emoji must not send a message');
    },
  );

  // -------------------------------------------------------------------------
  // S23 — custom-face panel (type 1) tap routes to the FACE send path and does
  // NOT touch the composer text (the defining S23 invariant).
  // -------------------------------------------------------------------------
  testWidgets(
    'S23 tapping a custom-face cell emits the face-send event and leaves the composer text untouched',
    (tester) async {
      // Register a recording listener through the SAME real addUIKitListener
      // API the production routing uses. This observes the exact `stickClick`
      // event the panel emits — the event `separate_data.uikitListener`
      // consumes to call sendFaceMessage(stickerIndex, name). We are observing
      // the real emitted contract, not re-implementing the route.
      final emitted = <Map<String, dynamic>>[];
      final platform =
          TencentCloudChatSdkPlatform.instance as _FakeStickerSdkPlatform;
      platform.addUIKitListener(
        listener: V2TimUIKitListener(
          onUiKitEventEmit: (data) => emitted.add(Map<String, dynamic>.from(data)),
        ),
      );

      var closeStickerCalls = 0;
      final sent = <String>[];
      await _pumpPanelAndComposer(
        tester,
        sentSink: sent,
        onCloseSticker: () => closeStickerCalls++,
      );

      expect(find.byType(TencentCloudChatStickerError), findsNothing);
      expect(_composerText(tester), '', reason: 'composer starts empty');

      // The panel opens on the first (emoji) tab; switch to the custom-face tab
      // via a REAL tab tap so its grid renders (real handleTabClick setState).
      final faceTab = _cellForAsset('assets/stickers/_tab_face.png');
      expect(faceTab, findsOneWidget, reason: 'the custom-face tab should render');
      await tester.tap(faceTab);
      await tester.pumpAndSettle();

      final faceCell =
          _cellForAsset('assets/custom_face_resource/4352/gcs00@2x.png');
      expect(faceCell, findsOneWidget,
          reason: 'the custom-face grid cell should render on the face tab');

      // REAL tap on the custom-face cell.
      await tester.tap(faceCell);
      await tester.pumpAndSettle();

      // A8 (defining invariant): the composer text is UNCHANGED — a custom face
      // must NOT be inserted as text (this is what distinguishes S23 from S22).
      expect(_composerText(tester), '',
          reason: 'a custom-face tap must not touch the composer text');
      // And it must not have gone out as a plain text message either.
      expect(sent, isEmpty);

      // A6: the desktop input's real type==1 branch requested the panel close.
      expect(closeStickerCalls, greaterThan(0),
          reason: 'the desktop input closes the sticker panel on a type-1 tap');

      // A9 (send contract): the panel emitted exactly the `stickClick{type:1}`
      // event carrying the face name + sticker index that
      // `separate_data.sendFaceMessage` consumes for the `__face__:{json}` wire
      // send. (Asserting the real emitted event, the seam the send is wired to.)
      //
      // Production truth (sticker_widget.dart:173-177): sendStickerMessage
      // strips the surrounding brackets for a non-TUIEmoji "[name]" before
      // emitting, so the custom-face wire name is "gcs00" (the bracketed
      // "[gcs00]" form is only kept for default TUIEmoji_* tokens). The
      // bracket-stripped value is exactly what flows into createFaceMessage.
      const String kExpectedFaceWireName = 'gcs00';
      final faceEvents = emitted
          .where((e) => e['eventType'] == 'stickClick' && e['type'] == 1)
          .toList();
      expect(faceEvents, isNotEmpty,
          reason: 'the custom-face tap must emit a type-1 stickClick event');
      expect(faceEvents.single['name'], kExpectedFaceWireName,
          reason:
              'the emitted face event carries the bracket-stripped face name (production transform)');
      expect(faceEvents.single['stickerIndex'], 1,
          reason: 'the emitted face event carries the pack sticker index');

      // Negative: no type-0 (emoji insertion) event was emitted by a face tap.
      expect(
        emitted.where((e) => e['eventType'] == 'stickClick' && e['type'] == 0),
        isEmpty,
        reason: 'a custom-face tap must not emit a type-0 (insert-text) event',
      );
    },
  );
}
