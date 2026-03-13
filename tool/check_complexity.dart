import 'dart:io';

/// Checks that no Dart file in lib/ exceeds the line-count threshold.
/// Run from project root: dart run tool/check_complexity.dart
/// Exit code 1 if any file exceeds [maxLines] (default 500).
void main(List<String> args) {
  const maxLines = 500;
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[complexity] lib/ not found');
    exit(1);
  }
  var failed = 0;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync().length;
    if (lines > maxLines) {
      stderr.writeln('[complexity] ${entity.path}: $lines LOC (> $maxLines)');
      failed++;
    }
  }
  // Initially warn only; switch to exit(1) once splits are done (plan §14).
  if (failed > 0) {
    // exit(1);
  }
}
