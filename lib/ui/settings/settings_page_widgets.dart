part of 'settings_page.dart';

class _HoverableSettingsRow extends StatefulWidget {
  const _HoverableSettingsRow({required this.child});
  final Widget child;
  @override
  State<_HoverableSettingsRow> createState() => _HoverableSettingsRowState();
}

class _HoverableSettingsRowState extends State<_HoverableSettingsRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.04);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _isHovered ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
        ),
        child: widget.child,
      ),
    );
  }
}

class _AccountCardItem extends StatefulWidget {
  const _AccountCardItem({
    required this.account,
    required this.isCurrentAccount,
    required this.colorTheme,
    required this.onSwitch,
    required this.currentChip,
    required this.subtitle,
  });
  final Map<String, String> account;
  final bool isCurrentAccount;
  final dynamic colorTheme;
  final VoidCallback onSwitch;
  final Widget currentChip;
  final Widget subtitle;

  @override
  State<_AccountCardItem> createState() => _AccountCardItemState();
}

class _AccountCardItemState extends State<_AccountCardItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accountNickname = widget.account['nickname'] ?? '';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          color: widget.isCurrentAccount
              ? widget.colorTheme.primaryColor.withValues(alpha: 0.10)
              : (_isHovered ? widget.colorTheme.primaryColor.withValues(alpha: 0.06) : null),
        ),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: widget.isCurrentAccount
                  ? widget.colorTheme.primaryColor
                  : widget.colorTheme.secondaryColor,
              child: Text(
                accountNickname.isNotEmpty
                    ? accountNickname[0].toUpperCase()
                    : 'A',
                style: TextStyle(
                  color: widget.isCurrentAccount
                      ? widget.colorTheme.onPrimary
                      : widget.colorTheme.onSecondary,
                ),
              ),
            ),
            title: Text(accountNickname.isNotEmpty ? accountNickname : 'Unnamed Account'),
            subtitle: widget.subtitle,
            trailing: widget.isCurrentAccount ? widget.currentChip : IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: widget.onSwitch,
              tooltip: AppLocalizations.of(context)!.switchToThisAccount,
            ),
          ),
        ),
      ),
    );
  }
}
