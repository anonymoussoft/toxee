import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_paths.dart';

/// Log levels for unified format (matches C++ V2TIMLog).
enum LogLevel {
  debug,
  info,
  warn,
  error,
  fatal,
}

class AppLogger {
  static int _sequence = 0;
  static final int _pid = _getPid();
  static bool _enableFileLogging = true;
  static bool _enableConsoleLogging = false;
  static File? _logFile;
  static bool _initialized = false;
  static String? _customLogPath;
  static bool _hasLoggedError = false;

  static const String _tid = 'main'; // Dart main isolate; use Isolate.current.debugName if needed

  static int _getPid() {
    try {
      return pid;
    } catch (e) {
      return 0;
    }
  }

  static String _formatTime(DateTime now) {
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// Unified format: [pid-tid-seqno] YYYY-MM-DD HH:MM:SS [LEVEL] body
  static String _formatLine(LogLevel level, String body) {
    _sequence++;
    final seq = _sequence.toString();
    final now = DateTime.now();
    final timeStr = _formatTime(now);
    const levelStr = {
      LogLevel.debug: 'DEBUG',
      LogLevel.info: 'INFO',
      LogLevel.warn: 'WARN',
      LogLevel.error: 'ERROR',
      LogLevel.fatal: 'FATAL',
    };
    return '[$_pid-$_tid-$seq] $timeStr [${levelStr[level]}] $body';
  }

  static void setLogPath(String? path) {
    _customLogPath = path;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (_enableFileLogging) {
        if (_customLogPath != null) {
          final logFile = File(_customLogPath!);
          final logDir = logFile.parent;
          if (!await logDir.exists()) {
            await logDir.create(recursive: true);
          }
          _logFile = logFile;
          stderr.writeln('AppLogger: Log file initialized at: ${logFile.path}');
          stderr.writeln('AppLogger: Log directory exists: ${await logDir.exists()}');
        } else {
          final logDir = await AppPaths.logsDir;
          if (!await logDir.exists()) {
            await logDir.create(recursive: true);
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          _logFile = File('${logDir.path}/app_$timestamp.log');
        }
        await _logFile!.writeAsString('=== App Log Started ===\n', mode: FileMode.append);
      }
      _initialized = true;
    } catch (e) {
      stderr.writeln('Warning: Failed to initialize file logging: $e');
      _enableFileLogging = false;
    }
  }

  static void setFileLoggingEnabled(bool enabled) {
    _enableFileLogging = enabled;
  }

  static void setConsoleLoggingEnabled(bool enabled) {
    _enableConsoleLogging = enabled;
  }

  static String? getLogPath() {
    return _logFile?.path;
  }

  static void _writeToFile(String line) {
    if (!_enableFileLogging) return;
    if (_logFile == null) {
      if (!_hasLoggedError) {
        _hasLoggedError = true;
        stderr.writeln('AppLogger: Log file is null, cannot write. Call initialize() first.');
      }
      return;
    }
    try {
      _logFile!.writeAsStringSync('$line\n', mode: FileMode.append);
      _hasLoggedError = false;
    } catch (e, stackTrace) {
      if (!_hasLoggedError) {
        _hasLoggedError = true;
        stderr.writeln('AppLogger: Failed to write to log file: $e');
        stderr.writeln('AppLogger: Log file path: ${_logFile?.path}');
        for (final line in stackTrace.toString().split('\n')) {
          if (line.trim().isNotEmpty) stderr.writeln('AppLogger:   $line');
        }
      }
    }
  }

  static void _emit(LogLevel level, String body) {
    final formatted = _formatLine(level, body);
    if (_enableConsoleLogging) {
      if (level == LogLevel.debug) {
        debugPrint(formatted);
      } else {
        print(formatted);
      }
    }
    _writeToFile(formatted);
  }

  /// Log at DEBUG level
  static void debug(String message) {
    _emit(LogLevel.debug, message);
  }

  /// Log at INFO level
  static void info(String message) {
    _emit(LogLevel.info, message);
  }

  /// Log at WARN level
  static void warn(String message) {
    _emit(LogLevel.warn, message);
  }

  /// Log at ERROR level (message only)
  static void error(String message) {
    _emit(LogLevel.error, message);
  }

  /// Log at ERROR level with exception and stack trace
  static void logError(String message, [Object? error, StackTrace? stackTrace]) {
    _emit(LogLevel.error, message);
    if (error != null) {
      _emit(LogLevel.error, 'Error: $error');
    }
    if (stackTrace != null) {
      for (final line in stackTrace.toString().split('\n')) {
        if (line.trim().isNotEmpty) _writeToFile('  $line');
      }
    }
    if (_enableConsoleLogging && (error != null || stackTrace != null)) {
      if (error != null) print('Error: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }

  /// Legacy: log at INFO level (for callers that used log())
  static void log(String message) {
    info(message);
  }

  /// Legacy: log at DEBUG level
  static void debugLog(String message) {
    debug(message);
  }
}
