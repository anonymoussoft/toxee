import 'package:flutter/foundation.dart';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../runtime/session_runtime_coordinator.dart';
import '../../util/disposable_bag.dart';
import '../contact/contact_builder_override.dart';

/// Controller for [HomePage]: session runtime init and optional resource bag.
/// Call [initialize] after creation; call [dispose] when the page is disposed.
class HomePageController extends ChangeNotifier {
  HomePageController({required this.service});

  final FfiChatService service;
  final DisposableBag _bag = DisposableBag();
  ContactBuilderOverrideHandle? _contactBuilderOverride;

  bool _initialized = false;
  bool _disposed = false;

  /// Ensures session runtime is initialized. Idempotent.
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await SessionRuntimeCoordinator(service: service).ensureInitialized();
  }

  /// Apply contact builder override; restored in [dispose].
  void setContactBuilderOverride(ContactBuilderOverrideHandle handle) {
    if (_disposed) return;
    _contactBuilderOverride = handle;
    _bag.add(() => _contactBuilderOverride?.restore());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _contactBuilderOverride?.restore();
    _contactBuilderOverride = null;
    _bag.dispose();
    super.dispose();
  }
}
