/// Minimal interface for incoming/outgoing call views. Allows tests to supply a fake.
abstract class RingingCallManager {
  void acceptCall();
  void rejectCall();
  void hangUp();
}
