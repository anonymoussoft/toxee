import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../testing/ui_keys.dart';

/// New entry button widget (Add Friend / Create Group / Join IRC Channel)
class NewEntryButton extends StatefulWidget {
  const NewEntryButton({
    super.key,
    required this.onAddFriend,
    required this.onCreateGroup,
    this.onJoinIrcChannel,
  });
  final Future<void> Function() onAddFriend;
  final Future<void> Function() onCreateGroup;
  final Future<void> Function()? onJoinIrcChannel;

  @override
  State<NewEntryButton> createState() => _NewEntryButtonState();
}

class _NewEntryButtonState extends State<NewEntryButton> {
  final GlobalKey<PopupMenuButtonState<String>> _menuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  bool _hovered = false;

  PopupMenuItem<String> _menuItem({
    required BuildContext context,
    required String value,
    required IconData icon,
    required String label,
    Key? key,
  }) {
    final theme = Theme.of(context);
    return PopupMenuItem<String>(
      key: key,
      value: value,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label, style: theme.textTheme.bodyLarge),
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tL10n = TencentCloudChatLocalizations.of(context);
    return PopupMenuButton<String>(
      key: _menuKey,
      // Open the menu *below* the button (anchor at the button's bottom
      // edge) instead of Flutter's default `PopupMenuPosition.over` which
      // places the first menu item on top of the button — that made the
      // pill visually disappear behind the menu the moment it opened, and
      // looked like the button "ate itself" (see sc_01.png).
      position: PopupMenuPosition.under,
      // Hover/long-press tooltip — surfaced on desktop hover and assistive
      // tech. AppLocalizations key is authoritative; falls back to UIKit's
      // newChat string when AppLocalizations isn't ready yet.
      tooltip:
          AppLocalizations.of(context)?.newConversationTooltip ??
          tL10n?.newChat ??
          'New conversation',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      elevation: 2,
      itemBuilder: (context) => [
        _menuItem(
          context: context,
          value: 'add',
          icon: Icons.person_add_alt,
          label: tL10n?.addContact ?? 'Add Contact',
          key: UiKeys.newEntryAddContactItem,
        ),
        _menuItem(
          context: context,
          value: 'group',
          icon: Icons.group_add,
          label: tL10n?.createGroupChat ?? 'Create Group',
          key: UiKeys.newEntryCreateGroupItem,
        ),
        if (widget.onJoinIrcChannel != null)
          _menuItem(
            context: context,
            value: 'irc',
            icon: Icons.chat_bubble_outline,
            label: appL10n?.joinIrcChannel ?? 'Join IRC Channel',
            key: UiKeys.newEntryJoinIrcItem,
          ),
      ],
      onSelected: (v) async {
        if (v == 'add') {
          await widget.onAddFriend();
        } else if (v == 'group') {
          await widget.onCreateGroup();
        } else if (v == 'irc' && widget.onJoinIrcChannel != null) {
          await widget.onJoinIrcChannel!();
        }
      },
      // Single gesture owner: PopupMenuButton handles the tap directly via
      // Material + InkWell. Previously an inner OutlinedButton.onPressed
      // raced with PopupMenuButton's own tap detector — two gesture owners
      // on the same surface. Visual treatment (outlined pill, primary
      // border, icon+label) is preserved.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: UiKeys.newEntryMenuButton,
            borderRadius: BorderRadius.circular(14),
            onTap: () => _menuKey.currentState?.showButtonMenu(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(
                      alpha: _hovered ? 0.2 : 0.14,
                    ),
                    theme.colorScheme.primary.withValues(
                      alpha: _hovered ? 0.11 : 0.07,
                    ),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(
                    alpha: _hovered ? 0.5 : 0.32,
                  ),
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _hovered ? 0.14 : 0.08,
                    ),
                    blurRadius: _hovered ? 20 : 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(
                        AppThemeConfig.buttonBorderRadius,
                      ),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    tL10n?.newChat ?? 'New',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: theme.colorScheme.primary.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
