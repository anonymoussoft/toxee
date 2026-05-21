import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';

import '../../i18n/app_localizations.dart';

/// Replacement for `TencentCloudChatMessageHeaderInfo` that fixes the
/// `Expanded`-in-`MainAxisSize.min` layout bug which caused the status row to
/// get 0 height when the UIKit-supplied header was used inside our message
/// header builder.
///
/// Extracted from `lib/ui/home_page_bootstrap.dart` (was `_ToxeeMessageHeaderInfo`)
/// so it can live in its own library and be exercised directly by widget tests.
/// It has zero closure over `_HomePageState` — all data flows in through
/// constructor arguments — which is what made the extraction safe.
class ToxeeMessageHeaderInfo extends StatefulWidget {
  final bool Function({required String userID}) getUserOnlineStatus;
  final List<V2TimGroupMemberFullInfo> Function() getGroupMembersInfo;
  final String? userID;
  final String? groupID;
  final V2TimConversation? conversation;
  final bool showUserOnlineStatus;

  const ToxeeMessageHeaderInfo({
    super.key,
    required this.getUserOnlineStatus,
    required this.getGroupMembersInfo,
    this.userID,
    this.groupID,
    this.conversation,
    required this.showUserOnlineStatus,
  });

  @override
  State<ToxeeMessageHeaderInfo> createState() => _ToxeeMessageHeaderInfoState();
}

class _ToxeeMessageHeaderInfoState extends State<ToxeeMessageHeaderInfo> {
  String _getStatusText(BuildContext context) {
    final conv = widget.conversation;
    if (conv == null) return '';
    // C2C: show online/offline
    if (conv.type == 1) {
      final uid = conv.userID ?? widget.userID ?? '';
      if (uid.isNotEmpty) {
        final isOnline = widget.getUserOnlineStatus(userID: uid);
        final tL10n = TencentCloudChatLocalizations.of(context);
        final appL10n = AppLocalizations.of(context);
        return isOnline
            ? (tL10n?.online ?? appL10n?.statusOnline ?? 'Online')
            : (tL10n?.offline ?? appL10n?.statusOffline ?? 'Offline');
      }
    } else {
      // Group: show member count if > 2
      final members = widget.getGroupMembersInfo();
      if (members.length > 2) {
        final tL10n = TencentCloudChatLocalizations.of(context);
        final firstName = members[0].nickName ?? members[0].userID;
        return tL10n?.groupSubtitle(members.length, firstName) ??
            '${members.length} members';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _getStatusText(context);
    final displayName = widget.conversation?.showName ??
        widget.userID ??
        TencentCloudChatLocalizations.of(context)?.chat ??
        '';
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: textStyle.standardLargeText,
              fontWeight: FontWeight.bold,
              color: colorTheme.primaryTextColor,
              // Tight line-height: app-bar header sits inside a fixed-height
              // row, so the default body `height: 1.5` would push the two
              // stacked lines past the available vertical space.
              height: 1.15,
            ),
          ),
          if (widget.showUserOnlineStatus && statusText.isNotEmpty)
            Text(
              statusText,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: textStyle.standardSmallText,
                color: colorTheme.secondaryTextColor,
                height: 1.15,
              ),
            ),
        ],
      ),
    );
  }
}
