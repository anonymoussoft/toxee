import 'dart:io' show File;

import 'package:flutter/foundation.dart';

import '../util/prefs.dart';

typedef CallAvatarPathLoader = Future<String?> Function(String userId);
typedef CallAvatarFileExists = Future<bool> Function(String path);

class CallAvatarController extends ChangeNotifier {
  CallAvatarController({
    CallAvatarPathLoader? loadPath,
    CallAvatarFileExists? fileExists,
  })  : _loadPath = loadPath ?? Prefs.getFriendAvatarPath,
        _fileExists = fileExists ?? ((path) => File(path).exists());

  final CallAvatarPathLoader _loadPath;
  final CallAvatarFileExists _fileExists;

  String? _avatarPath;
  bool _hasAvatarImage = false;
  int _loadToken = 0;

  String? get avatarPath => _avatarPath;
  bool get hasAvatarImage => _hasAvatarImage;

  Future<void> loadForUser(String? userId) async {
    final token = ++_loadToken;
    final trimmedId = userId?.trim() ?? '';
    if (trimmedId.isEmpty) {
      _setState(path: null, hasAvatarImage: false);
      return;
    }

    final path = await _loadPath(trimmedId);
    final hasImage =
        path != null && path.isNotEmpty ? await _fileExists(path) : false;

    if (token != _loadToken) {
      return;
    }

    _setState(
      path: hasImage ? path : null,
      hasAvatarImage: hasImage,
    );
  }

  void _setState({
    required String? path,
    required bool hasAvatarImage,
  }) {
    if (_avatarPath == path && _hasAvatarImage == hasAvatarImage) {
      return;
    }
    _avatarPath = path;
    _hasAvatarImage = hasAvatarImage;
    notifyListeners();
  }
}
