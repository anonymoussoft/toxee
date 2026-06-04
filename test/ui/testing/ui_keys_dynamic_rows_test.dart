import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

void main() {
  group('UiKeys dynamic row helpers', () {
    test('conversationListTile uses the stable runtime key shape', () {
      expect(
        UiKeys.conversationListTile('c2c_friend_123'),
        const Key('conversation_list_item:c2c_friend_123'),
      );
    });

    test('contactListTile uses the stable runtime key shape', () {
      expect(
        UiKeys.contactListTile('friend_123'),
        const Key('contact_list_item:friend_123'),
      );
    });

    test('groupListTile uses the toxee-owned key shape', () {
      expect(
        UiKeys.groupListTile('tox_42'),
        const Key('group_list_tile:tox_42'),
      );
    });

    test('group profile entry/action keys stay stable', () {
      expect(
        UiKeys.groupProfileMembersEntry,
        const Key('group_profile_members_entry'),
      );
      expect(
        UiKeys.groupProfileClearHistoryButton,
        const Key('group_profile_clear_history_button'),
      );
      expect(
        UiKeys.groupProfileLeaveButton,
        const Key('group_profile_leave_button'),
      );
      expect(
        UiKeys.userProfileEditRemarkButton,
        const Key('user_profile_edit_remark_button'),
      );
      expect(
        UiKeys.userProfileFriendNameText,
        const Key('user_profile_friend_name_text'),
      );
      expect(
        UiKeys.userProfileModifyRemarkDialog,
        const Key('user_profile_modify_remark_dialog'),
      );
      expect(
        UiKeys.userProfileModifyRemarkTextField,
        const Key('user_profile_modify_remark_text_field'),
      );
      expect(
        UiKeys.userProfileModifyRemarkConfirmButton,
        const Key('user_profile_modify_remark_confirm_button'),
      );
      expect(
        UiKeys.userProfileConversationMuteSwitch,
        const Key('user_profile_conversation_mute_switch'),
      );
      expect(
        UiKeys.userProfileClearHistoryButton,
        const Key('user_profile_clear_history_button'),
      );
      expect(
        UiKeys.userProfileClearHistoryConfirmButton,
        const Key('user_profile_clear_history_confirm_button'),
      );
      expect(
        UiKeys.userProfileDeleteFriendButton,
        const Key('user_profile_delete_friend_button'),
      );
      expect(
        UiKeys.userProfileFriendNameText,
        const Key('user_profile_friend_name_text'),
      );
      expect(
        UiKeys.userProfileModifyRemarkDialog,
        const Key('user_profile_modify_remark_dialog'),
      );
      expect(
        UiKeys.contactApplicationItem('friend_123'),
        const Key('contact_application_item:friend_123'),
      );
      expect(
        UiKeys.contactApplicationAcceptButton('friend_123'),
        const Key('contact_application_accept_button:friend_123'),
      );
      expect(
        UiKeys.contactApplicationDeclineButton('friend_123'),
        const Key('contact_application_decline_button:friend_123'),
      );
      expect(
        UiKeys.contactApplicationAddWording('friend_123'),
        const Key('contact_application_addwording:friend_123'),
      );
      expect(
        UiKeys.contactNewContactsTab,
        const Key('contact_new_contacts_tab'),
      );
      expect(
        UiKeys.contactApplicationsListEmpty,
        const Key('contact_applications_list_empty'),
      );
      expect(
        UiKeys.conversationItemOnlineDot('c2c_friend_123'),
        const Key('conversation_item_online_dot:c2c_friend_123'),
      );
      expect(UiKeys.groupAddMemberButton, const Key('group_add_member_button'));
      expect(
        UiKeys.groupMemberInviteConfirmButton,
        const Key('group_member_invite_confirm_button'),
      );
      expect(
        UiKeys.groupMemberActionKickButton,
        const Key('group_member_action_kick_button'),
      );
      expect(
        UiKeys.groupInviteAcceptButton('tox_group_1'),
        const Key('group_invite_accept_button:tox_group_1'),
      );
    });
  });
}
