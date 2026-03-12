# In-App Call Reliability Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the remaining reliability optimizations for in-app calling without adding system call UI integration.

**Architecture:** Keep the current app-level call stack, but move remaining side effects into explicit helpers: permission preflight before signaling invite, structured permission outcomes for better UX, and a dedicated call effects listener for screen wakelock and transient notices.

**Tech Stack:** Flutter, Dart, `permission_handler`, `wakelock_plus`, `tim2tox_dart`, Flutter widget tests

---

### Task 1: Add failing tests for outgoing permission preflight and call wake policy

**Files:**
- Modify: `test/call_bridge_service_test.dart`
- Create: `test/call_effects_policy_test.dart`

**Step 1: Write the failing tests**

- Verify `TUICallKitAdapter.handleCall()` aborts before signaling when a preflight callback denies the call.
- Verify wake policy keeps the screen awake for `ringing` and `inCall`, but not for `idle` or `ended`.

**Step 2: Run tests to verify they fail**

Run: `flutter test test/call_bridge_service_test.dart test/call_effects_policy_test.dart`

**Step 3: Implement the minimal code**

- Add a preflight callback to `TUICallKitAdapter`.
- Add a simple wake policy helper.

**Step 4: Run tests to verify they pass**

Run: `flutter test test/call_bridge_service_test.dart test/call_effects_policy_test.dart`

### Task 2: Add structured permission results and notice plumbing

**Files:**
- Modify: `lib/call/permission_helper.dart`
- Modify: `lib/call/call_service_manager.dart`
- Create: `lib/call/call_ui_notice.dart`

**Step 1: Write the failing tests**

- Verify permission helper can describe denied outcomes with and without “open settings”.

**Step 2: Run tests to verify they fail**

Run: `flutter test test/call_and_history_regression_test.dart`

**Step 3: Implement the minimal code**

- Return a structured permission result instead of a raw bool for UI-facing paths.
- Emit call notices from the manager when permission failures block the action.

**Step 4: Run tests to verify they pass**

Run: `flutter test test/call_and_history_regression_test.dart`

### Task 3: Add a single call effects listener for wakelock and notices

**Files:**
- Create: `lib/call/call_effects_listener.dart`
- Modify: `lib/main.dart`
- Modify: `lib/ui/widgets/app_snackbar.dart`
- Modify: `pubspec.yaml`

**Step 1: Write the failing test**

- Verify the effect controller computes the correct wakelock state.

**Step 2: Run the test to verify it fails**

Run: `flutter test test/call_effects_policy_test.dart`

**Step 3: Implement the minimal code**

- Add `wakelock_plus`.
- Toggle wakelock from a listener instead of widget build code.
- Show a single floating snackbar for call notices, with a Settings action when appropriate.

**Step 4: Run focused verification**

Run: `flutter test test/call_bridge_service_test.dart test/call_effects_policy_test.dart test/call_and_history_regression_test.dart test/user_profile_call_actions_test.dart test/message_header_actions_test.dart`
