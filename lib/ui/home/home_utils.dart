import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../util/app_theme_config.dart';
import '../../util/qr_card_generator.dart';

/// Generate composite contact card (avatar + nickname + QR + caption)
Future<String> generateContactCardImage({
  required String userId,
  required String displayName,
  required Locale locale,
  required String bottomText,
  Color primaryColor = AppThemeConfig.primaryColor,
  Color textColor = AppThemeConfig.primaryTextColorLight,
  String? avatarPath,
}) {
  return ContactQrCardGenerator.generateTempCard(
    userId: userId,
    displayName: displayName,
    locale: locale,
    bottomText: bottomText,
    primaryColor: primaryColor,
    textColor: textColor,
    avatarPath: avatarPath,
  );
}

/// Prompt user for text input
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? actionLabel,
}) async {
  final controller = TextEditingController();
  String? result;
  await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius)),
        ),
        minLines: 1,
        maxLines: 3,
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TencentCloudChatLocalizations.of(context)?.cancel ?? 'Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                result = controller.text;
                Navigator.pop(context);
              },
              child: Text(actionLabel ?? (TencentCloudChatLocalizations.of(context)?.tuiEmojiOk ?? 'OK')),
            ),
          ],
        ),
      ],
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
  );
  return result;
}

