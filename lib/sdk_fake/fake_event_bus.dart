import 'dart:async';

// Minimal event bus to mimic TencentCloudChat.instance.eventBusInstance
class FakeEventBus {
  final Map<String, StreamController<dynamic>> _topicToCtrl = {};

  Stream<T> on<T>(String topic) {
    final ctrl = _topicToCtrl.putIfAbsent(topic, () => StreamController.broadcast());
    return ctrl.stream.where((e) => e is T).cast<T>();
  }

  void emit(String topic, dynamic event) {
    final ctrl = _topicToCtrl.putIfAbsent(topic, () => StreamController.broadcast());
    if (!ctrl.isClosed) ctrl.add(event);
  }

  void dispose() {
    for (final c in _topicToCtrl.values) {
      c.close();
    }
    _topicToCtrl.clear();
  }
}


