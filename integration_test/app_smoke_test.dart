// End-to-end startup smoke for toxee.
//
// Strategy: **Strategy B — mocked-platform integration**.
//
// **CI gating** — tagged `needs-native` because even though the test itself
// only renders a LoginPage and stubs every plugin channel it touches,
// `flutter test integration_test/...` builds a real platform binary (macOS
// app, iOS .app, Android APK, etc.) before running, and that build links
// `libtim2tox_ffi`. CI jobs that don't run the toxee bootstrap (which
// fetches + builds the native lib via `tool/bootstrap_deps.dart`) should
// skip this with `--exclude-tags=needs-native`.
//
// The dedicated workflow is `.github/workflows/e2e.yml` (opt-in via `ci:e2e`
// label) which both runs `bootstrap_deps.dart` AND builds the native lib via
// `tool/ci/build_tim2tox.sh`. Do NOT graft this test into analyze.yml —
// analyze.yml runs `bootstrap_deps.dart` but does not build libtim2tox_ffi
// or install Flutter desktop deps, so a `flutter test integration_test/`
// step there would fail at dlopen.
//
// CLAUDE.md flags the hybrid startup ordering (binary-replacement +
// Platform path + FakeUIKit + Tim2ToxSdkPlatform install) as the most
// failure-prone seam in the codebase. Unit tests cover individual pieces
// (`test/runtime/`, `test/auth/`, `test/sdk_fake/`), but nothing exercises
// the full `runApp(EchoUIKitApp())` → `_StartupGate._runStartup()` →
// resolved-outcome → first-frame chain. This smoke fills that gap.
//
// We deliberately do **not** call `AppBootstrap.initialize()` from `main()`:
//
//   1. `LoggingBootstrap` ends with `Tim2ToxFfi.open()` + `setLogFile(...)`,
//      which requires `libtim2tox_ffi` on `dlopen()` paths. CI build
//      machines don't always have that.
//   2. `AppRuntimeBootstrap` / `DesktopShellBootstrap` touch `window_manager`,
//      `tray_manager`, `flutter_local_notifications` — each one's
//      `MissingPluginException` would pollute the report.
//   3. `setNativeLibraryName('tim2tox_ffi')` (also in `LoggingBootstrap`) is
//      only required by call paths that this smoke deliberately avoids.
//
// Instead we drive `EchoUIKitApp` directly with:
//   * `SharedPreferences.setMockInitialValues({})` — empty prefs.
//   * a mocked `plugins.flutter.io/path_provider` channel pointed at a
//     per-test temp dir (so `Hive.initFlutter()` inside
//     `TencentCloudChatMaterialApp` doesn't crash trying to write to the
//     real `~/Library/Application Support`).
//   * a no-op handler for noisy plugin channels (`flutter_secure_storage`,
//     `xyz.luan/audioplayers`) — none of these are reached on the
//     [StartupShowLogin] path, but stubbing them keeps the report clean if
//     a future change adds a touch.
//
// With empty prefs, `StartupSessionUseCase.execute()` returns
// [StartupShowLogin] (nickname is null → first branch). `_StartupGate`
// flips `_checking = false` and the build renders `const LoginPage()`.
// We assert the LoginPage's "Register new account" call-to-action is
// visible — that's the user-observable proof that the startup chain
// completed without throwing.
//
// Run locally:
//   flutter test integration_test/app_smoke_test.dart
//
// The test lives under `integration_test/` (the conventional home for
// end-to-end smokes). The first run on a clean checkout builds the host
// platform binary (e.g. `Toxee.app` on macOS) before the Dart test
// process starts — that's how `flutter test integration_test/...` works
// and there is no opt-out. Subsequent runs reuse the cached build. The
// in-process test itself uses the plain `TestWidgetsFlutterBinding` so
// the actual smoke executes against the Dart VM with the platform-
// channel stubs below, not against the real plugins linked into the
// host binary — this keeps the assertions hermetic even though the
// build is not.
//
// A follow-up PR can wire this into CI as a separate step (e.g.
// `flutter test integration_test/`) in the existing analyze.yml job.
// The smoke needs no extra setup beyond `flutter pub get` (plus a
// successful `dart run tool/bootstrap_deps.dart`).
@Tags(['needs-native'])
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/main.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/util/prefs.dart';

/// Per-suite temp dir + plugin-channel stubs. Returned as a record so the
/// teardown can clear handlers without a stateful helper class.
typedef _SmokeHarness = ({
  Directory root,
  void Function() teardown,
});

Future<_SmokeHarness> _installPluginStubs() async {
  final root = await Directory.systemTemp.createTemp('toxee_smoke_');
  final appSupport = Directory(p.join(root.path, 'app_support'));
  final downloads = Directory(p.join(root.path, 'downloads'));
  final cache = Directory(p.join(root.path, 'cache'));
  final temp = Directory(p.join(root.path, 'temp'));
  for (final d in [appSupport, downloads, cache, temp]) {
    await d.create(recursive: true);
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // path_provider: route every channel call to our temp dirs so any code
  // path that calls `getApplicationDocumentsDirectory()` (e.g. Hive used
  // by TencentCloudChatMaterialApp.cache.init) lands inside the sandbox.
  const pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(pathProviderChannel,
      (MethodCall call) async {
    switch (call.method) {
      case 'getApplicationSupportDirectory':
      case 'getApplicationDocumentsDirectory':
        return appSupport.path;
      case 'getApplicationCacheDirectory':
        return cache.path;
      case 'getTemporaryDirectory':
        return temp.path;
      case 'getDownloadsDirectory':
        return downloads.path;
      default:
        return null;
    }
  });

  // flutter_secure_storage: not reached on the StartupShowLogin path, but
  // a no-op handler keeps the report clean if a future change touches it.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  messenger.setMockMethodCallHandler(secureStorageChannel,
      (MethodCall call) async {
    switch (call.method) {
      case 'read':
      case 'readAll':
        return null;
      case 'containsKey':
        return false;
      default:
        return null;
    }
  });

  // audioplayers: FakeUIKit.startWithFfi is NOT called in this smoke (we
  // never reach the runtime coordinator), but stub the channel to defend
  // against transitive touches in MaterialApp builder.
  const audioplayersChannel = MethodChannel('xyz.luan/audioplayers');
  messenger.setMockMethodCallHandler(
      audioplayersChannel, (MethodCall call) async => null);
  const audioplayersGlobalChannel =
      MethodChannel('xyz.luan/audioplayers.global');
  messenger.setMockMethodCallHandler(
      audioplayersGlobalChannel, (MethodCall call) async => null);

  void teardown() {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(audioplayersChannel, null);
    messenger.setMockMethodCallHandler(audioplayersGlobalChannel, null);
  }

  return (root: root, teardown: teardown);
}

void main() {
  // Use the plain test binding (not IntegrationTestWidgetsFlutterBinding)
  // so `flutter test integration_test/...` stays headless. See the file
  // header for the full rationale.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SmokeHarness harness;

  setUp(() async {
    harness = await _installPluginStubs();
    // Empty prefs → Prefs.getNickname() returns null → StartupShowLogin.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  tearDown(() async {
    harness.teardown();
    try {
      await harness.root.delete(recursive: true);
    } catch (_) {
      // Temp cleanup is best-effort; the OS reaps `/tmp` on its own cadence.
    }
  });

  testWidgets(
      'cold start with no profile renders LoginPage without exceptions',
      (WidgetTester tester) async {
    // Drive `EchoUIKitApp` directly (no main() — see file header for why).
    // The pumpWidget renders the app frame; the `_StartupGate` then runs
    // its async startup chain off the main thread, and we wait it out
    // with pumpAndSettle.
    await tester.pumpWidget(const EchoUIKitApp());

    // Settle through:
    //   * TencentCloudChatMaterialApp's FutureBuilder for _getLocale
    //     (which calls Hive.initFlutter under the mocked path_provider)
    //   * _StartupGate.initState() → _runStartup() → StartupShowLogin
    //   * setState that flips _checking = false
    //   * the next build that returns `const LoginPage()`.
    //
    // pumpAndSettle's positional args are (step, phase, timeout). Default
    // step is 100ms; passing Duration(seconds: 30) as the first arg would
    // fast-forward virtual time by 30s per pump and silently fire any
    // startup Timer that's due — masking real cold-start regressions.
    // Use default 100ms step + explicit 30s timeout for the cold-Hive
    // worst case observed on CI.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );

    // No exception escaped the framework's error handler during the
    // startup chain — this is the headline assertion (CLAUDE.md flags
    // the startup ordering as the most failure-prone seam in the codebase).
    expect(tester.takeException(), isNull,
        reason: 'startup chain must complete without uncaught exceptions');

    // We landed on the LoginPage — the only widget that `_StartupGate.build`
    // returns when the outcome is `StartupShowLogin`. Anything else means
    // the use case took a different branch and the test setup is stale.
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'StartupShowLogin must resolve to a LoginPage render');

    // Sanity: the localized "Register new account" call-to-action is on
    // screen. This proves AppLocalizations is wired (delegate registered,
    // English fallback resolved) and the LoginPage actually painted past
    // its initState async loads. We look it up via the AppLocalizations
    // helper rather than hard-coding the English string so a future i18n
    // tweak doesn't break the smoke.
    final BuildContext loginContext =
        tester.element(find.byType(LoginPage));
    final String registerLabel =
        AppLocalizations.of(loginContext)!.registerNewAccount;
    expect(find.text(registerLabel), findsOneWidget,
        reason:
            'LoginPage should render its localized register-new-account CTA');
  });
}
