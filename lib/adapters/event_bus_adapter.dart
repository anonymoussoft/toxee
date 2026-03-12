import 'package:tim2tox_dart/interfaces/event_bus.dart';
import 'package:tim2tox_dart/interfaces/event_bus_provider.dart';
import '../sdk_fake/fake_event_bus.dart';

/// Adapter that implements EventBusProvider using FakeEventBus
class EventBusAdapter implements EventBusProvider {
  final FakeEventBus _eventBus;
  
  EventBusAdapter(this._eventBus);
  
  @override
  EventBus get eventBus => _EventBusWrapper(_eventBus);
}

/// Wrapper to adapt FakeEventBus to EventBus interface
class _EventBusWrapper implements EventBus {
  final FakeEventBus _fakeEventBus;
  
  _EventBusWrapper(this._fakeEventBus);
  
  @override
  Stream<T> on<T>(String topic) {
    return _fakeEventBus.on<T>(topic);
  }
  
  @override
  void emit<T>(String topic, T event) {
    _fakeEventBus.emit(topic, event);
  }
}

