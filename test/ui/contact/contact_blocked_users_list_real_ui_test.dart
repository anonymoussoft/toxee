// S107 — Contacts: Blocked-Users tab listing surface (real-UI, L1 WidgetTester gate)
//
// Proves BOTH rendering branches of the REAL
// TencentCloudChatContactBlockList widget:
//
//   SEEDED branch  — dataInstance.contact.blockList seeded with one blocked
//     friend → the friend's nickname text is present in the tree and the
//     "No blocked users" text is absent.  Covers S107 A1 (listing renders
//     the blocked peer's row).
//
//   EMPTY branch   — dataInstance.contact.blockList cleared → the
//     "No blocked users" text is present and no nickname row remains.
//
// Design note — widget reads the SINGLETON, not the constructor param:
//   TencentCloudChatContactBlockList accepts a `blackList` constructor param
//   but ignores it at build time: both defaultBuilder and desktopBuilder read
//   `TencentCloudChat.instance.dataInstance.contact.blockList` directly
//   (tencent_cloud_chat_contact_block_list.dart:48 / :90).  Seeding is done
//   via contact.buildBlockList(...) and cleaned up via deleteFromBlockList in
//   tearDown.
//
// Row-key limitation (S107 Notes):
//   TencentCloudChatContactBlockListItem rows carry NO ValueKey — they are
//   plain InkWell widgets.  Assertion is by the friend's display name text,
//   which is rendered via TencentCloudChatContactItemContent._getShowName()
//   (priority: friendRemark > nickName > userID).  A future patch adding a
//   'contact_block_list_item:<userID>' key would let us assert by key instead.
//
// Unblock round-trip NOT covered (stays L3):
//   The unblock control (the blackUser switch on the user profile) round-trips
//   through Tim2Tox deleteFromBlackList + SharedPreferencesAdapter — native
//   code that cannot run hermetically.  That leg is covered by S29's gate
//   (tool/mcp_test/run_fixture_c_block.sh).  This gate covers the listing
//   surface only.
//
// Mobile-parity: TencentCloudChatContactBlockList is shared UIKit-fork code
// (not platform-specific); this gate covers iOS/Android at the same time as
// macOS/Linux/Windows.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_block_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

// ---------------------------------------------------------------------------
// Harness helper
// ---------------------------------------------------------------------------

/// Wraps [child] in a localized MaterialApp.
///
/// Registers all UIKit-fork localisation delegates so the fork's `tL10n`
/// singleton is resolved before any fork widget builds.
/// (TencentCloudChatState.didChangeDependencies calls
///  chatController.initGlobalAdapterInBuildPhase → TencentCloudChatIntl().init)
/// English locale is pinned for stable string assertions.
///
/// Wraps in a Navigator so the block-list widget's AppBar leading widget
/// (TencentCloudChatContactLeading) can call Navigator.of(context).pop()
/// without throwing; the default MaterialApp home Scaffold provides this.
Widget _harness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

// The exact English string for tL10n.noBlockList, from
// tencent_cloud_chat_localizations_en.dart:798.
const _noBlockListText = 'No blocked users';

// Display name used in both seeded tests — set as nickName so
// _getShowName() resolves to this value (nick takes precedence over userID
// when friendRemark is absent).
const _blockedFriendNick = 'Blocked Friend Nick';
const _blockedFriendId = 'blocked_friend_id';

void main() {
  // -------------------------------------------------------------------------
  // Shared tearDown: remove any seeded block-list entries and clear the
  // contactBuilder so tests are order-independent.
  // -------------------------------------------------------------------------
  tearDown(() {
    final contact = TencentCloudChat.instance.dataInstance.contact;
    // Remove the seeded entry if present (no-op when already empty).
    contact.deleteFromBlockList([_blockedFriendId], 'tearDown');
    contact.contactBuilder = null;
  });

  // =========================================================================
  // SEEDED branch — S107 A1
  // =========================================================================
  testWidgets(
    'S107 SEEDED: blocked-list with one entry renders the friend nickname '
    'and does NOT show "No blocked users"',
    (tester) async {
      final contact = TencentCloudChat.instance.dataInstance.contact;

      // Install the contactBuilder so the row's avatar/content sub-widgets
      // can be built.  Without it the InkWell Row children receive null
      // from the ?. calls which causes a type error.
      contact.contactBuilder = TencentCloudChatContactBuilders();

      // Seed the REAL singleton block list.
      // buildBlockList appends to _blockList and notifies listeners.
      // The widget reads this list during build at :48 / :90.
      final blockedFriend = V2TimFriendInfo(
        userID: _blockedFriendId,
        userProfile: V2TimUserFullInfo(nickName: _blockedFriendNick),
      );
      contact.buildBlockList([blockedFriend], 'test_seed');

      // Pump the REAL TencentCloudChatContactBlockList.
      // The constructor `blackList` param is intentionally empty — the widget
      // ignores it and reads the seeded singleton list instead.
      await tester.pumpWidget(
        _harness(
          const TencentCloudChatContactBlockList(blackList: []),
        ),
      );
      await tester.pump();

      // A1 (primary): the blocked friend's display name is rendered as a row.
      // This proves the real list branch executed:
      //   list.isNotEmpty → ListView.builder → TencentCloudChatContactBlockListItem
      //   → TencentCloudChatContactBlockListItemContent
      //   → TencentCloudChatContactItemContent._getShowName() → nickName.
      expect(
        find.text(_blockedFriendNick),
        findsOneWidget,
        reason:
            'S107-A1: the blocked friend nickname must render as a row in '
            'the blocked-users list',
      );

      // A1 (negative): the empty-state text must be absent.
      // Proves the real "seeded" code path was taken, not the empty-state path.
      expect(
        find.text(_noBlockListText),
        findsNothing,
        reason:
            'S107-A1: "No blocked users" must be absent when the block list '
            'is non-empty',
      );
    },
  );

  // =========================================================================
  // EMPTY branch
  // =========================================================================
  testWidgets(
    'S107 EMPTY: empty block list renders "No blocked users" and no name rows',
    (tester) async {
      // No contactBuilder needed for the empty branch — the ListView is never
      // built so no sub-widget builder calls occur.

      // Ensure the singleton block list is clean (tearDown guarantees this
      // across tests, but be explicit for clarity).
      final contact = TencentCloudChat.instance.dataInstance.contact;
      // deleteFromBlockList on a non-existent id is a no-op.
      contact.deleteFromBlockList([_blockedFriendId], 'pre_empty_test');

      await tester.pumpWidget(
        _harness(
          const TencentCloudChatContactBlockList(blackList: []),
        ),
      );
      await tester.pump();

      // The empty-state text must be present.
      // This proves list.isEmpty → Center(Text(tL10n.noBlockList)) branch at
      //   tencent_cloud_chat_contact_block_list.dart:72-80 (defaultBuilder).
      expect(
        find.text(_noBlockListText),
        findsOneWidget,
        reason:
            'EMPTY: "No blocked users" must render when the block list is empty',
      );

      // No stale nickname text from a previously seeded test.
      expect(
        find.text(_blockedFriendNick),
        findsNothing,
        reason: 'EMPTY: no blocked-friend row may appear for an empty list',
      );
    },
  );

  // =========================================================================
  // SEEDED→EMPTY ordering: makes the empty assertion above non-vacuous.
  // Pumps a seeded list THEN clears it and hot-rebuilds; asserts the empty
  // state replaces the row.  This proves the two branches are mutually
  // exclusive (not both-always-on).
  // =========================================================================
  testWidgets(
    'S107 SEEDED→EMPTY transition: clearing the block list switches from row '
    'to "No blocked users" text on rebuild',
    (tester) async {
      final contact = TencentCloudChat.instance.dataInstance.contact;
      contact.contactBuilder = TencentCloudChatContactBuilders();

      // Phase 1: seeded — row present.
      final blockedFriend = V2TimFriendInfo(
        userID: _blockedFriendId,
        userProfile: V2TimUserFullInfo(nickName: _blockedFriendNick),
      );
      contact.buildBlockList([blockedFriend], 'test_seed_transition');

      await tester.pumpWidget(
        _harness(
          const TencentCloudChatContactBlockList(blackList: []),
        ),
      );
      await tester.pump();

      // Row is present, empty text absent (same as the SEEDED test above).
      expect(find.text(_blockedFriendNick), findsOneWidget,
          reason: 'transition Phase-1: nick must be present after seed');
      expect(find.text(_noBlockListText), findsNothing,
          reason: 'transition Phase-1: empty text must be absent after seed');

      // Phase 2: clear the singleton list.
      // deleteFromBlockList notifies listeners; the widget's
      // _contactDataSubscription fires contactDataHandler → safeSetState → rebuild.
      contact.deleteFromBlockList([_blockedFriendId], 'test_clear_transition');
      await tester.pump(); // process the state notification
      await tester.pump(); // settle the rebuild

      // Now the empty branch must be active.
      expect(find.text(_noBlockListText), findsOneWidget,
          reason:
              'transition Phase-2: "No blocked users" must appear after clearing '
              'the list');
      expect(find.text(_blockedFriendNick), findsNothing,
          reason:
              'transition Phase-2: nick row must disappear after clearing the list');
    },
  );
}
