import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/bootstrap_service.dart';

/// Adapter that implements BootstrapService using SharedPreferences
class BootstrapNodesAdapter implements BootstrapService {
  final SharedPreferences _prefs;
  
  static const _kCurrentBootstrapHost = 'current_bootstrap_host';
  static const _kCurrentBootstrapPort = 'current_bootstrap_port';
  static const _kCurrentBootstrapPubkey = 'current_bootstrap_pubkey';
  
  BootstrapNodesAdapter(this._prefs);
  
  @override
  Future<String?> getBootstrapHost() async {
    return _prefs.getString(_kCurrentBootstrapHost);
  }
  
  @override
  Future<int?> getBootstrapPort() async {
    return _prefs.getInt(_kCurrentBootstrapPort);
  }
  
  @override
  Future<String?> getBootstrapPublicKey() async {
    return _prefs.getString(_kCurrentBootstrapPubkey);
  }
  
  @override
  Future<void> setBootstrapNode({
    required String host,
    required int port,
    required String publicKey,
  }) async {
    await _prefs.setString(_kCurrentBootstrapHost, host);
    await _prefs.setInt(_kCurrentBootstrapPort, port);
    await _prefs.setString(_kCurrentBootstrapPubkey, publicKey);
  }
}

