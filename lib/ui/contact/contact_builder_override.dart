import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart' as contact_pkg;
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';

/// Handle to restore contact profile builders when the page is disposed.
/// Call [capture] before applying overrides, then [restore] in dispose.
class ContactBuilderOverrideHandle {
  ContactBuilderOverrideHandle._({
    required this.originalContentBuilder,
    required this.originalStateBuilder,
    required this.originalDeleteBuilder,
  });

  final UserProfileContentBuilder originalContentBuilder;
  final UserProfileStateButtonBuilder originalStateBuilder;
  final UserProfileDeleteButtonBuilder originalDeleteBuilder;

  bool _restored = false;

  /// Captures current profile builders. Call this before [contact_pkg.TencentCloudChatContactManager.builder.setBuilders].
  static ContactBuilderOverrideHandle capture() {
    final manager = contact_pkg.TencentCloudChatContactManager.builder;
    return ContactBuilderOverrideHandle._(
      originalContentBuilder: ({required V2TimUserFullInfo userFullInfo}) =>
          manager.getUserProfileContentBuilder(userFullInfo: userFullInfo),
      originalStateBuilder: ({required V2TimUserFullInfo userFullInfo}) =>
          manager.getUserProfileStateButtonBuilder(userFullInfo: userFullInfo),
      originalDeleteBuilder: ({required V2TimUserFullInfo userFullInfo}) =>
          manager.getUserProfileDeleteButtonBuilder(userFullInfo: userFullInfo),
    );
  }

  /// Restores the captured builders. Idempotent.
  void restore() {
    if (_restored) return;
    _restored = true;
    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      userProfileContentBuilder: originalContentBuilder,
      userProfileStateButtonBuilder: originalStateBuilder,
      userProfileDeleteButtonBuilder: originalDeleteBuilder,
    );
  }
}
