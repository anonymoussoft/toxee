# Investigation: Should we split `home_page.dart` and `prefs.dart`?

**Date:** 2026-05-20
**Decision:** **DO NOT SPLIT** either file in this pass.
**Author:** Code-architect agent (commissioned 2026-05-20)

## Summary

The two largest files in `lib/` —

- `lib/ui/home_page.dart` — 1,996 LOC
- `lib/util/prefs.dart` — 1,982 LOC

— both exceed the `tool/check_complexity.dart` 500-LOC warning threshold. The user
asked whether to split them as part of the testing/maintainability push. The
short answer after investigation is **no, not as a single sweep**. The deeper
answer follows.

## What each file actually contains

### `lib/ui/home_page.dart` (1,996 LOC)

`HomePage` / `_HomePageState` is the root widget for the authenticated session.
The file uses `part` directives to include two extension files:

- `home_page_bootstrap.dart` (~870 LOC) — `_initAfterSessionReady()`: UIKit
  component registration, all subscription setup (connection, conversation,
  contact, group profile, friends, friend applications), notification routing,
  conversation context menu handler. Also contains `_ToxeeMessageHeaderInfo`
  (a self-contained widget, ~100 LOC).
- `home_page_plugins.dart` (~200 LOC) — Sticker / text-translate / sound-to-text
  plugin registration logic.

The remaining 1,996 LOC in `home_page.dart` itself contains:

- The widget `build()` tree with responsive layout, keyboard shortcuts, bottom
  nav, LAN banner — ~330 LOC
- `initState` / `dispose` / `didChangeAppLifecycleState` lifecycle — ~130 LOC
- Group sync: `_handleGroupChanged`, `_loadPersistedGroupsIntoUIKit` — ~230 LOC
- Media / file sending: `_sendMedia`, `_createSelfQrCardImage`,
  `_buildDesktopInputOptions` — ~220 LOC
- Contact / conversation management: `_selectConversation`, `_openChat`,
  `_showConversationContextMenu`, `_showUserProfileOnRight` — ~200 LOC
- Dialogs: `_showAddFriendDialog`, `_showAddGroupDialog`,
  `_showJoinIrcChannelDialog`, `_showMessageReceiversDialog` — ~160 LOC
- Settings adapters: `_setAutoAcceptFriends`, `_setAutoAcceptGroupInvites`,
  `_acceptFriendApplications` — ~80 LOC
- Utility: `_showSnackBar`, `_showErrorSnackBar`, `_updateTray`,
  `_loadBootstrapServiceStatus`, `_maybePrewarmCallPermissions`,
  `_refreshBootstrapOnResume`, `_loadLocalFriends`, `_load` — ~100 LOC
- Intent marker classes for keyboard shortcuts — ~20 LOC
- `_buildAddFriendButton`, `_onAddFriend` — ~70 LOC

Every private method closes over `_HomePageState` fields:
`_scaffoldMessengerContext`, `_index`, `_currentConversationID`,
`_messageWidgetKeys`, `_autoAcceptFriends`, `_pendingFriendApps`,
`_localFriends`, `_lanBootstrapServiceRunning`, `_inContactProfileContext`, etc.

None of these groups has a self-contained identity that survives extraction
without either making it a `part` (no testability gain) or passing large state
structs.

### `lib/util/prefs.dart` (1,982 LOC)

A flat static facade with ~120 get/set methods for SharedPreferences keys.
Already partially decomposed:

- `prefs/window_prefs.dart` — `_getWindowBoundsImpl`, `_setWindowBoundsImpl`,
  `_getWindowMaximizedImpl`, `_setWindowMaximizedImpl`
- `prefs/security_prefs.dart` — IRC config and app-installed getters/setters
- `prefs/account_prefs.dart` — `_getAccountListImpl`, `_setAccountListImpl`
- `prefs/chat_prefs.dart` — `_getLocalFriendsImpl`, `_setLocalFriendsImpl`
- `prefs/prefs_interfaces.dart` — Typed interfaces (`ICorePrefs`,
  `IFriendPrefs`, `IUIPrefs`, `INotificationPrefs`)
- `prefs/prefs_impl.dart` — `PrefsImpl` delegation class
- `prefs/scoped_key.dart` — `scopedPrefsKey()` helper (extracted from a prior
  X2 dedup fix)

The remaining body of `Prefs` in `prefs.dart` shares private static fields:
`_cachedPrefs`, `_cachedCurrentAccountToxId`, `_accountToxIdCached`,
`_secureStorage`, `_scopedKey()`. Every method in the class depends on at least
one of these. Splitting into independent non-`part` classes would require
exposing them or threading them through — breaking the facade contract that
~30+ call sites in the codebase depend on.

## Prior split history (the load-bearing fact)

Commit `86483f2` ("refactor: split home_page and settings_page into part
files") extracted:

- `lib/ui/home/home_page_controller.dart`
- `lib/ui/home/home_page_scope.dart`
- `lib/ui/home/home_page_view.dart`
- `lib/ui/home_page_persistence.dart`

Commit `973948d` ("refactor(home): responsive breakpoints by shortestSide +
HomePage cleanup") **deleted all four of those files** and collapsed them back
into `home_page.dart`. The system-prompt git status at session start confirms
those files are listed as `D` (deleted).

The split was undone because:

1. The `part`-based decomposition produced **no testability improvement** —
   every file was still `part of 'home_page.dart'` and so could not be unit
   tested in isolation.
2. The boundaries (controller / scope / view) were **not actually clean** —
   the "view" still had to call state-mutating methods that lived in the
   "controller", requiring cross-`part` access to `_HomePageState`'s
   protected internals. The seams leaked.
3. A responsive-breakpoints refactor that needed to touch the view layer
   surfaced the seam leakage as a maintenance pain, and a re-collapse was
   cheaper than fixing the boundaries.

## Why "split again" is the wrong move now

**`home_page.dart`:**

- Prior split was reverted for good structural reasons. No cleaner boundary
  has appeared in the meantime.
- The `part` pattern cannot produce testable modules — it's just file
  fragmentation, not decoupling.
- The business-logic refactors that would genuinely help
  (e.g. a `HomeGroupController`) require **semantic** understanding of the
  group-sync sequence, not mechanical splitting. `_handleGroupChanged` calls
  `UikitDataFacade.clearMessageList`,
  `UikitDataFacade.deleteGroupInfoFromJoinedGroupList`,
  `FakeChatDataProvider.unblockConversation`, and
  `FakeUIKit.instance.im?.refreshConversations()` in a carefully sequenced
  order. The `unblockConversation` call counteracts a side-effect of
  `deleteGroupInfoFromJoinedGroupList`; moving these out without preserving
  the sequence would silently break group sync.

**`prefs.dart`:**

- Already partially decomposed: interfaces, a delegation impl, multiple `part`
  implementation helpers.
- The remaining body is a **flat facade** that the rest of the codebase
  depends on at ~30+ call sites. Further `part` splitting just games the LOC
  counter.
- Independent class extraction (e.g. a `PasswordVerifier`) is viable but
  requires exposing private secure-storage helpers — making it a non-trivial
  API change for relatively little LOC reduction.

## What IS worth doing in a follow-up

These are **specific, low/medium-risk** extractions that would actually move
the needle. None of them are done in this pass.

### 1. Extract `_ToxeeMessageHeaderInfo` to its own file — ZERO RISK

- Location: `home_page_bootstrap.dart` lines 875–969
- Target: `lib/ui/home/toxee_message_header_info.dart`
- It is a self-contained `StatefulWidget` with **no `_HomePageState` closure**.
- ~100 LOC, becomes independently widget-testable.

### 2. Migrate `_handleGroupChanged` + `_loadPersistedGroupsIntoUIKit` to a `HomeGroupController` class — MEDIUM RISK

- ~230 LOC reduction in `home_page.dart`
- The group-sync logic becomes testable in isolation
- **Risk:** the call ordering in `_handleGroupChanged` is timing-sensitive
  (the `unblockConversation` after `deleteGroupInfoFromJoinedGroupList` is
  intentional). Any extraction must preserve that ordering or add a test
  that pins it down.
- Recommended only if a test for the group-sync invariant is written
  *before* the move, not after.

### 3. Extract password verifier from `prefs.dart` — LOW–MEDIUM RISK

- Location: lines 1785–1913 (PBKDF2 / SHA-256 password verification)
- Target: `lib/util/prefs/password_verifier.dart`
- ~130 LOC, no dependency on `_cachedPrefs` / `_cachedCurrentAccountToxId`
- Uses `_secureRead` / `_secureWrite` / `_secureDelete` and `_kPbkdf2Prefix`
- **Cost:** must expose secure-storage helpers (either make them `internal`
  to a `prefs/` library, or pass an injected `FlutterSecureStorage`).
- **Benefit:** password hashing logic becomes testable without
  SharedPreferences, which is what you actually want when verifying PBKDF2
  iterations, salt handling, and the `$pbkdf2-sha256$` prefix protocol.

## Bottom line

> Splitting for the sake of the complexity warning is a known anti-pattern in
> this repo — it was tried, reverted, and the reversion was the right call.
> The 500-LOC threshold is a warning, not a gate; the right response to two
> 2000-LOC files is **targeted extraction of independently-testable units**,
> not a mechanical split into part files.

If the user wants the LOC count down, do items 1 + 3 above (zero / low-risk,
testability win). Defer item 2 (`HomeGroupController`) until there's a
dedicated test for the group-sync ordering. Do not do another
`controller/scope/view` part split — that path is closed.

## 2026-05-20 Follow-up — items 1, 2, 3 landed

All three recommended extractions were implemented the same day:

### Item 1 — `_ToxeeMessageHeaderInfo` → `lib/ui/home/toxee_message_header_info.dart`
- `home_page_bootstrap.dart`: 969 → 873 LOC (−96).
- New widget file: 110 LOC, public `ToxeeMessageHeaderInfo` class.
- Tests: `test/ui/home/toxee_message_header_info_test.dart` — 6 widget tests
  (C2C online/offline, `showUserOnlineStatus: false` hides status row,
  conversation-null name fallback, group with ≥3 members renders subtitle,
  group with ≤2 members hides status row).

### Item 2 — `HomeGroupController` → `lib/ui/home/home_group_controller.dart`
- `home_page.dart`: 1995 → 1809 LOC (−186).
- New controller file: 281 LOC.
- Followed the **"test first"** guardrail. The ordering test
  (`test/ui/home/home_group_controller_ordering_test.dart`, 9 tests) was
  written and validated against the standalone controller BEFORE wiring it
  into `_HomePageState`, then re-run after wiring to confirm the invariant
  held through the extraction.
- `GroupSyncOps` struct injects every UIKit/service callback so the
  controller is testable without UIKit singletons. `GroupSyncOps.real(...)`
  is the production wiring; `_HomePageState.initState()` constructs the
  controller with it.
- Pinned invariants: full 4-step ordering
  (`clearMessageList → deleteGroupInfoFromJoinedGroupList → unblockConversation
  → refreshConversations`), `group_` prefix on `unblockConversation`, each
  op called exactly once, displayName persistence via `Prefs`,
  `loadPersistedGroupsIntoUIKit` end-to-end smoke.

### Item 3 — `PasswordVerifier` → `lib/util/prefs/password_verifier.dart`
- `prefs.dart`: 1981 → 1811 LOC (−170, vs the ~130 estimate).
- New file: 363 LOC. Injects `FlutterSecureStorage` + `LegacyPasswordStore`
  for testability (instead of exposing the private `_secureRead/Write/Delete`
  helpers).
- Tests: 18 unit tests covering round-trip, wire format (pbkdf2: prefix /
  150k iters / 256 bits / SHA-256 / 32 B salt), legacy SHA-256 migration
  (salted + unsalted), constant-time comparison, and `MissingPluginException`
  graceful swallow.

### Net effect
- `home_page.dart`: 1995 → 1809 LOC (−186)
- `home_page_bootstrap.dart`: 969 → 873 LOC (−96)
- `prefs.dart`: 1981 → 1811 LOC (−170)
- Combined: **−452 LOC** out of the two flagship files (plus their
  part-file), all of which now have dedicated unit/widget tests pinning
  their non-trivial behavior.

The "do not split for the sake of splitting" recommendation stands for
anything beyond these three carved-out responsibilities. Any future
extraction should likewise lead with the test, not the rearrangement.
