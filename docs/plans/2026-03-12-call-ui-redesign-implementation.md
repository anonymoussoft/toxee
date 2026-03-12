# Call UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the full call experience so in-call, incoming, outgoing, and floating windows share a restrained business-dark visual language without changing call behavior.

**Architecture:** Introduce a small shared call-presentation layer in `lib/call/` for surfaces, top status chrome, action docks, compact cards, and layout tokens. Rebuild `InCallView`, `IncomingCallView`, `OutgoingCallView`, and `CallFloatingWidget` on top of those primitives while keeping `CallStateNotifier`, `CallServiceManager`, and `CallOverlay` semantics intact.

**Tech Stack:** Flutter, Material, existing `CallStateNotifier`, existing `CallServiceManager`, existing `VideoHandler`, `flutter_test`

---

> **Implementation note:** `toxee` has no commits yet, so `git worktree` cannot be used safely. Execute this plan in the current workspace and avoid touching unrelated staged changes.

## Document Purpose

This document is intentionally more detailed than a normal task list. It is meant to answer three questions before any implementation begins:

1. What exactly should change in the call UI
2. Which files should own the new behavior and styling
3. How to verify that the redesign is visual-only and does not break call behavior

This plan is for documentation and execution guidance only. It does not authorize implementation in this turn.

## Current State Snapshot

The current call experience is functionally complete but visually fragmented:

- [in_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/in_call_view.dart#L11) uses a dark gradient, a large freeform remote-video stack, a prominent top-right minimize button, and a bottom action row with translucent video-only styling.
- [incoming_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/incoming_call_view.dart#L10) uses pulse-ring avatar animation and a layout that feels separate from the in-call screen.
- [outgoing_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/outgoing_call_view.dart#L10) mirrors incoming style but introduces another layout rhythm and separate visual hierarchy.
- [call_floating_widget.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_floating_widget.dart#L9) uses a pill layout that does not match the fullscreen surfaces.
- [call_overlay.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_overlay.dart#L11) already orchestrates state transitions cleanly, so it should remain mostly unchanged except for stable keys and transition timing.
- [call_state_notifier.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_state_notifier.dart#L8) exposes a simple state machine:
  - `idle`
  - `ringing`
  - `inCall`
  - `ended`
  - plus `minimized`, `mode`, `direction`, and duration tracking

The redesign should preserve this state model and only change how those states are presented.

## Product Direction

The approved design direction is:

- Visual style: business-dark
- Interaction style: balanced between meeting tool and phone call
- Scope: redesign the full call window set
  - incoming call
  - outgoing call
  - in-call
  - floating minimized window

The target feeling is:

- clean
- restrained
- professional
- consistent across mobile and desktop
- lower animation noise than the current pulse-heavy implementation

The target feeling is not:

- playful
- “consumer social app”
- overly glassy
- visually loud
- conference-dashboard heavy

## Design Goals

### Primary Goals

- Create one coherent visual language across all call states.
- Reduce gratuitous glow, gradient, and pulse effects.
- Prioritize remote video during active video calls.
- Keep action controls obvious without making the UI feel cluttered.
- Ensure minimized and fullscreen states feel like the same product.

### Secondary Goals

- Improve scanability on desktop screens without diverging from mobile.
- Make audio-only and video-call layouts feel related instead of separately designed.
- Give tests stable structural hooks using `ValueKey`s instead of brittle tree assumptions.

### Non-Goals

- Do not change signaling, audio, camera, or duration logic.
- Do not add new call features such as screen sharing, participant grids, full network quality stats dashboard, or chat-in-call. A single in-call quality indicator (text/icon in the top bar only) is allowed.
- Do not change `CallStateNotifier` semantics unless a testability issue makes a small additive change unavoidable.
- Do not redesign unrelated chat or profile screens.

## Internationalization

- **Rule:** All user-visible strings in call UI must come from `AppLocalizations.of(context)`; no hardcoded English or other language strings in call widgets.
- **Existing keys:** The app already has call-related keys in [lib/l10n/app_en.arb](toxee/lib/l10n/app_en.arb) (e.g. `callMute`, `callMinimize`, `callCalling`, `callVideoCall`, `callAudioCall`, etc.). Reuse these where they exist.
- **New keys to add** (in all locale ARB files: app_en.arb, app_zh.arb, app_zh_Hans.arb, app_zh_Hant.arb, app_ar.arb, app_ja.arb, app_ko.arb):
  - `callQualityGood` — e.g. "Good connection"
  - `callQualityMedium` — e.g. "Fair connection"
  - `callQualityPoor` — e.g. "Poor connection"
  - `callQualityUnknown` — e.g. "—" or "Checking…" (or omit label when unknown)
  - `callQualityLabel` — optional accessibility/semantic label for the quality indicator, e.g. "Call quality"
- **Process:** For each task that introduces or touches call UI text, define or reuse keys in the template ARB first, run `flutter gen-l10n`, then use the generated getters in code. No new i18n mechanism; use the existing [lib/i18n/app_localizations.dart](toxee/lib/i18n/app_localizations.dart) and delegates.

## Responsive and Platform Adaptation

- **Reference:** Use the existing [lib/util/responsive_layout.dart](toxee/lib/util/responsive_layout.dart): breakpoints `mobileBreakpoint = 600`, `tabletBreakpoint = 1024`; helpers `isMobile`, `isTablet`, `isDesktop`, `responsiveValue`, `responsivePadding`, `responsiveHorizontalPadding`, `responsiveFontSize`, etc.
- **Shell and components:**
  - `CallSceneShell`: Use `MediaQuery.sizeOf(context)` and `ResponsiveLayout.responsiveValue` for top bar height (e.g. mobile 56, tablet 64, desktop 72), horizontal/vertical padding, and bottom dock offset from safe area.
  - `CallTopStatusBar` / `CallActionDock`: Use `ResponsiveLayout.responsiveFontSize(context)` for text scale where appropriate; keep a single layout structure, only adjust spacing and size.
- **Layout behavior (concise):**
  - **Mobile portrait:** Main stage dominates; top bar one row; dock single row above bottom safe area; local preview inside stage (e.g. top-right).
  - **Mobile landscape:** Same shell; dock and preview remain accessible; preview does not cover primary controls.
  - **Tablet / desktop:** Same shell and components; larger margins and padding via `responsiveValue`; no separate "conference" layout.
- **Android / iOS:** Rely on Flutter `SafeArea` (already used in current [in_call_view.dart](toxee/lib/call/in_call_view.dart) and others). Ensure the new shell and all call views are built inside `SafeArea` so notch and system UI are respected. No platform-specific layout branches; one layout works on both.

## High-Level UI Strategy

The redesign should use one shared shell and a small set of reusable call-specific primitives.

### Shared Structural Pattern

All four call surfaces should follow the same broad structure:

1. Background surface
2. Top status bar
3. Main content stage
4. Bottom action area or action strip
5. Optional secondary card layer

This makes the experience feel continuous when the user moves between:

- ringing
- active call
- minimized
- restored

### Shared Shell Responsibilities

The new shared shell should own:

- page background color and surface tone
- safe-area padding
- top status bar placement
- bottom dock placement
- desktop/mobile spacing behavior
- structural layering for video stage and compact overlays

Individual views should only decide:

- what title and subtitle to show
- which actions to expose
- whether the main stage is avatar-based or video-based
- whether a local preview card or compact thumbnail is needed

## Visual Specification

### Color System

Keep the palette small and consistent:

- Background base: near-black graphite
- Secondary surface: slightly lifted charcoal panel
- Border: low-contrast cool gray
- Primary text: soft white, not pure white
- Secondary text: muted gray-blue
- Accent: subtle steel blue only where a neutral highlight is needed
- Accept action: restrained green
- Destructive action: controlled red

Avoid:

- large vivid gradients
- neon blues
- bright glow halos
- purple tint

### Surface Treatment

Use flat or nearly flat dark surfaces with very light elevation:

- large panels: solid dark fill with 1px low-contrast border
- docks: dark elevated capsule or rounded rectangle
- preview cards: precise radius, thin border, small shadow
- floating window: compact elevated card instead of pill-only aesthetic

Backdrop blur is allowed only if it materially improves contrast, and should be used sparingly.

### Typography

Hierarchy should be simple:

- Name/title: medium weight
- Status/duration: regular weight, smaller, tabular digits where useful
- Action labels: short, minimal, secondary emphasis

Avoid:

- oversized titles
- decorative letter spacing
- dense labels beneath every control if icons already communicate enough

### Motion

Motion should be restrained:

- incoming/outgoing: subtle fade and scale, not dominant pulse rings
- state switches: short cross-fade or fade-through
- dock appearance: light vertical fade/slide if needed
- minimized card restore: no dramatic spring animation

Remove or greatly reduce:

- layered pulse circles around avatars
- large breathing effects
- aggressive glow blooms

## Screen-by-Screen Spec

### 1. In-Call Video Screen

#### Layout Intent

The active video call screen should prioritize the remote feed and de-emphasize chrome.

#### Top Region

Replace the isolated top-right minimize icon treatment with a thin top status bar containing:

- remote avatar or small presence marker
- remote name
- duration
- call mode label when useful
- **Call quality indicator** (when available): compact label and/or icon in the top bar (e.g. right of duration, left of minimize), showing good / fair / poor / unknown. Use `AppLocalizations` for labels (e.g. `callQualityGood`). When quality is unknown, show placeholder or hide the indicator. No extra row; keep one thin top bar.
- trailing minimize action

This bar should read as part of the shell rather than an icon floating over content.

#### Main Stage

For video calls:

- remote video occupies the main stage
- remote video should fill available space as cleanly as possible
- fallback state should show a calm placeholder rather than plain text on a raw black slab
- placeholder should still feel designed, e.g. muted identity card plus “remote video unavailable” text

#### Local Preview

The self-preview should become a deliberate card:

- stable aspect ratio
- consistent corner radius
- subtle border
- light shadow
- predictable placement

Default placement:

- portrait: upper-right inside the stage
- landscape: upper-right or right-side anchored, depending on overlap pressure

The preview card should not visually overpower the remote feed.

#### Bottom Dock

The dock should be one unified component:

- mute
- toggle video
- speaker if supported
- hang up

Dock behavior:

- centered
- floating slightly above bottom safe area
- same shape across phone and desktop
- labels may be shown, but should remain compact
- destructive action visually separated via color, not size explosion

#### Audio-Only Variant

When `CallMode.audio` is active:

- replace remote video stage with a centered identity stage
- keep top status bar and bottom dock unchanged
- maintain layout rhythm so switching from video to audio does not feel like entering a different product

### 2. Incoming Call Screen

#### Layout Intent

Incoming call should feel immediate and calm, not animated for spectacle.

#### Top Region

Top status bar should contain:

- call type
- source identity
- trailing minimize action only if minimizing incoming calls remains supported by product behavior

#### Main Stage

Use a centered identity card:

- avatar
- remote name
- short subtitle such as “Video call” or “Audio call”

Do not use the current expanding pulse-ring motif.

Allowed motion:

- soft fade-in of the card
- optional tiny breathing scale on the avatar card, if subtle

#### Action Area

Action area should contain exactly two primary choices:

- reject
- accept

If video/audio distinction matters at this state, it should be shown in subtitle text rather than adding more buttons.

Layout rules:

- portrait: bottom horizontal strip
- landscape: still visually aligned with the same strip logic, not a completely different composition

### 3. Outgoing Call Screen

#### Layout Intent

Outgoing call is the same shell as incoming, but with a single-call-progress action pattern.

#### Main Stage

Centered identity card:

- avatar
- remote name
- status text such as “Calling…”
- optional call-type subtitle

Animation should be lighter than the current pulse treatment.

#### Action Area

One destructive primary action:

- cancel / hang up

The page should visually resemble incoming screen enough that users understand they are in the same flow.

### 4. Floating Minimized Window

#### Layout Intent

The floating window should feel like a compact continuation of fullscreen, not a separate utility bubble.

#### Behavior

Preserve current behavior:

- draggable
- tap to restore
- explicit hang-up affordance

#### Visual Form

Convert the pill into a compact business-dark card:

- fixed height band with cleaner padding
- better separation between identity section and hang-up action
- optional thumbnail area for video calls
- avatar-only compact mode for audio calls

#### Content Rules

Always show:

- remote name
- duration or “Calling…”

Optional: small quality icon next to duration when in-call and quality is available; use same semantics as top bar.

Video minimized mode may additionally show:

- remote video thumbnail if easily available
- otherwise a styled placeholder block

#### Drag Rules

Retain boundary clamping and saved position behavior from the current widget.

## Shared Component Design

Introduce a thin set of call-only primitives. Do not create a large design system.

### Proposed New Files

- `lib/call/call_ui_shell.dart`
  - shared page shell
  - shared spacing tokens
  - shared dark surface constants
- `lib/call/call_ui_components.dart`
  - top status bar
  - action dock
  - compact call card
  - identity stage
  - video stage wrapper

If the implementation becomes too dense, a third file is acceptable:

- `lib/call/call_ui_tokens.dart`

Only create this if `call_ui_shell.dart` becomes overloaded.

### Component Inventory

`CallSceneShell`

- owns overall dark surface and safe area
- accepts `topBar`, `child`, and `bottomBar`
- supports fullscreen and compact modes

`CallTopStatusBar`

- title
- subtitle
- optional leading avatar/icon
- optional **qualityIndicator** slot (e.g. `Widget?` or a small `CallQuality` enum-driven widget) so the in-call view can inject the quality widget
- optional trailing action
- stable key: `call-top-bar`

`CallActionDock`

- receives action descriptors
- handles layout for 1, 2, or 4 actions
- stable key: `call-action-dock`

`CallDockAction`

- icon
- label
- `destructive`
- `selected`
- `enabled`
- callback

`CallIdentityStage`

- avatar
- title
- subtitle
- optional secondary note

`CallVideoStage`

- remote content area
- optional local preview card
- stable key for preview: `call-local-preview-card`

`CallCompactCard`

- used by floating widget
- title
- subtitle
- optional thumbnail/avatar slot
- optional **quality** indicator: small icon or dot for in-call quality when minimized (v1 can omit if scope is tight)
- hang-up action
- stable key: `floating-call-card`

## File-by-File Change Plan

**L10n and codegen:** Implementation steps that add or use new call UI strings must: add the key to the template ARB (and other locale ARBs), run `flutter gen-l10n`, and use the generated getters. Reuse existing `call*` keys where they exist.

### [call_state_notifier.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_state_notifier.dart#L8)

- **Additive, optional change only:** A getter for call quality (e.g. `CallQuality get callQuality`) that defaults to `unknown` and does not alter existing state or transitions. No other semantics changes.

### [in_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/in_call_view.dart#L11)

Current responsibilities:

- layout math
- background rendering
- top chrome
- remote video stack
- preview placement
- dock layout
- button visuals

Target responsibilities after redesign:

- map `CallStateNotifier` and `CallServiceManager` to shared shell primitives
- define which actions appear
- define how remote and local video are plugged into the shared stage

Responsibilities to move out:

- raw color styling
- button surface styling
- generic top bar rendering
- generic dock rendering

### [incoming_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/incoming_call_view.dart#L10)

Current responsibilities:

- pulse animation
- custom portrait layout
- custom landscape layout
- direct button rendering

Target responsibilities after redesign:

- provide content and actions to the shared shell
- keep only the minimum state-specific logic

### [outgoing_call_view.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/outgoing_call_view.dart#L10)

Same refactor shape as incoming call.

### [call_floating_widget.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_floating_widget.dart#L9)

Preserve:

- drag logic
- position clamping
- restore behavior
- hang-up action

Refactor:

- visual structure
- compact thumbnail/identity treatment
- spacing and shape

### [call_overlay.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/call_overlay.dart#L11)

Keep behavior intact.

Possible small changes only:

- reduce debug `print` noise if it interferes with tests
- expose more stable `ValueKey`s through child views
- adjust `AnimatedSwitcher` timing to fit the redesigned transitions

### [video_handler.dart](/Users/bin.gao/chat-uikit/toxee/lib/call/video_handler.dart#L1)

No behavioral changes expected.

The redesign may rely on existing:

- `remoteImage`
- `localPreview`
- `isLocalPreviewReady`

Do not rewrite video processing unless the UI redesign uncovers a layout-only helper need.

## State Mapping Specification

The redesign must preserve the current state machine:

### `CallUIState.idle`

- overlay hidden
- child app fully interactive

### `CallUIState.ringing`

- incoming: show redesigned incoming screen
- outgoing: show redesigned outgoing screen
- minimized: show redesigned floating card

### `CallUIState.inCall`

- audio mode: identity stage + dock
- video mode: remote video stage + local preview + dock
- minimized: show redesigned floating card

### `CallUIState.ended`

- keep existing temporary ended treatment unless redesign explicitly folds it into the shell
- if changed, ensure auto-reset timing remains identical

### Additional Flags

`isMinimized`

- only changes presentation
- must not alter action availability

`isMuted`

- only changes dock button selected state and icon

`isVideoEnabled`

- changes dock button selected state
- may also affect local preview visibility styling, but must not destroy the preview container unexpectedly

`isSpeakerOn`

- only visible when `CallMediaCapabilities.supportsSpeakerToggle()` returns true

### Call quality (data abstraction)

- Introduce a **read-only** quality representation (e.g. enum `CallQuality { good, medium, poor, unknown }` or an int level) and a getter on `CallStateNotifier` (e.g. `CallQuality get callQuality => ...`) so the UI can bind to it without changing the core state machine.
- Initial implementation may always return `unknown`; the top bar then shows the unknown state or hides the indicator. When backend/AV layer provides metrics later, wire them into this getter (or a separate notifier) and the existing UI will show good/medium/poor without further layout changes.

## Responsive Rules

The redesign should remain visually unified across device classes.

### Mobile Portrait

- remote video dominates height
- top bar remains compact
- dock floats just above bottom safe area
- preview card anchored inside stage

### Mobile Landscape

- remote video still dominates
- dock may narrow and wrap less aggressively
- preview card must not block critical controls

### Desktop / Tablet

- preserve the same shell, but allow more breathing room
- do not invent a totally separate split-screen layout unless clearly necessary
- use larger margins, not different visual language

## Accessibility and Usability Requirements

- All action buttons remain reachable with one tap/click.
- Maintain semantic labels on call actions.
- Preserve sufficient contrast on dark surfaces.
- Duration text should continue to use tabular figures where shown.
- Do not make essential actions icon-only without accessibility labels.

## Testing Strategy

The redesign needs more widget-level coverage than the code currently has.

### Existing Relevant Tests

- [call_and_history_regression_test.dart](/Users/bin.gao/chat-uikit/toxee/test/call_and_history_regression_test.dart#L1)
- [widget_test.dart](/Users/bin.gao/chat-uikit/toxee/test/widget_test.dart#L1)

### New Tests to Add

- `test/call_ui_shell_test.dart`
  - shell renders top bar and dock
- `test/call_in_call_view_test.dart`
  - video call layout exposes top bar, preview card, dock
  - audio call layout exposes identity stage and dock
- `test/call_ring_screens_test.dart`
  - incoming screen has two actions
  - outgoing screen has one destructive action
- `test/call_floating_widget_test.dart`
  - minimized card renders and supports restore affordance

### Existing Test to Extend

- `test/call_and_history_regression_test.dart`
  - add overlay-level transition assertions for redesigned keys

### Preferred Testing Style

- Assert structural keys and essential text, not pixel values.
- Avoid brittle subtree shape assertions.
- Test behavior-level outcomes:
  - dock exists
  - destructive action exists
  - minimized card exists
  - top bar exists

## Detailed Task Breakdown

### Task 1: Shared Call Shell

**Files:**
- Create: `lib/call/call_ui_shell.dart`
- Create: `lib/call/call_ui_components.dart`
- Test: `test/call_ui_shell_test.dart`

**Intent:**

Build the presentation primitives first so later screen rewrites only compose them.

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_ui_shell.dart';
import 'package:toxee/call/call_ui_components.dart';

void main() {
  testWidgets('renders a compact business-dark call shell with top bar and dock',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CallSceneShell(
          child: SizedBox.expand(),
          topBar: CallTopStatusBar(
            key: ValueKey('call-top-bar'),
            title: 'Alice',
            subtitle: '00:32',
            trailingIcon: Icons.picture_in_picture_alt,
          ),
          bottomBar: CallActionDock(
            key: ValueKey('call-action-dock'),
            actions: [
              CallDockAction(icon: Icons.mic, label: 'Mute'),
              CallDockAction(icon: Icons.call_end, label: 'Hang up', destructive: true),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/call_ui_shell_test.dart`

Expected: FAIL with undefined shell components.

**Step 3: Write minimal implementation**

Implementation requirements:

- `CallSceneShell` owns background and slot placement
- `CallTopStatusBar` renders title, subtitle, optional trailing action
- `CallActionDock` renders action descriptors consistently
- no per-screen business logic inside these shared components
- Use `ResponsiveLayout` for shell, top bar, and dock sizing and padding
- Ensure any text in the shell components uses `AppLocalizations`
- Add the new quality-related ARB keys (callQualityGood, callQualityMedium, callQualityPoor, callQualityUnknown, callQualityLabel) and run `flutter gen-l10n` so Task 2 can use them

**Step 4: Run test to verify it passes**

Run: `flutter test test/call_ui_shell_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/call/call_ui_shell.dart lib/call/call_ui_components.dart test/call_ui_shell_test.dart
git commit -m "feat: add shared call scene shell"
```

### Task 2: Rebuild In-Call View

**Files:**
- Modify: `lib/call/in_call_view.dart:1-999`
- Modify: `lib/call/call_ui_shell.dart`
- Modify: `lib/call/call_ui_components.dart`
- Test: `test/call_in_call_view_test.dart`

**Intent:**

Make `InCallView` the canonical fullscreen screen and prove the shared shell is viable.

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/in_call_view.dart';

void main() {
  testWidgets('video in-call view shows top status bar, local preview card, and dock',
      (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.outgoing,
        inviteID: 'invite-1',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      )
      ..enterCall();

    await tester.pumpWidget(buildInCallTestApp(callState));

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-local-preview-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/call_in_call_view_test.dart`

Expected: FAIL because the current view does not expose the new structure.

**Step 3: Write minimal implementation**

Implementation requirements:

- replace bespoke gradient shell with shared shell
- move top chrome into `CallTopStatusBar`
- move action row into `CallActionDock`
- wrap remote video in a reusable stage widget
- show stable local preview card with key `call-local-preview-card`
- preserve existing behavior for:
  - mute
  - toggle video
  - speaker when supported
  - hang up
  - minimize
- Build the quality indicator widget from `callState.callQuality` (or equivalent) and pass it into `CallTopStatusBar`
- All button and status labels via l10n

**Step 4: Run test to verify it passes**

Run: `flutter test test/call_in_call_view_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/call/in_call_view.dart lib/call/call_ui_shell.dart lib/call/call_ui_components.dart test/call_in_call_view_test.dart
git commit -m "feat: redesign in-call video surface"
```

### Task 3: Rebuild Incoming and Outgoing Screens

**Files:**
- Modify: `lib/call/incoming_call_view.dart:1-999`
- Modify: `lib/call/outgoing_call_view.dart:1-999`
- Modify: `lib/call/call_ui_shell.dart`
- Modify: `lib/call/call_ui_components.dart`
- Test: `test/call_ring_screens_test.dart`

**Intent:**

Unify ringing-state screens so they feel like state variants, not separate products.

**Step 1: Write the failing test**

```dart
void main() {
  testWidgets('incoming screen uses shared shell with two primary actions', (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.incoming,
        inviteID: 'invite-2',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      );

    await tester.pumpWidget(buildIncomingCallTestApp(callState));

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('incoming-call-actions')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('outgoing screen uses shared shell with one destructive action', (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'invite-3',
        remoteUserID: 'bob',
        remoteNickname: 'Bob',
      );

    await tester.pumpWidget(buildOutgoingCallTestApp(callState));

    expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('outgoing-call-actions')), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/call_ring_screens_test.dart`

Expected: FAIL because current ringing screens use bespoke pulse layouts.

**Step 3: Write minimal implementation**

Implementation requirements:

- incoming and outgoing use `CallSceneShell`
- both use the same identity stage
- incoming exposes two actions: reject / accept
- outgoing exposes one destructive action: cancel
- heavy pulse-ring animation is removed or reduced to subtle motion
- No quality display on ringing screens; keep using l10n for "Video call" / "Audio call" and all buttons (existing keys)

**Step 4: Run test to verify it passes**

Run: `flutter test test/call_ring_screens_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/call/incoming_call_view.dart lib/call/outgoing_call_view.dart lib/call/call_ui_shell.dart lib/call/call_ui_components.dart test/call_ring_screens_test.dart
git commit -m "feat: unify ringing call screens"
```

### Task 4: Rebuild Floating Widget

**Files:**
- Modify: `lib/call/call_floating_widget.dart:1-999`
- Modify: `lib/call/call_ui_components.dart`
- Test: `test/call_floating_widget_test.dart`

**Intent:**

Make the minimized window feel visually related to fullscreen while preserving drag/restore behavior.

**Step 1: Write the failing test**

```dart
void main() {
  testWidgets('floating widget shows shared compact card and restore affordance',
      (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.outgoing,
        inviteID: 'invite-4',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      )
      ..enterCall()
      ..minimize();

    await tester.pumpWidget(buildFloatingCallTestApp(callState));

    expect(find.byKey(const ValueKey('floating-call-card')), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/call_floating_widget_test.dart`

Expected: FAIL because the current floating widget does not use the compact card structure.

**Step 3: Write minimal implementation**

Implementation requirements:

- preserve drag logic and saved position
- wrap visuals in shared compact card
- show remote name and status/duration
- support video-thumbnail-like slot for video mode when available
- keep restore-on-tap and explicit hang-up affordance
- Optional: small quality icon in the compact card when in-call and quality is available; use l10n for any new tooltip/label

**Step 4: Run test to verify it passes**

Run: `flutter test test/call_floating_widget_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/call/call_floating_widget.dart lib/call/call_ui_components.dart test/call_floating_widget_test.dart
git commit -m "feat: redesign floating call card"
```

### Task 5: Overlay and Regression Verification

**Files:**
- Modify: `lib/call/call_overlay.dart:1-999`
- Modify: `test/call_and_history_regression_test.dart`
- Test: `test/call_and_history_regression_test.dart`
- Test: `test/call_ui_shell_test.dart`
- Test: `test/call_in_call_view_test.dart`
- Test: `test/call_ring_screens_test.dart`
- Test: `test/call_floating_widget_test.dart`

**Intent:**

Verify the redesign integrates cleanly with overlay transitions and does not regress existing call utilities.

**Step 1: Write the failing regression test**

```dart
testWidgets('call overlay switches between full-screen and floating redesigned surfaces',
    (tester) async {
  final callState = CallStateNotifier()
    ..startRinging(
      mode: CallMode.video,
      direction: CallDirection.outgoing,
      inviteID: 'invite-5',
      remoteUserID: 'alice',
      remoteNickname: 'Alice',
    )
    ..enterCall();

  await tester.pumpWidget(buildCallOverlayTestApp(callState));
  expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);

  callState.minimize();
  await tester.pump();
  expect(find.byKey(const ValueKey('floating-call-card')), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/call_and_history_regression_test.dart`

Expected: FAIL because redesigned keys are not yet present in overlay-level tests.

**Step 3: Write minimal implementation**

Implementation requirements:

- keep the overlay state routing unchanged
- ensure redesigned views expose stable keys used by tests
- only adjust transition timing if necessary for smoother visual handoff
- When writing overlay tests that depend on text (e.g. quality labels), use `find.text(AppLocalizations.of(context)!.callQualityGood)` or the appropriate key so tests are locale-safe; for responsive behavior, assert only that key structure (top bar, dock, floating card) is present, not pixel dimensions

**Step 4: Run test to verify it passes**

Run: `flutter test test/call_ui_shell_test.dart test/call_in_call_view_test.dart test/call_ring_screens_test.dart test/call_floating_widget_test.dart test/call_and_history_regression_test.dart`

Expected: PASS with all new widget tests and existing call regressions green.

**Step 5: Commit**

```bash
git add lib/call/call_overlay.dart test/call_and_history_regression_test.dart test/call_ui_shell_test.dart test/call_in_call_view_test.dart test/call_ring_screens_test.dart test/call_floating_widget_test.dart
git commit -m "feat: finalize unified call ui redesign"
```

## Risks and Mitigations

### Risk: Visual refactor accidentally changes call behavior

Mitigation:

- keep `CallStateNotifier` unchanged
- keep `CallServiceManager` unchanged
- treat layout as a pure presentation concern
- test dock presence and transition states explicitly

### Risk: Video preview layering becomes unstable

Mitigation:

- keep remote and local preview rendering logic in `InCallView`
- only wrap them with new surface widgets
- avoid rewriting `VideoHandler`

### Risk: Desktop and mobile diverge too much

Mitigation:

- enforce one shell
- vary only spacing and scale, not structure

### Risk: Floating window redesign breaks drag or restore

Mitigation:

- preserve current position update flow
- only replace the child surface

## Verification Checklist

- [ ] `CallSceneShell` exists and owns common dark surface behavior
- [ ] `InCallView` uses shared top bar and action dock
- [ ] local preview card has stable structure and does not dominate the remote stage
- [ ] `IncomingCallView` and `OutgoingCallView` use the same visual shell
- [ ] `CallFloatingWidget` visually matches the fullscreen redesign
- [ ] minimized and restored states still map correctly through `CallOverlay`
- [ ] `flutter test test/call_ui_shell_test.dart test/call_in_call_view_test.dart test/call_ring_screens_test.dart test/call_floating_widget_test.dart test/call_and_history_regression_test.dart` passes
- [ ] All call UI strings are sourced from `AppLocalizations`; no hardcoded user-visible strings in call views or shared call components
- [ ] Shell and call views use `ResponsiveLayout` (or equivalent) for mobile/tablet/desktop sizing and padding; layout is tested on a narrow (phone) and wide (tablet/desktop) size
- [ ] In-call screen shows the quality indicator in the top bar when quality is not unknown; when unknown, indicator is hidden or shows the unknown placeholder
- [ ] `CallStateNotifier` has at most an additive quality getter; core state machine and transitions are unchanged

## Execution Notes

- Start with Task 1 and do not skip the shared shell.
- Do not redesign screens one by one without extracting shared primitives first.
- If the shell becomes too generic, stop and split tokens from components, but do not build a large framework.
- If tests become hard to write, expose stable `ValueKey`s rather than weakening assertions.

## Deliverable Summary

After implementation, the expected outcome is:

- one visually unified call system
- lower animation noise
- stronger fullscreen/minimized continuity
- improved test coverage for call presentation states
- no changes to call signaling or media behavior
