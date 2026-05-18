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
    // A9: forward to FakeConversationManager which clears the underlying
    // history and emits a refresh so the UI updates immediately instead
    // of waiting for the 5s poll to re-emit the conversation.
    await _conversationManager.deleteConversation(conversationID);
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

