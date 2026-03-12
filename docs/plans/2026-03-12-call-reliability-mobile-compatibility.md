# Call Reliability And Mobile Compatibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the known audio/video call reliability issues in `toxee`, especially on phones and tablets, and make unsupported call flows fail safely instead of behaving incorrectly.

**Architecture:** Keep the existing app-level calling model, but harden the signaling state machine, normalize captured media before it reaches ToxAV, and gate unsupported UX paths. Avoid adding half-finished platform-native call stacks in this change; instead, make current mobile behavior predictable and explicit.

**Tech Stack:** Flutter, Dart, `camera`, `record`, `permission_handler`, `tim2tox_dart`, Tencent Cloud Chat UIKit

---

### Task 1: Add regression tests for call-state and media normalization helpers

**Files:**
- Create: `test/call_service_manager_logic_test.dart`
- Modify: `lib/call/audio_handler.dart`
- Modify: `lib/call/video_handler.dart`

**Step 1: Write the failing tests**

- Verify audio capture uses explicit `48kHz`, mono, PCM16 configuration.
- Verify video helper compacts padded or strided YUV planes into contiguous I420 buffers.
- Verify helper logic reports when speaker control should be hidden on unsupported platforms.

**Step 2: Run the tests to confirm they fail**

Run: `flutter test test/call_service_manager_logic_test.dart`

Expected: failures for missing helpers / wrong behavior.

**Step 3: Implement the minimal production helpers**

- Add a testable factory/helper for recorder configuration.
- Add a testable plane-compaction helper for video frames.
- Add a small platform capability helper for speaker availability.

**Step 4: Run the tests to confirm they pass**

Run: `flutter test test/call_service_manager_logic_test.dart`

Expected: all tests pass.

### Task 2: Fix signaling-path outgoing call bookkeeping

**Files:**
- Create: `test/call_bridge_service_test.dart`
- Modify: `../tim2tox/dart/lib/service/call_bridge_service.dart`
- Modify: `../tim2tox/dart/lib/service/tuicallkit_adapter.dart`

**Step 1: Write the failing test**

- Verify an outgoing invite is registered in `CallBridgeService`, can be looked up by `inviteID`, and can be ended cleanly.

**Step 2: Run the test to confirm it fails**

Run: `flutter test test/call_bridge_service_test.dart`

Expected: failure because outgoing calls are not tracked.

**Step 3: Implement the minimal fix**

- Add an explicit outgoing-call registration API in `CallBridgeService`.
- Call it from `TUICallKitAdapter` immediately after signaling invite success.
- Preserve correct call metadata for cancel / reject / timeout / end.

**Step 4: Run the test to confirm it passes**

Run: `flutter test test/call_bridge_service_test.dart`

Expected: pass.

### Task 3: Make mobile UX safe for unsupported or denied call capabilities

**Files:**
- Modify: `lib/call/call_service_manager.dart`
- Modify: `lib/call/in_call_view.dart`
- Modify: `lib/call/permission_helper.dart`
- Modify: `chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/tencent_cloud_chat_message_input_container.dart`

**Step 1: Write the failing test**

- Verify unsupported controls or flows are gated: group-call entry hidden, speaker control hidden when no route implementation is available, and permission preflight returns structured results.

**Step 2: Run the test to confirm it fails**

Run: `flutter test test/call_service_manager_logic_test.dart`

Expected: failures for unsupported UI / permission handling.

**Step 3: Implement the minimal fix**

- Add permission preflight helpers.
- Gate unsupported controls in the UI.
- Hide the mobile speaker toggle until a real route implementation exists.
- Remove group-call entry from the message input path because adapter only supports 1v1.

**Step 4: Run the tests to confirm they pass**

Run: `flutter test test/call_service_manager_logic_test.dart test/message_header_actions_test.dart`

Expected: pass.

### Task 4: Wire the runtime behavior and verify call regression coverage

**Files:**
- Modify: `lib/call/call_service_manager.dart`
- Modify: `lib/call/video_handler.dart`
- Modify: `lib/call/audio_handler.dart`

**Step 1: Write the failing test**

- Verify toggling local video stops and resumes capture consistently.
- Verify denied permissions prevent media start and do not leave the call UI in a misleading state.

**Step 2: Run the test to confirm it fails**

Run: `flutter test test/call_service_manager_logic_test.dart`

Expected: fail.

**Step 3: Implement the minimal fix**

- Restart local camera capture on video re-enable.
- Compact and send normalized video buffers.
- Use explicit audio capture config.
- Keep permission failures from silently pretending media started.

**Step 4: Run the focused and broader suites**

Run: `flutter test test/call_service_manager_logic_test.dart test/call_bridge_service_test.dart test/call_and_history_regression_test.dart test/user_profile_call_actions_test.dart test/message_header_actions_test.dart`

Expected: all pass.
