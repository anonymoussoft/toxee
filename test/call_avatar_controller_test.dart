import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_avatar_controller.dart';

void main() {
  test('clears avatar state when user id becomes empty', () async {
    final controller = CallAvatarController(
      loadPath: (userId) async => '/tmp/$userId.png',
      fileExists: (path) async => true,
    );

    await controller.loadForUser('alice');
    expect(controller.avatarPath, '/tmp/alice.png');
    expect(controller.hasAvatarImage, isTrue);

    await controller.loadForUser('');

    expect(controller.avatarPath, isNull);
    expect(controller.hasAvatarImage, isFalse);
  });

  test('ignores stale avatar loads when a newer user request finishes first',
      () async {
    final completers = <String, Completer<String?>>{
      'alice': Completer<String?>(),
      'bob': Completer<String?>(),
    };
    final controller = CallAvatarController(
      loadPath: (userId) => completers[userId]!.future,
      fileExists: (path) async => true,
    );

    final aliceFuture = controller.loadForUser('alice');
    final bobFuture = controller.loadForUser('bob');

    completers['bob']!.complete('/tmp/bob.png');
    await bobFuture;
    completers['alice']!.complete('/tmp/alice.png');
    await aliceFuture;

    expect(controller.avatarPath, '/tmp/bob.png');
    expect(controller.hasAvatarImage, isTrue);
  });
}
