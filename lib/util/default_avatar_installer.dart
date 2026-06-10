import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'prefs.dart';

abstract final class DefaultAvatarInstaller {
  static const String defaultUserAsset = 'assets/avatars/default_user.png';
  static const String defaultGroupAsset = 'assets/avatars/default_group.png';

  static Future<String> installDefaultUserAvatar({
    required String toxId,
    AssetBundle? bundle,
  }) async {
    final avatarsDirPath = await AppPaths.getAccountAvatarsPath(toxId);
    final destPath = p.join(avatarsDirPath, 'avatar_${toxId}_default.png');
    await _writeAsset(
      assetPath: defaultUserAsset,
      destPath: destPath,
      bundle: bundle ?? rootBundle,
    );
    return destPath;
  }

  static Future<String> installDefaultGroupAvatar({
    required String groupId,
    String? toxId,
    AssetBundle? bundle,
  }) async {
    final effectiveToxId = toxId?.trim().isNotEmpty == true
        ? toxId!.trim()
        : await Prefs.getCurrentAccountToxId();
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      throw StateError(
        'Cannot install default group avatar without an account',
      );
    }
    final avatarsDirPath = await AppPaths.getAccountAvatarsPath(effectiveToxId);
    final safeGroupId = _sanitizeSegment(groupId);
    final destPath = p.join(avatarsDirPath, 'group_${safeGroupId}_default.png');
    await _writeAsset(
      assetPath: defaultGroupAsset,
      destPath: destPath,
      bundle: bundle ?? rootBundle,
    );
    return destPath;
  }

  static Future<void> _writeAsset({
    required String assetPath,
    required String destPath,
    required AssetBundle bundle,
  }) async {
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    final bytes = await bundle.load(assetPath);
    await destFile.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  static String _sanitizeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
