import 'package:tim2tox_dart/interfaces/conversation_manager_provider.dart';
import 'package:tim2tox_dart/models/fake_models.dart' as framework_models;
import '../sdk_fake/fake_managers.dart';

/// Adapter that implements ConversationManagerProvider using FakeConversationManager
class ConversationManagerAdapter implements ConversationManagerProvider {
  final FakeConversationManager _conversationManager;
  
  ConversationManagerAdapter(this._conversationManager);
  
  @override
  Future<List<framework_models.FakeConversation>> getConversationList() async {
    final clientConvs = await _conversationManager.getConversationList();
    // Convert client FakeConversation to framework FakeConversation
    return clientConvs.map((conv) => framework_models.FakeConversation(
      conversationID: conv.conversationID,
      title: conv.title,
      faceUrl: conv.faceUrl,
      unreadCount: conv.unreadCount,
      isGroup: conv.isGroup,
      isPinned: conv.isPinned,
    )).toList();
  }
  
  @override
  Future<void> setPinned(String conversationID, bool isPinned) async {
    await _conversationManager.setPinned(conversationID, isPinned);
  }
  
  @override
  Future<void> deleteConversation(String conversationID) async {
    // FakeConversationManager doesn't have deleteConversation method
    // This should be handled by clearing messages
    // For now, we'll do nothing as the original implementation also didn't have this
  }
  
  @override
  Future<int> getTotalUnreadCount() async {
    final conversations = await getConversationList();
    int total = 0;
    for (final conv in conversations) {
      total += conv.unreadCount;
    }
    return total;
  }
}

