import 'app_bootstrap_result.dart';
import 'app_runtime_bootstrap.dart';
import 'desktop_shell_bootstrap.dart';
import 'logging_bootstrap.dart';
import 'prefs_bootstrap.dart';

/// Application startup orchestration. [initialize] runs logging, prefs, runtime,
/// and desktop shell (if applicable), then returns a result for the caller to
/// run the appropriate app.
class AppBootstrap {
  AppBootstrap._();

  static Future<AppBootstrapResult> initialize() async {
    await LoggingBootstrap.initialize();
    final prefsResult = await PrefsBootstrap.initialize();
    if (prefsResult != null) {
      return prefsResult;
    }
    await AppRuntimeBootstrap.initialize();
    await DesktopShellBootstrap.initializeIfNeeded();
    return const AppBootstrapSuccess();
  }
}

