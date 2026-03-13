import 'package:shared_preferences/shared_preferences.dart';

import 'app_bootstrap_result.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import '../util/prefs_upgrader.dart';

/// Prefs initialization and schema migration. Returns [AppBootstrapUpgradeRequired]
/// when stored prefs are from a newer app version.
class PrefsBootstrap {
  PrefsBootstrap._();

  /// Returns null on success; [AppBootstrapUpgradeRequired] when upgrade required.
  static Future<AppBootstrapUpgradeRequired?> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setLanBootstrapServiceRunning(false);
    try {
      await PrefsUpgrader.run(prefs);
    } on PrefsStorageNewerThanAppException catch (e) {
      AppLogger.log(
          'Prefs stored by newer app (${e.storedVersion} > ${e.currentVersion}), showing upgrade required');
      return AppBootstrapUpgradeRequired(
        storedVersion: e.storedVersion,
        currentVersion: e.currentVersion,
      );
    }
    return null;
  }
}
