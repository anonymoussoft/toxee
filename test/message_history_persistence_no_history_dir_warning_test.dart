// Regression test for X11 — MessageHistoryPersistence surfaces a warning at
// construction time when no per-account `historyDirectory` is injected.
//
// `MessageHistoryPersistence` defaults to a shared `<AppSupport>/chat_history`
// directory when no `historyDirectory` is passed. With more than one account
// on the device that silently merges histories — conversation files key on
// peer pubkey only, so messages from two different accounts to the same peer
// collide. X11 doesn't change the default behaviour (that would break
// existing tests and the LAN-bootstrap / first-launch fallback paths); it
// just logs a structured warning so integrators notice early.
//
// This test does not exercise disk I/O — only the construction-time logger
// call. No FFI needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/interfaces/logger_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

class _RecordingLogger implements LoggerService {
  final List<String> infos = [];
  final List<String> warnings = [];
  final List<String> debugs = [];
  final List<String> errors = [];

  @override
  void log(String message) => infos.add(message);

  @override
  void logWarning(String message) => warnings.add(message);

  @override
  void logDebug(String message) => debugs.add(message);

  @override
  void logError(String message, Object error, StackTrace stack) =>
      errors.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageHistoryPersistence — X11 missing historyDirectory warning',
      () {
    test('logs a warning via injected logger when historyDirectory is null',
        () {
      final logger = _RecordingLogger();
      // Build but don't touch disk.
      MessageHistoryPersistence(logger: logger);
      expect(logger.warnings, isNotEmpty);
      expect(
        logger.warnings.single,
        contains('historyDirectory'),
        reason: 'warning text should mention the missing argument',
      );
      expect(logger.warnings.single, contains('per-account'));
    });

    test('logs a warning when historyDirectory is empty string', () {
      final logger = _RecordingLogger();
      MessageHistoryPersistence(historyDirectory: '', logger: logger);
      expect(logger.warnings, isNotEmpty);
    });

    test(
        'does NOT log a warning when historyDirectory is supplied (happy path)',
        () {
      final logger = _RecordingLogger();
      MessageHistoryPersistence(
        historyDirectory: '/tmp/anywhere_explicit',
        logger: logger,
      );
      expect(logger.warnings, isEmpty);
    });
  });
}
