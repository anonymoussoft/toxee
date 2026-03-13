/// Represents different initialization steps during app startup.
/// Shared by [StartupSessionUseCase] and [StartupLoadingScreen].
enum StartupStep {
  checkingUserInfo,
  initializingService,
  loggingIn,
  initializingSDK,
  updatingProfile,
  connecting,
  loadingFriends,
  completed,
}
