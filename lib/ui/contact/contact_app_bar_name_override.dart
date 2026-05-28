import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

import '../../util/responsive_layout.dart';

/// Title-only replacement for UIKit's `TencentCloudChatContactAppBarName`.
///
/// The upstream widget renders the contacts-tab title alongside a
/// `MenuAnchor` + `Icons.maps_ugc_outlined` IconButton that opens the
/// Tencent-IM "Add Contact" / "Add Group" sheets (search by userID).
/// Those flows are broken on Tox, and toxee already overlays its own
/// `NewEntryButton` (Tox-aware: Add Contact via Tox ID/QR, Create Group,
/// Join IRC Channel) on the contacts page. This widget renders only the
/// title text — the icon is intentionally suppressed so the toxee overlay
/// is the only "new chat" affordance on screen.
///
/// Styling matches the upstream `TencentCloudChatContactAppBarName`
/// `defaultBuilder` / `desktopBuilder` paths: same color
/// (`colorTheme.contactItemFriendNameColor`), same weight (`w600`), and
/// roughly the same font size per breakpoint (`textStyle.fontsize_34` on
/// mobile, `textStyle.fontsize_24 + 4` on desktop).
class ContactAppBarNameOverride extends StatelessWidget {
  const ContactAppBarNameOverride({
    super.key,
    this.title,
    this.trailing,
  });

  final String? title;

  /// Optional trailing widget rendered after the title. toxee uses this slot
  /// for [NewEntryButton] (the "+ New Chat" pill), placing it inside the
  /// AppBar instead of overlaying it as a floating `Positioned` child of
  /// `TencentCloudChatContact`. Anchoring the button inside the AppBar gives
  /// the popup menu room to open *below* the button instead of covering it.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final localizations = TencentCloudChatLocalizations.of(context);
        final effectiveTitle = title ?? localizations?.contacts ?? '';
        final isDesktop = ResponsiveLayout.isDesktop(context);
        final fontSize =
            isDesktop ? textStyle.fontsize_24 + 4 : textStyle.fontsize_34;
        return Row(
          children: [
            Expanded(
              child: Text(
                effectiveTitle,
                style: TextStyle(
                  color: colorTheme.contactItemFriendNameColor,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}
