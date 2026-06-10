// Real-UI search FLOW gates (interactive residue of the search campaign).
//
// The keys-level anchors and the S93 matching+highlight LOGIC are already
// gated in `custom_search_keys_test.dart`. This file drives the interactive
// FLOWS that file does not:
//
//   * S48 — conversation-list / global search: type a query into the REAL
//     `CustomSearch` search field, the real `_matchesKeywordCaseInsensitive`
//     filter narrows the rendered result rows, clearing empties them, and a
//     fresh query restores the full match set.
//   * S135 — tap a search RESULT row → the production open-target handler
//     (`_navigateToMessage`) fires for the right conversation (group flavor;
//     C2C-conversation flavor added cheaply).
//   * S93 residue — in-conversation search drill-down
//     (`SearchChatHistoryWindow`): with >1 matching conversation result, the
//     REAL selection mechanic advances the highlighted/selected match and the
//     right-hand message panel follows.
//
// REAL-UI discipline: the production widgets, the production keyword filter,
// the production row render/highlight, and the production navigation handler
// all run. The ONLY thing replaced is the FFI-backed singleton fetch (the data
// source, not the logic): `CustomSearch.rawSearchDataOverride` supplies raw,
// PRE-FILTER inputs and `CustomSearch.onOpenConversation` observes the
// open-target — the repo's canonical function-typed-seam pattern (cf.
// LoginPage.exportAccount, SettingsPage.teardownSession).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/search/custom_search.dart';
import 'package:toxee/ui/search/search_chat_history_window.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// --- Localization harness (mirrors custom_search_keys_test.dart). These are
// toxee's own widgets and read AppLocalizations.of(context); a plain
// MaterialApp with the AppLocalizations delegate is sufficient — no UIKit
// TencentCloudChatIntl init required. ---
Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

Future<void> _pumpSettled(WidgetTester tester, Widget child) async {
  // Desktop-width surface so CustomSearch renders its desktop result columns
  // and SearchChatHistoryWindow renders the left/right split (not the mobile
  // single-column fallback, which has its own selection path we cover too).
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

V2TimMessage _textMessage({required String msgId, required String text}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_conv_type': 1,
    'message_conv_id': 'group_search_demo',
    // Empty sender keeps SearchChatHistoryWindow's _loadSenderDisplayNames a
    // no-op (it early-returns on empty sender IDs) so the drill-down never
    // touches the singleton getUsersInfo.
    'message_sender': '',
    'message_client_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_server_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_msg_id': msgId,
    'message_elem_array': <Map<String, dynamic>>[
      V2TimTextElem(text: text).toJson(),
    ],
  });
}

V2TimFriendInfoResult _contact({
  required String userID,
  required String remark,
}) {
  return V2TimFriendInfoResult(
    resultCode: 0,
    relation: 0,
    friendInfo: V2TimFriendInfo(userID: userID, friendRemark: remark),
  );
}

V2TimGroupInfo _group({required String groupID, required String groupName}) {
  return V2TimGroupInfo(
    groupID: groupID,
    groupType: 'Work',
    groupName: groupName,
  );
}

TencentCloudChatSearchResultItemData _messageResult({
  required String conversationID,
  required String showName,
  String? userID,
  String? groupID,
  required List<V2TimMessage> messages,
}) {
  return TencentCloudChatSearchResultItemData(
    showName: showName,
    conversationID: conversationID,
    userID: userID,
    groupID: groupID,
    messageList: messages,
    totalCount: messages.length,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // S48 — global / conversation-list search: type → filter → clear → re-query.
  // The three contacts all carry the shared token "neighbour" so a broad query
  // surfaces all of them; the distinct "Ali" token surfaces only Alice. The
  // REAL `_matchesKeywordCaseInsensitive` filter does the narrowing — the seam
  // only supplies the raw (unfiltered) contact set.
  // ---------------------------------------------------------------------------
  group('S48 global search filter flow', () {
    final allContacts = <V2TimFriendInfoResult>[
      _contact(userID: 'tox_alice', remark: 'Alice neighbour'),
      _contact(userID: 'tox_bob', remark: 'Bob neighbour'),
      _contact(userID: 'tox_charlie', remark: 'Charlie neighbour'),
    ];

    Future<void> pumpSearch(WidgetTester tester) async {
      await _pumpSettled(
        tester,
        CustomSearch(
          // No userID/groupID/keyWord → GLOBAL, non-embedded: renders the real
          // in-widget search field so we can type into the production input.
          rawSearchDataOverride: (keyword) async => (
            contacts: allContacts,
            groups: const <V2TimGroupInfo>[],
            messages: const <TencentCloudChatSearchResultItemData>[],
          ),
        ),
      );
    }

    // Enter text into the production field and let the 300ms debounce +
    // async _performSearch settle.
    Future<void> typeQuery(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(UiKeys.messageSearchField), text);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    // The highlighted contact title is a RichText (not a plain Text), so we
    // assert on the deterministic per-row key instead of the visible string.
    final aliceRow = find.byKey(UiKeys.searchResultContact('tox_alice'));
    final bobRow = find.byKey(UiKeys.searchResultContact('tox_bob'));
    final charlieRow = find.byKey(UiKeys.searchResultContact('tox_charlie'));

    testWidgets('typing "Ali" filters the result rows to Alice only', (
      tester,
    ) async {
      await pumpSearch(tester);
      // Real field present (A1 / A7: exactly one search TextField, no double).
      expect(find.byKey(UiKeys.messageSearchField), findsOneWidget);

      await typeQuery(tester, 'Ali');

      expect(aliceRow, findsOneWidget,
          reason: 'the only contact whose remark contains "Ali" must survive');
      expect(bobRow, findsNothing,
          reason: 'Bob has no "Ali" — the real filter must drop it');
      expect(charlieRow, findsNothing,
          reason: 'Charlie has no "Ali" — the real filter must drop it');
    });

    testWidgets('clearing the query empties results; re-querying restores them',
        (tester) async {
      await pumpSearch(tester);

      // Broad shared token → all three rows render (full match set).
      await typeQuery(tester, 'neighbour');
      expect(aliceRow, findsOneWidget);
      expect(bobRow, findsOneWidget);
      expect(charlieRow, findsOneWidget);

      // Clear → _performSearch early-returns on empty keyword, emptying the
      // result rows (in the app shell the pane then swaps back to the
      // conversation list; that shell swap is exercised by the home surface,
      // this widget owns the result-emptying half).
      await typeQuery(tester, '');
      expect(aliceRow, findsNothing);
      expect(bobRow, findsNothing);
      expect(charlieRow, findsNothing);

      // Re-query restores the full match set — proves the field/flow recovers,
      // not a one-shot.
      await typeQuery(tester, 'neighbour');
      expect(aliceRow, findsOneWidget);
      expect(bobRow, findsOneWidget);
      expect(charlieRow, findsOneWidget);
    });

    testWidgets('case-insensitive query still narrows correctly', (
      tester,
    ) async {
      await pumpSearch(tester);
      await typeQuery(tester, 'ALICE');
      expect(aliceRow, findsOneWidget,
          reason: 'the real filter lower-cases both sides');
      expect(bobRow, findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // S135 — tap a search RESULT row → production open-target handler fires for
  // the right conversation. Group flavor is required; C2C-conversation flavor
  // added cheaply. Both tap the REAL keyed rows and assert the REAL
  // `_navigateToMessage` reports the correct userID/groupID via the seam.
  // ---------------------------------------------------------------------------
  group('S135 result-row opens the right conversation', () {
    testWidgets('tapping a GROUP result row opens that group (groupID routed)',
        (tester) async {
      String? openedUserID = '__unset__';
      String? openedGroupID = '__unset__';
      var openCount = 0;

      final group = _group(groupID: 'gidG', groupName: 'Project Falcon');

      await _pumpSettled(
        tester,
        CustomSearch(
          rawSearchDataOverride: (keyword) async => (
            contacts: const <V2TimFriendInfoResult>[],
            groups: <V2TimGroupInfo>[group],
            messages: const <TencentCloudChatSearchResultItemData>[],
          ),
          onOpenConversation: ({userID, groupID, targetMessage}) {
            openCount++;
            openedUserID = userID;
            openedGroupID = groupID;
          },
        ),
      );

      await tester.enterText(
        find.byKey(UiKeys.messageSearchField),
        'Falcon',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // The REAL keyed group row must exist (proves the group survived the
      // real filter + rendered with its deterministic key).
      final rowFinder = find.byKey(UiKeys.searchResultGroup('gidG'));
      expect(rowFinder, findsOneWidget);

      await tester.tap(rowFinder);
      await tester.pump();

      expect(openCount, 1, reason: 'the open-target handler must fire exactly once');
      expect(openedGroupID, 'gidG',
          reason: 'the GROUP row must route groupID to _navigateToMessage');
      expect(openedUserID, isNull,
          reason: 'a group open carries no userID');
    });

    testWidgets(
        'tapping a CONVERSATION fallback row opens that conversation (c2c routed)',
        (tester) async {
      String? openedUserID = '__unset__';
      String? openedGroupID = '__unset__';

      // Conversation-fallback rows only render when contacts+groups+messages
      // are all empty (custom_search.dart fallback branch). The fallback list
      // comes from UikitDataFacade.conversationList, which is the singleton —
      // so this flavor uses the MESSAGE result row instead, whose onTap path is
      // the SAME `_navigateToMessage` open-target but drill-down via the
      // history window. We assert the C2C-message result row drives the same
      // handler through its drill-down "Open chat".
      final c2c = _messageResult(
        conversationID: 'c2c_tox_dave',
        showName: 'Dave',
        userID: 'tox_dave',
        messages: <V2TimMessage>[
          _textMessage(msgId: 'm-dave-1', text: 'pizza on friday'),
        ],
      );

      await _pumpSettled(
        tester,
        CustomSearch(
          rawSearchDataOverride: (keyword) async => (
            contacts: const <V2TimFriendInfoResult>[],
            groups: const <V2TimGroupInfo>[],
            messages: <TencentCloudChatSearchResultItemData>[c2c],
          ),
          onOpenConversation: ({userID, groupID, targetMessage}) {
            openedUserID = userID;
            openedGroupID = groupID;
          },
        ),
      );

      await tester.enterText(
        find.byKey(UiKeys.messageSearchField),
        'pizza',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // The C2C message result row is keyed by its conversationID.
      final rowFinder =
          find.byKey(UiKeys.searchResultMessage('c2c_tox_dave'));
      expect(rowFinder, findsOneWidget);

      // Tapping it opens the drill-down history window (real navigation).
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();
      expect(find.byType(SearchChatHistoryWindow), findsOneWidget,
          reason: 'the message result row opens the real drill-down window');

      // "Open chat" in the drill-down routes through the SAME _navigateToMessage
      // open-target with the C2C userID.
      await tester.tap(find.byKey(UiKeys.searchHistoryMessage('m-dave-1')));
      await tester.pumpAndSettle();
      expect(openedUserID, 'tox_dave',
          reason: 'the C2C drill-down must route userID to the open-target');
      expect(openedGroupID, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // S93 residue — in-conversation search drill-down advances the selected match
  // across >1 result. SearchChatHistoryWindow has no dedicated next/prev button:
  // the production "advance across matches" mechanic is selecting among the
  // result rows in the left panel (each a matching conversation), which moves
  // `_selectedIndex` and re-renders the right-hand message panel. We drive that
  // real selection forward and back and assert the highlighted/selected match
  // (and its message panel) follows. (No wrap control exists in production — see
  // notes; selection clamps rather than wraps.)
  // ---------------------------------------------------------------------------
  group('S93 drill-down advances the selected match', () {
    SearchChatHistoryWindow buildWindow({
      void Function({String? userID, String? groupID, V2TimMessage? targetMessage})?
          onNav,
    }) {
      final first = _messageResult(
        conversationID: 'c2c_first',
        showName: 'First Friend',
        userID: 'tox_first',
        messages: <V2TimMessage>[
          _textMessage(msgId: 'first-1', text: 'pizza one'),
          _textMessage(msgId: 'first-2', text: 'pizza two'),
        ],
      );
      final second = _messageResult(
        conversationID: 'c2c_second',
        showName: 'Second Friend',
        userID: 'tox_second',
        messages: <V2TimMessage>[
          _textMessage(msgId: 'second-1', text: 'pizza three'),
        ],
      );
      final third = _messageResult(
        conversationID: 'c2c_third',
        showName: 'Third Friend',
        userID: 'tox_third',
        messages: <V2TimMessage>[
          _textMessage(msgId: 'third-1', text: 'pizza four'),
        ],
      );
      return SearchChatHistoryWindow(
        initialKeyword: 'pizza',
        messageSearchResults: <TencentCloudChatSearchResultItemData>[
          first,
          second,
          third,
        ],
        initialSelectedResult: first,
        onNavigateToMessage: onNav ?? ({userID, groupID, targetMessage}) {},
      );
    }

    testWidgets(
        'selecting the next result row advances the highlighted match + panel',
        (tester) async {
      await _pumpSettled(tester, buildWindow());

      // Initial selection = first result: its messages are in the right panel.
      expect(find.byKey(UiKeys.searchHistoryMessage('first-1')), findsOneWidget);
      expect(find.byKey(UiKeys.searchHistoryMessage('first-2')), findsOneWidget);
      expect(find.byKey(UiKeys.searchHistoryMessage('second-1')), findsNothing,
          reason: 'the second result is not selected yet');

      // The selected (first) left row is emphasized (FontWeight.w600 title).
      final firstTitleBefore = tester.widget<Text>(
        find.descendant(
          of: find.byKey(UiKeys.searchResultMessage('c2c_first')),
          matching: find.text('First Friend'),
        ),
      );
      expect(firstTitleBefore.style?.fontWeight, FontWeight.w600,
          reason: 'the initially-selected result must render emphasized');

      // ADVANCE to the second result row (the real selection mechanic).
      await tester.tap(find.byKey(UiKeys.searchResultMessage('c2c_second')));
      await tester.pumpAndSettle();

      // Right panel now shows the SECOND result's message; first is gone.
      expect(find.byKey(UiKeys.searchHistoryMessage('second-1')), findsOneWidget,
          reason: 'advancing must re-render the panel to the new match');
      expect(find.byKey(UiKeys.searchHistoryMessage('first-1')), findsNothing);

      // The second left row is now the emphasized/selected one; first is not.
      final secondTitleAfter = tester.widget<Text>(
        find.descendant(
          of: find.byKey(UiKeys.searchResultMessage('c2c_second')),
          matching: find.text('Second Friend'),
        ),
      );
      expect(secondTitleAfter.style?.fontWeight, FontWeight.w600,
          reason: 'the newly-selected result must become emphasized');
      final firstTitleAfter = tester.widget<Text>(
        find.descendant(
          of: find.byKey(UiKeys.searchResultMessage('c2c_first')),
          matching: find.text('First Friend'),
        ),
      );
      expect(firstTitleAfter.style?.fontWeight, FontWeight.w500,
          reason: 'the previously-selected result must lose emphasis');
    });

    testWidgets('selection moves forward across three results and back (prev)',
        (tester) async {
      await _pumpSettled(tester, buildWindow());

      // forward: first -> second -> third
      await tester.tap(find.byKey(UiKeys.searchResultMessage('c2c_second')));
      await tester.pumpAndSettle();
      expect(find.byKey(UiKeys.searchHistoryMessage('second-1')), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.searchResultMessage('c2c_third')));
      await tester.pumpAndSettle();
      expect(find.byKey(UiKeys.searchHistoryMessage('third-1')), findsOneWidget);
      expect(find.byKey(UiKeys.searchHistoryMessage('second-1')), findsNothing);

      // back (prev): third -> first
      await tester.tap(find.byKey(UiKeys.searchResultMessage('c2c_first')));
      await tester.pumpAndSettle();
      expect(find.byKey(UiKeys.searchHistoryMessage('first-1')), findsOneWidget);
      expect(find.byKey(UiKeys.searchHistoryMessage('third-1')), findsNothing);

      final firstTitle = tester.widget<Text>(
        find.descendant(
          of: find.byKey(UiKeys.searchResultMessage('c2c_first')),
          matching: find.text('First Friend'),
        ),
      );
      expect(firstTitle.style?.fontWeight, FontWeight.w600,
          reason: 'navigating back must re-emphasize the first result');
    });

    testWidgets('tapping a drilled-down message opens the right conversation',
        (tester) async {
      String? openedUserID = '__unset__';
      String? openedGroupID = '__unset__';

      await _pumpSettled(
        tester,
        buildWindow(
          onNav: ({userID, groupID, targetMessage}) {
            openedUserID = userID;
            openedGroupID = groupID;
          },
        ),
      );

      // Advance to the second result, then open its message — the open-target
      // must carry the SECOND conversation's userID, proving the selected match
      // drives navigation (not the initial one).
      await tester.tap(find.byKey(UiKeys.searchResultMessage('c2c_second')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.searchHistoryMessage('second-1')));
      await tester.pumpAndSettle();

      expect(openedUserID, 'tox_second',
          reason: 'the open-target must follow the advanced selection');
      expect(openedGroupID, isNull);
    });
  });
}
