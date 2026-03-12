import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import 'call_audio_platform.dart';
import 'call_state_notifier.dart';
import 'call_media_capabilities.dart';
import 'call_ui_shell.dart';
import 'call_ui_components.dart';
import 'in_call_manager.dart';

/// Full-screen in-call UI using shared shell: top bar, video/identity stage, action dock.
class InCallView extends StatelessWidget {
  const InCallView({
    super.key,
    required this.callState,
    required this.manager,
  });

  final CallStateNotifier callState;
  final InCallManager manager;

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        callState.remoteNickname ?? callState.remoteUserID ?? l10n.unknown;
    final isVideo = callState.mode == CallMode.video;
    final screenSize = MediaQuery.sizeOf(context);
    final shortSide = min(screenSize.width, screenSize.height);
    final avatarRadius = (shortSide * 0.12).clamp(36.0, 80.0);
    final avatarFontSize = avatarRadius * 0.8;

    return CallSceneShell(
      topBar: CallTopStatusBar(
        key: const ValueKey('call-top-bar'),
        title: name,
        subtitle: _formatDuration(callState.callDuration),
        qualityIndicator: _buildQualityIndicator(context, l10n),
        trailingIcon: Icons.picture_in_picture_alt,
        onTrailingPressed: () => callState.minimize(),
      ),
      bottomBar: CallActionDock(
        key: const ValueKey('call-action-dock'),
        actions: _buildDockActions(context, l10n, isVideo),
      ),
      child: isVideo
          ? CallVideoStage(
              remoteContent: _buildRemoteContent(l10n),
              localPreviewCard: _buildLocalPreviewCard(l10n, shortSide),
            )
          : CallIdentityStage(
              avatar: _buildAvatar(name, avatarRadius, avatarFontSize),
              title: name,
              subtitle: _formatDuration(callState.callDuration),
            ),
    );
  }

  Widget? _buildQualityIndicator(BuildContext context, AppLocalizations l10n) {
    final quality = callState.callQuality;
    if (quality == CallQuality.unknown) return null;
    final label = switch (quality) {
      CallQuality.good => l10n.callQualityGood,
      CallQuality.medium => l10n.callQualityMedium,
      CallQuality.poor => l10n.callQualityPoor,
      CallQuality.unknown => null,
    };
    if (label == null) return null;
    return Semantics(
      label: l10n.callQualityLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
      ),
    );
  }

  List<CallDockAction> _buildDockActions(
      BuildContext context, AppLocalizations l10n, bool isVideo) {
    final showSpeakerToggle = CallMediaCapabilities.supportsSpeakerToggle();
    final actions = <CallDockAction>[
      CallDockAction(
        icon: callState.isMuted ? Icons.mic_off : Icons.mic,
        label: callState.isMuted ? l10n.callUnmute : l10n.callMute,
        selected: callState.isMuted,
        onPressed: () => manager.toggleMute(),
      ),
      if (isVideo)
        CallDockAction(
          icon: callState.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
          label:
              callState.isVideoEnabled ? l10n.callVideoOff : l10n.callVideoOn,
          selected: !callState.isVideoEnabled,
          onPressed: () => manager.toggleVideo(),
        ),
      if (!showSpeakerToggle &&
          CallMediaCapabilities.supportsAudioRouteSelection())
        CallDockAction(
          icon: Icons.route,
          label: l10n.routeSelection,
          onPressed: () => _showAudioRouteSheet(context, l10n),
        ),
      CallDockAction(
        icon: Icons.call_end,
        label: l10n.callHangUp,
        destructive: true,
        onPressed: () => manager.hangUp(),
      ),
    ];
    return actions;
  }

  void _showAudioRouteSheet(BuildContext context, AppLocalizations l10n) {
    final state = manager.audioState.value;
    if (!state.canSelectRoutes) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  l10n.routeSelection,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final route in state.routes)
                ListTile(
                  leading: Icon(_iconForRoute(route.kind)),
                  title: Text(route.label),
                  trailing:
                      route.selected ? const Icon(Icons.check, size: 20) : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await manager.selectAudioRoute(route.id);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForRoute(CallAudioRouteKind? kind) {
    switch (kind) {
      case CallAudioRouteKind.speaker:
        return Icons.speaker_phone;
      case CallAudioRouteKind.bluetooth:
        return Icons.bluetooth_audio;
      case CallAudioRouteKind.wired:
        return Icons.headset;
      case CallAudioRouteKind.earpiece:
        return Icons.phone_in_talk;
      case CallAudioRouteKind.unknown:
      case null:
        return Icons.route;
    }
  }

  Widget _buildRemoteContent(AppLocalizations l10n) {
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: manager.remoteVideo,
      builder: (context, image, _) {
        if (image != null) {
          return RawImage(image: image, fit: BoxFit.contain);
        }
        return Center(
          child: Container(
            color: Colors.black26,
            child: Center(
              child: Text(l10n.callRemoteVideo,
                  style: const TextStyle(color: Colors.white54)),
            ),
          ),
        );
      },
    );
  }

  Widget? _buildLocalPreviewCard(AppLocalizations l10n, double shortSide) {
    final previewWidth = (shortSide * 0.35).clamp(120.0, 280.0);
    final previewHeight = previewWidth * 4 / 3;
    return ListenableBuilder(
      listenable: manager.previewListenable,
      builder: (context, _) {
        final preview = manager.localPreview;
        return Positioned(
          top: 16,
          right: 16,
          child: KeyedSubtree(
            key: const ValueKey('call-local-preview-card'),
            child: Container(
              width: previewWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: preview ??
                    const ColoredBox(
                      color: Color(0xFF2C2C2E),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String name, double radius, double fontSize) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 8,
          ),
        ],
      ),
      child: CallUserAvatar(
        userId: callState.remoteUserID,
        name: name,
        radius: radius,
        fontSize: fontSize,
      ),
    );
  }
}
