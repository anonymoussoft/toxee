import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/contact/friend_request_display_name.dart';

void main() {
  test('prefers explicit nickname when present', () {
    expect(
      resolveFriendRequestDisplayName(
        userId: 'ABC123',
        nickname: 'alice',
        wording: 'alice here! Tox me maybe?',
      ),
      'alice',
    );
  });

  test('infers nickname from "name here" wording pattern', () {
    expect(
      resolveFriendRequestDisplayName(
        userId: 'ABC123',
        wording: 'gaobin_linux here! Tox me maybe?',
      ),
      'gaobin_linux',
    );
  });

  test('falls back to user ID when wording has no safe nickname hint', () {
    expect(
      resolveFriendRequestDisplayName(
        userId: 'ABC123',
        wording: "Hello, I'd like to add you as a friend.",
      ),
      'ABC123',
    );
  });
}
