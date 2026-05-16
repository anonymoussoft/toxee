// Shared test support for account_export tests.
//
// Mocks path_provider so AppPaths.* writes land under a per-test temp dir
// instead of the user's actual ~/Library/Application Support. Also wires
// SharedPreferences mock initial values and exposes a helper that returns
// the temp root.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

class AccountExportTestEnv {
  AccountExportTestEnv._(this.root);
  final Directory root;

  String get appSupport => p.join(root.path, 'app_support');
  String get downloads => p.join(root.path, 'downloads');
  String get profiles => p.join(root.path, 'profiles');
  String get extras => p.join(root.path, 'extras');

  Future<void> dispose() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
    // Tear down path_provider mock so subsequent groups in the same file
    // can install their own handler against a fresh temp dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  }
}

/// Sets up path_provider mocks, creates the per-test temp dirs, configures
/// Prefs with `profile_storage_root` + `downloads_directory` pointed at the
/// temp dirs, and returns the environment handle.
Future<AccountExportTestEnv> setUpAccountExportTestEnv({
  Map<String, Object> sharedPrefs = const {},
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = await Directory.systemTemp.createTemp('toxee_export_test_');
  final env = AccountExportTestEnv._(root);

  for (final sub in [env.appSupport, env.downloads, env.profiles, env.extras]) {
    await Directory(sub).create(recursive: true);
  }

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'getApplicationSupportDirectory':
          return env.appSupport;
        case 'getApplicationDocumentsDirectory':
          return env.appSupport;
        case 'getApplicationCacheDirectory':
          return p.join(env.root.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(env.root.path, 'temp');
        case 'getDownloadsDirectory':
          return env.downloads;
        default:
          return null;
      }
    },
  );

  SharedPreferences.setMockInitialValues({
    'profile_storage_root': env.profiles,
    'downloads_directory': env.downloads,
    ...sharedPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
  // Persist (in case mock initial values were ignored for these keys).
  await Prefs.setProfileStorageRoot(env.profiles);
  await Prefs.setDownloadsDirectory(env.downloads);

  return env;
}
