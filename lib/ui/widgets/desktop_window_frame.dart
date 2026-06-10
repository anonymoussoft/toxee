import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../util/platform_utils.dart';

const double kDesktopWindowFrameHeight = 44.0;

/// Shared desktop-only custom title bar used after the native system title bar
/// is hidden via `window_manager`.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!PlatformUtils.isDesktop) return;
    windowManager.addListener(this);
    unawaited(_refreshMaximizedState());
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _refreshMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _isMaximized = isMaximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isDesktop) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleBarColor = isDark
        ? scheme.surface.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.94);
    final titleColor = scheme.onSurface.withValues(alpha: 0.88);

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Material(
            color: titleBarColor,
            child: Container(
              height: kDesktopWindowFrameHeight,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _toggleMaximize,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Image.asset(
                                isDark
                                    ? 'assets/app_icon_white.png'
                                    : 'assets/app_icon.png',
                                width: 18,
                                height: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Toxee',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _WindowControlButton(
                    icon: Icons.remove_rounded,
                    onPressed: () => windowManager.minimize(),
                  ),
                  _WindowControlButton(
                    icon: _isMaximized
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    onPressed: _toggleMaximize,
                  ),
                  _WindowControlButton(
                    icon: Icons.close_rounded,
                    danger: true,
                    onPressed: () => windowManager.close(),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final bool danger;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = widget.danger
        ? Colors.red.withValues(alpha: _hovered ? 0.88 : 0)
        : scheme.onSurface.withValues(alpha: _hovered ? 0.09 : 0);
    final iconColor = widget.danger && _hovered
        ? Colors.white
        : scheme.onSurface.withValues(alpha: 0.84);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => unawaited(widget.onPressed()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: 46,
            height: kDesktopWindowFrameHeight,
            color: backgroundColor,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}
