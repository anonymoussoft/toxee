/// Result of [AppBootstrap.initialize].
sealed class AppBootstrapResult {
  const AppBootstrapResult();
}

/// Bootstrap completed successfully; run the app.
class AppBootstrapSuccess extends AppBootstrapResult {
  const AppBootstrapSuccess();
}

/// Stored prefs were created by a newer app version; show upgrade required UI.
class AppBootstrapUpgradeRequired extends AppBootstrapResult {
  const AppBootstrapUpgradeRequired({
    required this.storedVersion,
    required this.currentVersion,
  });

  final int storedVersion;
  final int currentVersion;
}
