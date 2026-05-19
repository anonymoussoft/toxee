part of 'home_page.dart';

// BinaryReplacementHistoryHook installation lived here historically. It now
// lives in `lib/runtime/session_runtime_coordinator.dart` so the hook is
// installed in the same atomic init block as `Tim2ToxSdkPlatform`,
// eliminating the window where FFI-path messages could write to history
// before the UIKit listener wrapper was in place.
//
// File intentionally kept (not deleted) to preserve the `part` declaration
// in `home_page.dart` and minimize unrelated diff churn.
