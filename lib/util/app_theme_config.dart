import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/dark.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/light.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme_model.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';

/// Centralized theme configuration based on WeChat light/dark themes.
class AppThemeConfig {
  AppThemeConfig._();

  // ──────────────────────────────────────────────
  //  Light mode colors (WeChat style)
  // ──────────────────────────────────────────────

  /// Primary color - WeChat Green (light mode)
  static const Color primaryColor = Color(0xFF07C160);

  /// Secondary color - darker green for pressed/hover (light mode)
  static const Color secondaryColor = Color(0xFF06AD56);

  /// Self message bubble - WeChat green bubble (light mode)
  static const Color selfMessageBubbleColorLight = Color(0xFF95EC69);

  /// Light mode scaffold background - WeChat gray
  static const Color lightScaffoldBackground = Color(0xFFEDEDED);

  /// Light mode gradient colors for startup/login screens and desktop sidebar
  static const Color lightGradientStart = Color(0xFFEDEDED);
  static const Color lightGradientEnd = Color(0xFFE6E6E6);

  /// Primary text color (light mode) - WeChat near-black
  static const Color primaryTextColorLight = Color(0xFF111111);

  /// Secondary text color (light mode) - WeChat gray
  static const Color secondaryTextColorLight = Color(0xFF999999);

  /// Divider color (light mode) - WeChat
  static const Color dividerColorLight = Color(0xFFD9D9D9);

  // ──────────────────────────────────────────────
  //  Dark mode colors (WeChat dark style, softer for readability)
  // ──────────────────────────────────────────────

  /// Primary color for dark mode - softer green (less saturated, easier on eyes)
  static const Color primaryColorDark = Color(0xFF5BC973);

  /// Secondary color for dark mode
  static const Color secondaryColorDark = Color(0xFF4AB063);

  /// Self message bubble - darker muted green (better contrast with soft white text)
  static const Color selfMessageBubbleColorDark = Color(0xFF2E6B4F);

  /// Self message text on bubble - soft white (not pure white, more coordinated)
  static const Color selfMessageTextColorDark = Color(0xFFE5E5E5);

  /// Message status/read icon in dark - neutral gray (avoids "too green" next to bubble)
  static const Color messageStatusIconColorDark = Color(0xFF9E9E9E);

  /// Others message bubble - WeChat dark card (dark mode)
  static const Color othersMessageBubbleColorDark = Color(0xFF2C2C2C);

  /// Dark mode scaffold background - WeChat dark
  static const Color darkScaffoldBackground = Color(0xFF191919);

  /// Dark mode gradient colors for startup/login screens and desktop sidebar
  static const Color darkGradientStart = Color(0xFF1F1F1F);
  static const Color darkGradientEnd = Color(0xFF272727);

  /// Primary text color (dark mode) - WeChat
  static const Color primaryTextColorDark = Color(0xFFD1D1D1);

  /// Secondary text color (dark mode) - WeChat
  static const Color secondaryTextColorDark = Color(0xFF6B6B6B);

  /// Divider color (dark mode) - WeChat
  static const Color dividerColorDark = Color(0xFF2C2C2C);

  // ──────────────────────────────────────────────
  //  Shared colors
  // ──────────────────────────────────────────────

  /// Success/connected status color - WeChat green
  static const Color successColor = Color(0xFF07C160);

  /// Error/disconnected status color - WeChat red
  static const Color errorColor = Color(0xFFFA5151);

  // ──────────────────────────────────────────────
  //  Border radii (WeChat uses tighter radii)
  // ──────────────────────────────────────────────

  /// Standard border radius for cards
  static const double cardBorderRadius = 12.0;

  /// Border radius for buttons
  static const double buttonBorderRadius = 8.0;

  /// Border radius for input fields
  static const double inputBorderRadius = 8.0;

  /// Border radius for main form cards (e.g. login form)
  static const double formCardBorderRadius = 12.0;

  /// Border radius for badges (e.g. unread count)
  static const double badgeBorderRadius = 8.0;

  /// Creates a TencentCloudChatThemeModel based on WeChat light/dark themes.
  static TencentCloudChatThemeModel createYouthfulThemeModel() {
    return TencentCloudChatThemeModel(
      lightTheme: LightTencentCloudChatColors(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        secondButtonColor: primaryColor,
        primaryTextColor: primaryTextColorLight,
        backgroundColor: const Color(0xFFFFFFFF),
        surface: lightScaffoldBackground,
        secondaryTextColor: secondaryTextColorLight,
        dividerColor: dividerColorLight,
        tipsColor: errorColor,
        othersMessageBubbleBorderColor: dividerColorLight,
        contactItemTabItemNameColor: const Color(0x99999999),
        appBarBackgroundColor: lightScaffoldBackground,
        appBarIconColor: primaryTextColorLight,
        firstButtonColor: primaryColor,
        switchActivatedColor: primaryColor,
        contactBackButtonColor: primaryColor,
        contactAppBarIconColor: primaryColor,
        contactAgreeButtonColor: primaryColor,
        settingInfoEditColor: primaryColor,
        groupProfileAddMemberTextColor: primaryColor,
        conversationItemSendingIconColor: primaryColor,
        conversationItemMoreActionItemNormalTextColor: primaryColor,
        conversationItemSwipeActionOneBgColor: primaryColor,
        conversationItemNormalBgColor: lightScaffoldBackground,
        conversationItemIsPinedBgColor: lightScaffoldBackground,
        conversationItemShowNameTextColor: primaryTextColorLight,
        conversationItemLastMessageTextColor: const Color(0xFF999999),
        conversationItemTimeTextColor: const Color(0xFF999999),
        conversationNoConversationTextColor: const Color(0xFF999999),
        messageStatusIconColor: primaryColor,
        // Message bubbles - WeChat style
        selfMessageBubbleColor: selfMessageBubbleColorLight,
        selfMessageTextColor: const Color(0xFF000000),
        othersMessageBubbleColor: Colors.white,
        othersMessageTextColor: const Color(0xFF000000),
        // Desktop gradient (empty page, sidebar)
        desktopBackgroundColorLinearGradientOne: lightGradientStart,
        desktopBackgroundColorLinearGradientTwo: lightGradientEnd,
        // Settings
        settingBackgroundColor: lightScaffoldBackground,
        settingTitleColor: const Color(0xFF111111),
        settingTabBackgroundColor: lightScaffoldBackground,
        // Contacts
        contactTabItemBackgroundColor: lightScaffoldBackground,
        contactItemFriendNameColor: const Color(0xFF111111),
        contactSearchBackgroundColor: const Color(0xFFFFFFFF),
        contactBackgroundColor: lightScaffoldBackground,
      ),
      darkTheme: DarkTencentCloudChatColors(
        primaryColor: primaryColorDark,
        secondaryColor: secondaryColorDark,
        onPrimary: const Color(0xFF121212),
        onSecondary: const Color(0xFF121212),
        secondButtonColor: primaryColorDark,
        primaryTextColor: primaryTextColorDark,
        backgroundColor: darkScaffoldBackground,
        surface: const Color(0xFF2C2C2C),
        secondaryTextColor: secondaryTextColorDark,
        dividerColor: dividerColorDark,
        tipsColor: errorColor,
        othersMessageBubbleBorderColor: dividerColorDark,
        contactItemTabItemNameColor: const Color(0xCC6B6B6B),
        appBarBackgroundColor: const Color(0xFF1F1F1F),
        appBarIconColor: primaryTextColorDark,
        firstButtonColor: primaryColorDark,
        switchActivatedColor: primaryColorDark,
        contactBackButtonColor: primaryColorDark,
        contactAppBarIconColor: primaryColorDark,
        contactAgreeButtonColor: primaryColorDark,
        settingInfoEditColor: primaryColorDark,
        groupProfileAddMemberTextColor: primaryColorDark,
        conversationItemSendingIconColor: primaryColorDark,
        conversationItemMoreActionItemNormalTextColor: primaryColorDark,
        conversationItemSwipeActionOneBgColor: primaryColorDark,
        conversationItemNormalBgColor: darkScaffoldBackground,
        conversationItemIsPinedBgColor: darkScaffoldBackground,
        conversationItemShowNameTextColor: primaryTextColorDark,
        conversationItemLastMessageTextColor: const Color(0xFF6B6B6B),
        conversationItemTimeTextColor: const Color(0xFF6B6B6B),
        conversationNoConversationTextColor: const Color(0xFF6B6B6B),
        messageStatusIconColor: messageStatusIconColorDark,
        // Message bubbles - WeChat dark style (muted green + soft white text)
        selfMessageBubbleColor: selfMessageBubbleColorDark,
        selfMessageTextColor: selfMessageTextColorDark,
        othersMessageBubbleColor: othersMessageBubbleColorDark,
        othersMessageTextColor: const Color(0xFFD1D1D1),
        // Desktop gradient
        desktopBackgroundColorLinearGradientOne: darkGradientStart,
        desktopBackgroundColorLinearGradientTwo: darkGradientEnd,
        // Settings
        settingBackgroundColor: darkScaffoldBackground,
        settingTitleColor: const Color(0xFFD1D1D1),
        settingTabBackgroundColor: darkScaffoldBackground,
        // Contacts
        contactTabItemBackgroundColor: const Color(0xFF2C2C2C),
        contactItemFriendNameColor: const Color(0xFFD1D1D1),
        contactSearchBackgroundColor: const Color(0xFF2C2C2C),
        contactBackgroundColor: darkScaffoldBackground,
      ),
      textStyle: TencentCloudChatTextStyle(
        navigationTitle: 20,
        contactTitle: 18,
        messageBody: 14,
        messageSnippet: 16,
        buttonLabel: 16,
        standardText: 14,
        standardLargeText: 16,
        standardSmallText: 12,
      ),
    );
  }
}
