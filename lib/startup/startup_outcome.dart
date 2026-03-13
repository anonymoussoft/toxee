import 'package:tim2tox_dart/service/ffi_chat_service.dart';

/// Result of [StartupSessionUseCase.execute].
/// Widget reacts by updating UI and/or navigating.
sealed class StartupOutcome {
  const StartupOutcome();
}

/// No registered user or auto-login disabled; show login/registration.
final class StartupShowLogin extends StartupOutcome {
  const StartupShowLogin();
}

/// Startup failed; show error message and retry/go-to-login.
final class StartupShowError extends StartupOutcome {
  const StartupShowError(this.message);
  final String message;
}

/// Service is ready and (if needed) friends loaded; navigate to home.
final class StartupOpenHome extends StartupOutcome {
  const StartupOpenHome(this.service);
  final FfiChatService service;
}

/// Service created but not yet connected; widget must wait and then load friends and navigate.
final class StartupWaitForConnection extends StartupOutcome {
  const StartupWaitForConnection(this.service);
  final FfiChatService service;
}
