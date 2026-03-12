import 'package:tim2tox_dart/interfaces/logger_service.dart';
import '../util/logger.dart';

/// Adapter that implements LoggerService using AppLogger
class AppLoggerAdapter implements LoggerService {
  @override
  void log(String message) {
    AppLogger.info(message);
  }

  @override
  void logError(String message, Object error, StackTrace stack) {
    AppLogger.logError(message, error, stack);
  }

  @override
  void logWarning(String message) {
    AppLogger.warn(message);
  }

  @override
  void logDebug(String message) {
    AppLogger.debug(message);
  }
}

