import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

void main() {
  group('UiKeys dynamic selectors', () {
    test(
      'conversation/contact/group row helpers expose stable key strings',
      () {
        expect(
          UiKeys.conversationListTile('c2c_friend').toString(),
          const ValueKey<String>(
            'conversation_list_item:c2c_friend',
          ).toString(),
        );
        expect(
          UiKeys.contactListTile('friend_123').toString(),
          const ValueKey<String>('contact_list_item:friend_123').toString(),
        );
        expect(
          UiKeys.groupListTile('tox_42').toString(),
          const ValueKey<String>('group_list_tile:tox_42').toString(),
        );
      },
    );

    test('group profile member-entry key is stable', () {
      expect(
        UiKeys.groupProfileMembersEntry.toString(),
        const ValueKey<String>('group_profile_members_entry').toString(),
      );
    });
  });
}
