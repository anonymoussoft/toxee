/// Minimal interface for incoming/outgoing call views. Allows tests to supply a fake.
///
/// All three methods perform async work (permission checks, signaling RPCs,
/// ToxAV FFI calls). Returning `Future<void>` makes that explicit so callers
/// can `await` propagation or attach error handlers — the previous `void`
/// signatures silently dropped failures.
abstract class RingingCallManager {
  Future<void> acceptCall();
  Future<void> rejectCall();
  Future<void> hangUp();
}
