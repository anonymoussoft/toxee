import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import 'friend_request_display_name.dart';

class ContactApplicationItemContentOverride extends StatelessWidget {
  const ContactApplicationItemContentOverride({
    super.key,
    required this.application,
  });

  final V2TimFriendApplication application;

  bool get _hasNickname {
    return _displayName != application.userID;
  }

  String get _displayName {
    return resolveFriendRequestDisplayName(
      userId: application.userID,
      nickname: application.nickname,
      wording: application.addWording,
    );
  }

  String get _addWording => application.addWording?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: textStyle.fontsize_14,
                  fontWeight: FontWeight.w600,
                  color: colorTheme.contactItemFriendNameColor,
                ),
              ),
              if (_hasNickname) ...[
                const SizedBox(height: 2),
                Text(
                  application.userID,
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: textStyle.fontsize_12,
                    color: colorTheme.secondaryTextColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
              if (_addWording.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _addWording,
                  key: ValueKey(
                    'contact_application_addwording:${application.userID}',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorTheme.contactItemTabItemNameColor,
                    fontSize: textStyle.fontsize_12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
