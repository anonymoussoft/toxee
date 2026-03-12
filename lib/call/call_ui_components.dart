import 'dart:io' show File;

import 'package:flutter/material.dart';
import '../util/responsive_layout.dart';
import 'call_avatar_controller.dart';
import 'call_ui_shell.dart';

/// Returns the first character of [name] for avatar display (uppercase for a–z).
/// Uses [String.characters] so emoji and CJK work correctly.
String callAvatarInitial(String name) {
  if (name.isEmpty) return '?';
  final first = name.characters.first;
  if (first.length == 1) {
    final code = first.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) return first.toUpperCase();
  }
  return first;
}

/// Avatar for call screens: loads real user image from [Prefs.getFriendAvatarPath]
/// when [userId] is set, otherwise shows [callAvatarInitial(name)].
class CallUserAvatar extends StatefulWidget {
  const CallUserAvatar({
    super.key,
    this.userId,
    this.controller,
    required this.name,
    required this.radius,
    required this.fontSize,
  });

  final String? userId;
  final CallAvatarController? controller;
  final String name;
  final double radius;
  final double fontSize;

  @override
  State<CallUserAvatar> createState() => _CallUserAvatarState();
}

class _CallUserAvatarState extends State<CallUserAvatar> {
  late final CallAvatarController _ownedController;
  late CallAvatarController _controller;

  @override
  void initState() {
    super.initState();
    _ownedController = CallAvatarController();
    _bindController(widget.controller ?? _ownedController);
    _controller.loadForUser(widget.userId);
  }

  void _bindController(CallAvatarController controller) {
    _controller = controller;
    _controller.addListener(_onControllerChanged);
  }

  void _unbindController() {
    _controller.removeListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(CallUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController = widget.controller ?? _ownedController;
    if (!identical(oldWidget.controller ?? _ownedController, nextController)) {
      _unbindController();
      _bindController(nextController);
    }
    if (oldWidget.userId != widget.userId) {
      _controller.loadForUser(widget.userId);
    }
  }

  @override
  void dispose() {
    _unbindController();
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = _controller.avatarPath;
    final hasImage = _controller.hasAvatarImage;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Colors.grey.shade700,
      backgroundImage: hasImage && path != null ? FileImage(File(path)) : null,
      child: hasImage
          ? null
          : Text(
              callAvatarInitial(widget.name),
              style: TextStyle(
                fontSize: widget.fontSize,
                color: Colors.white,
              ),
            ),
    );
  }
}

/// Descriptor for a single action in the call dock.
class CallDockAction {
  const CallDockAction({
    required this.icon,
    required this.label,
    this.destructive = false,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool destructive;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
}

/// Thin top status bar for call screens: title, subtitle, optional trailing action.
class CallTopStatusBar extends StatelessWidget {
  const CallTopStatusBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.qualityIndicator,
    this.trailingIcon,
    this.onTrailingPressed,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? qualityIndicator;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingPressed;

  @override
  Widget build(BuildContext context) {
    final fontSize = ResponsiveLayout.responsiveFontSize(context);
    final padding = ResponsiveLayout.responsiveHorizontalPadding(context);
    const softWhite = Color(0xFFE8E8E8);
    const mutedGray = Color(0xFF9CA3AF);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, SizedBox(width: padding)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: softWhite,
                    fontSize: 16 * fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: mutedGray,
                      fontSize: 13 * fontSize,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (qualityIndicator != null) ...[
            qualityIndicator!,
            SizedBox(width: padding),
          ],
          if (trailingIcon != null)
            IconButton(
              icon: Icon(trailingIcon, color: mutedGray, size: 24),
              onPressed: onTrailingPressed,
            ),
        ],
      ),
    );
  }
}

/// Action dock for call controls: mute, video, speaker, hang up.
class CallActionDock extends StatelessWidget {
  const CallActionDock({
    super.key,
    required this.actions,
  });

  final List<CallDockAction> actions;

  @override
  Widget build(BuildContext context) {
    final fontSize = ResponsiveLayout.responsiveFontSize(context);
    const mutedGray = Color(0xFF9CA3AF);
    const softWhite = Color(0xFFE8E8E8);
    const destructiveRed = Color(0xFFDC2626);
    const dockSurface = Color(0xFF20242A);
    const selectedSurface = Color(0xFF2C3440);
    const selectedBlue = Color(0xFFD7E3F4);
    const borderColor = Color(0xFF2F3640);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: dockSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: actions.map((a) {
          final isDestructive = a.destructive;
          final isSelected = a.selected && !isDestructive;
          final isEnabled = a.enabled && a.onPressed != null;
          final foregroundColor = isDestructive
              ? destructiveRed
              : isSelected
                  ? selectedBlue
                  : isEnabled
                      ? mutedGray
                      : mutedGray.withValues(alpha: 0.45);
          final labelColor = isDestructive
              ? softWhite
              : isSelected
                  ? selectedBlue
                  : foregroundColor;
          final buttonColor = isDestructive
              ? destructiveRed
              : isSelected
                  ? selectedSurface
                  : Colors.transparent;

          return SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: buttonColor,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: Icon(
                      a.icon,
                      color: isDestructive ? Colors.white : foregroundColor,
                      size: 24,
                    ),
                    onPressed: isEnabled ? a.onPressed : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11 * fontSize,
                    fontWeight: isSelected || isDestructive
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Centered identity stage for audio-only or ringing: avatar, title, subtitle.
class CallIdentityStage extends StatelessWidget {
  const CallIdentityStage({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.secondaryNote,
  });

  final Widget avatar;
  final String title;
  final String? subtitle;
  final String? secondaryNote;

  @override
  Widget build(BuildContext context) {
    const softWhite = Color(0xFFE8E8E8);
    const mutedGray = Color(0xFF9CA3AF);
    final fontSize = ResponsiveLayout.responsiveFontSize(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: softWhite,
              fontSize: 20 * fontSize,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(color: mutedGray, fontSize: 14 * fontSize),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (secondaryNote != null && secondaryNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secondaryNote!,
              style: TextStyle(color: mutedGray, fontSize: 12 * fontSize),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Video stage: remote content area and optional local preview card with stable key.
class CallVideoStage extends StatelessWidget {
  const CallVideoStage({
    super.key,
    required this.remoteContent,
    this.localPreviewCard,
  });

  final Widget remoteContent;
  final Widget? localPreviewCard;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        remoteContent,
        if (localPreviewCard != null) localPreviewCard!,
      ],
    );
  }
}

/// Compact card for floating call window: title, subtitle, optional leading, hang-up action.
class CallCompactCard extends StatelessWidget {
  const CallCompactCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.thumbnail,
    required this.onHangUp,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? thumbnail;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    const softWhite = Color(0xFFE8E8E8);
    const mutedGray = Color(0xFF9CA3AF);
    const destructiveRed = Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          if (thumbnail != null && leading == null) ...[
            thumbnail!,
            const SizedBox(width: 8)
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: softWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: mutedGray, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onHangUp,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: destructiveRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_end,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RingingCallScene extends StatelessWidget {
  const RingingCallScene({
    super.key,
    required this.userId,
    required this.name,
    required this.primarySubtitle,
    this.secondaryNote,
    required this.bottomBar,
    required this.onMinimize,
    required this.avatarRadius,
    required this.avatarFontSize,
  });

  final String? userId;
  final String name;
  final String primarySubtitle;
  final String? secondaryNote;
  final Widget bottomBar;
  final VoidCallback onMinimize;
  final double avatarRadius;
  final double avatarFontSize;

  @override
  Widget build(BuildContext context) {
    return CallSceneShell(
      topBar: CallTopStatusBar(
        key: const ValueKey('call-top-bar'),
        title: name,
        subtitle: primarySubtitle,
        trailingIcon: Icons.picture_in_picture_alt,
        onTrailingPressed: onMinimize,
      ),
      bottomBar: bottomBar,
      child: CallIdentityStage(
        avatar: CallUserAvatar(
          userId: userId,
          name: name,
          radius: avatarRadius,
          fontSize: avatarFontSize,
        ),
        title: name,
        subtitle: primarySubtitle,
        secondaryNote: secondaryNote,
      ),
    );
  }
}
