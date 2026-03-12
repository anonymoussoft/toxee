import 'in_call_manager.dart';
import 'ringing_call_manager.dart';

/// Interface for [CallOverlay]: provides both in-call and ringing actions.
/// Implemented by [CallServiceManager]; tests can supply a fake.
abstract class CallOverlayManager implements InCallManager, RingingCallManager {}
