import 'dart:io';

void _expectContains(String source, String needle, String label) {
  if (!source.contains(needle)) {
    throw StateError('Missing $label: $needle');
  }
}

void main() {
  final uiKeys = File('lib/ui/testing/ui_keys.dart').readAsStringSync();
  final homePageBootstrap = File(
    'lib/ui/home_page_bootstrap.dart',
  ).readAsStringSync();
  final messageRow = File(
    'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_list_view/message_row/tencent_cloud_chat_message_row_container.dart',
  ).readAsStringSync();
  final messageMenu = File(
    'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_widgets/menu/tencent_cloud_chat_message_item_with_menu.dart',
  ).readAsStringSync();
  final messageMenuContainer = File(
    'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_widgets/menu/tencent_cloud_chat_message_item_with_menu_container.dart',
  ).readAsStringSync();
  final mobileInput = File(
    'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart',
  ).readAsStringSync();
  final desktopImageTools = File(
    'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/common/for_desktop/image_tools.dart',
  ).readAsStringSync();

  _expectContains(
    uiKeys,
    "static const Key chatInputTextField = Key('chat_input_text_field')",
    'UiKeys.chatInputTextField',
  );
  _expectContains(
    uiKeys,
    "static const Key chatSendButton = Key('chat_send_button')",
    'UiKeys.chatSendButton',
  );
  _expectContains(
    homePageBootstrap,
    'key: UiKeys.chatInputTextField',
    'messageInputBuilder chat-input wrapper',
  );
  _expectContains(
    messageRow,
    "ValueKey('message_list_item:",
    'per-message row key',
  );
  _expectContains(
    messageMenu,
    "ValueKey('message_menu_item:\$action')",
    'message menu item key factory',
  );
  _expectContains(
    messageMenuContainer,
    "ValueKey('confirm_dialog_primary_button')",
    'message delete confirm primary button key',
  );
  _expectContains(
    mobileInput,
    "ValueKey('emoji_panel_button')",
    'mobile emoji panel toggle key',
  );
  _expectContains(
    desktopImageTools,
    "ValueKey('desktop_send_image_confirm_button')",
    'desktop pasted-image confirm button key',
  );
}
