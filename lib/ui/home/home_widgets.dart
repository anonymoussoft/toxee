import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../i18n/app_localizations.dart';

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
  final GlobalKey<PopupMenuButtonState<String>> _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: _menuKey,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'add',
          child: ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: Text(TencentCloudChatLocalizations.of(context)?.addContact ?? 'Add Contact'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'group',
          child: ListTile(
            leading: const Icon(Icons.group_add),
            title: Text(TencentCloudChatLocalizations.of(context)?.createGroupChat ?? 'Create Group'),
          ),
        ),
        if (widget.onJoinIrcChannel != null)
          PopupMenuItem<String>(
            value: 'irc',
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(appL10n?.joinIrcChannel ?? 'Join IRC Channel'),
            ),
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
      child: SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: Text(TencentCloudChatLocalizations.of(context)?.newChat ?? 'New'),
          onPressed: () => _menuKey.currentState?.showButtonMenu(),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

