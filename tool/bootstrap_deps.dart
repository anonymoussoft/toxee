// Bootstrap dependencies: init submodules, vendor tencent_cloud_chat_sdk, (later: apply patches, write overrides).
// Run from repo root: dart run tool/bootstrap_deps.dart
// Options: --offline-check-only (only verify existing state, no network), --force (re-vendor SDK)
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final repoRoot = _repoRoot();
  final offlineOnly = args.contains('--offline-check-only');
  final force = args.contains('--force');

  if (offlineOnly) {
    exit(_offlineCheck(repoRoot));
  }

  // 1) Submodule sync and update (or clone from .gitmodules if not yet registered)
  //    Do this first so third_party/tim2tox exists and contains the lock file.
  const submodulePaths = ['third_party/tim2tox', 'third_party/chat-uikit-flutter'];
  const submoduleUrls = {
    'third_party/tim2tox': 'https://github.com/anonymoussoft/tim2tox.git',
    'third_party/chat-uikit-flutter': 'https://github.com/anonymoussoft/chat-uikit-flutter.git',
  };
  int code = await _run(repoRoot, 'git', ['submodule', 'sync', '--recursive']);
  if (code != 0) {
    stderr.writeln('bootstrap_deps: git submodule sync failed');
    exit(code);
  }
  // Update only registered submodules (no path args to avoid "pathspec did not match" when not registered)
  code = await _run(repoRoot, 'git', ['submodule', 'update', '--init', '--recursive']);
  if (code != 0) {
    stdout.writeln('Submodules not yet registered in repo; will clone from .gitmodules if missing.');
  }

  // Ensure submodule dirs exist: either from update --init or clone from .gitmodules URLs
  for (final p in submodulePaths) {
    final dir = Directory('$repoRoot/$p');
    if (!dir.existsSync()) {
      final url = submoduleUrls[p];
      if (url == null) {
        stderr.writeln('bootstrap_deps: no URL for $p');
        exit(1);
      }
      stdout.writeln('Cloning $p...');
      final parts = p.split('/');
      final parentPath = parts.sublist(0, parts.length - 1).join('/');
      if (parentPath.isNotEmpty) {
        Directory('$repoRoot/$parentPath').createSync(recursive: true);
      }
      code = await _run(repoRoot, 'git', ['clone', url, p]);
      if (code != 0) {
        stderr.writeln('bootstrap_deps: git clone $p failed');
        exit(code);
      }
    }
  }

  // Pin chat-uikit-flutter to v2 branch (see .gitmodules branch = v2)
  final uikitDir = Directory('$repoRoot/third_party/chat-uikit-flutter');
  if (uikitDir.existsSync()) {
    const branch = 'v2';
    int c = await _run(repoRoot, 'git', ['-C', 'third_party/chat-uikit-flutter', 'fetch', 'origin', branch]);
    if (c == 0) {
      c = await _run(repoRoot, 'git', ['-C', 'third_party/chat-uikit-flutter', 'checkout', '-B', branch, 'FETCH_HEAD']);
      if (c == 0) {
        stdout.writeln('third_party/chat-uikit-flutter switched to branch $branch');
      }
    }
  }

  final tim2toxDir = Directory('$repoRoot/third_party/tim2tox');
  final lockFile = File('$repoRoot/third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
  if (!lockFile.existsSync()) {
    stderr.writeln('bootstrap_deps: missing third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
    stderr.writeln('  Ensure third_party/tim2tox is present (clone or use tool/verify_bootstrap_local.sh for local workspace).');
    exit(1);
  }
  final lock = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
  final version = lock['version'] as String? ?? '';
  final archiveUrl = lock['archive_url'] as String? ?? '';
  final expectedSha256 = lock['sha256'] as String?;
  if (version.isEmpty || archiveUrl.isEmpty) {
    stderr.writeln('bootstrap_deps: lock file must have version and archive_url');
    exit(1);
  }

  // 2) Vendor SDK
  final sdkDir = Directory('$repoRoot/third_party/tencent_cloud_chat_sdk');
  final stateFile = File('$repoRoot/tool/vendor_state.json');
  final currentState = _readVendorState(stateFile);
  final needVendor = force ||
      !sdkDir.existsSync() ||
      currentState['version'] != version ||
      (expectedSha256 != null && expectedSha256.isNotEmpty && currentState['sha256'] != expectedSha256);

  if (needVendor) {
    if (sdkDir.existsSync()) sdkDir.deleteSync(recursive: true);
    sdkDir.createSync(recursive: true);
    final tempDir = Directory.systemTemp.createTempSync('toxee_sdk_');
    try {
      final archivePath = '${tempDir.path}/sdk.tar.gz';
      stdout.writeln('Downloading tencent_cloud_chat_sdk $version...');
      await _download(archiveUrl, archivePath);
      String? actualSha256;
      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        actualSha256 = await _sha256File(archivePath);
        if (actualSha256 != expectedSha256) {
          stderr.writeln('bootstrap_deps: SHA-256 mismatch (got $actualSha256, expected $expectedSha256)');
          exit(1);
        }
      } else {
        actualSha256 = await _sha256File(archivePath);
      }
      await _extractTarGz(archivePath, tempDir.path);
      // Pub tarball extracts to a single top-level dir (e.g. package/ or tencent_cloud_chat_sdk-8.7.7201/)
      final entries = tempDir.listSync().whereType<FileSystemEntity>().toList();
      if (entries.length == 1 && entries.first is Directory) {
        final inner = entries.first as Directory;
        for (final e in inner.listSync()) {
          final name = e.path.split(Platform.pathSeparator).last;
          final dest = File('${sdkDir.path}/$name');
          if (e is File) {
            e.copySync(dest.path);
          } else if (e is Directory) {
            Directory('${sdkDir.path}/$name').createSync(recursive: true);
            _copyDir(e, Directory('${sdkDir.path}/$name'));
          }
        }
      } else {
        // Flat list of files/dirs at top level
        for (final e in entries) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (e is File) {
            e.copySync('${sdkDir.path}/$name');
          } else if (e is Directory) {
            final destSub = Directory('${sdkDir.path}/$name');
            destSub.createSync(recursive: true);
            _copyDir(e, destSub);
          }
        }
      }
      stateFile.writeAsStringSync(jsonEncode({
        'version': version,
        'sha256': actualSha256,
      }));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  // 3) Apply SDK patch series via tim2tox tool (patches live in tim2tox repo: patches/tencent_cloud_chat_sdk/<version>/)
  final stateMap = stateFile.existsSync() ? (jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>) : <String, dynamic>{};
  const appliedKey = 'patches_applied';
  final seriesFile = File('${tim2toxDir.path}/patches/tencent_cloud_chat_sdk/$version/series');
  final bool shouldApplySdkPatches = stateMap[appliedKey] != true &&
      tim2toxDir.existsSync() &&
      seriesFile.existsSync();
  if (shouldApplySdkPatches) {
    final lines = seriesFile.readAsLinesSync().map((s) => s.trim()).where((s) => s.isNotEmpty && !s.startsWith('#')).toList();
    if (lines.isNotEmpty) {
      stdout.writeln('Applying tencent_cloud_chat_sdk patches from tim2tox (${lines.length} patch(es))...');
      // Run tim2tox's apply_sdk_patches.dart directly (no "dart run") so it does not depend on package_config
      final scriptPath = File('${tim2toxDir.path}/tool/apply_sdk_patches.dart');
      if (!scriptPath.existsSync()) {
        stderr.writeln('bootstrap_deps: tim2tox tool/apply_sdk_patches.dart not found');
        exit(1);
      }
      final patchCode = await _run(repoRoot, 'dart', [scriptPath.path, '--sdk-dir=${sdkDir.path}'], workingDirectory: tim2toxDir.path);
      if (patchCode != 0) {
        stderr.writeln('bootstrap_deps: tim2tox apply_sdk_patches failed (exit $patchCode)');
        exit(patchCode);
      }
      stateMap[appliedKey] = true;
      stateFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(stateMap));
    }
  }

  // 4) Generate pubspec_overrides.yaml so all local deps resolve under third_party/
  const uikitPackages = [
    'tencent_cloud_chat_common',
    'tencent_cloud_chat_message',
    'tencent_cloud_chat_conversation',
    'tencent_cloud_chat_contact',
    'tencent_cloud_chat_sticker',
    'tencent_cloud_chat_intl',
    'tencent_cloud_chat_text_translate',
    'tencent_cloud_chat_sound_to_text',
  ];
  final overrides = StringBuffer('# Generated by tool/bootstrap_deps.dart - do not edit.\n');
  overrides.writeln('dependency_overrides:');
  overrides.writeln('  tim2tox_dart:');
  overrides.writeln('    path: third_party/tim2tox/dart');
  overrides.writeln('  tencent_cloud_chat_sdk:');
  overrides.writeln('    path: third_party/tencent_cloud_chat_sdk');
  for (final p in uikitPackages) {
    overrides.writeln('  $p:');
    overrides.writeln('    path: third_party/chat-uikit-flutter/$p');
  }
  overrides.writeln('  record_linux: ^1.2.1');
  File('$repoRoot/pubspec_overrides.yaml').writeAsStringSync(overrides.toString());

  stdout.writeln('Bootstrap complete.');
}

int _offlineCheck(String repoRoot) {
  final lockFile = File('$repoRoot/third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
  if (!lockFile.existsSync()) return 1;
  final sdkDir = Directory('$repoRoot/third_party/tencent_cloud_chat_sdk');
  final tim2tox = Directory('$repoRoot/third_party/tim2tox');
  final uikit = Directory('$repoRoot/third_party/chat-uikit-flutter');
  if (!tim2tox.existsSync() || !uikit.existsSync()) return 1;
  if (!sdkDir.existsSync()) return 1;
  return 0;
}

Map<String, String> _readVendorState(File f) {
  if (!f.existsSync()) return {};
  try {
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return {
      'version': m['version']?.toString() ?? '',
      'sha256': m['sha256']?.toString() ?? '',
    };
  } catch (_) {
    return {};
  }
}

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/tool/bootstrap_deps.dart').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('bootstrap_deps: run from toxee repo root');
      exit(1);
    }
    dir = parent;
  }
}

Future<int> _run(String cwd, String executable, List<String> args, {String? workingDirectory}) async {
  final wd = workingDirectory ?? cwd;
  final r = await Process.run(executable, args, workingDirectory: wd, runInShell: false);
  if (r.stdout.toString().trim().isNotEmpty) stdout.write(r.stdout);
  if (r.stderr.toString().trim().isNotEmpty) stderr.write(r.stderr);
  return r.exitCode;
}

Future<void> _download(String url, String destPath) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final file = File(destPath).openWrite();
    await resp.pipe(file);
    await file.close();
  } finally {
    client.close();
  }
}

Future<String> _sha256File(String path) async {
  if (Platform.isWindows) {
    final r = await Process.run(
      'certutil',
      ['-hashfile', path, 'SHA256'],
      runInShell: false,
    );
    if (r.exitCode != 0) {
      throw Exception('certutil failed: ${r.stderr}');
    }
    final lines = (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => RegExp(r'^[A-Fa-f0-9 ]+$').hasMatch(line) && line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw Exception('certutil output did not contain a SHA-256 hash');
    }
    return lines.first.replaceAll(' ', '').toLowerCase();
  }

  try {
    final r = await Process.run('sha256sum', [path], runInShell: false);
    if (r.exitCode == 0) {
      return (r.stdout as String).split(' ').first.trim();
    }
  } on ProcessException {
    // Fall through to shasum on platforms like macOS where sha256sum is absent.
  }

  final r = await Process.run('shasum', ['-a', '256', path], runInShell: false);
  if (r.exitCode != 0) {
    throw Exception('sha256 tool failed: ${r.stderr}');
  }
  return (r.stdout as String).split(' ').first.trim();
}

Future<void> _extractTarGz(String archivePath, String destDir) async {
  final code = await Process.run('tar', ['-xzf', archivePath, '-C', destDir], runInShell: false).then((r) => r.exitCode);
  if (code != 0) throw Exception('tar extract failed');
}

void _copyDir(Directory src, Directory dest) {
  for (final e in src.listSync()) {
    final name = e.path.split(Platform.pathSeparator).last;
    final destPath = '${dest.path}/$name';
    if (e is File) {
      File(destPath).parent.createSync(recursive: true);
      e.copySync(destPath);
    } else if (e is Directory) {
      Directory(destPath).createSync(recursive: true);
      _copyDir(e, Directory(destPath));
    }
  }
}
