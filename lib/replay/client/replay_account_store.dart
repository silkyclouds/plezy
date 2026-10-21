import 'dart:convert';

import '../../media/ids.dart';
import '../../services/credential_vault.dart';
import '../auth/replay_auth.dart';
import 'replay_api_cache.dart';

/// Keeps one signed-in session per broadcaster, encrypted at rest with the app's credential vault.
class ReplayAccountStore {
  final ReplayApiCache _cache;
  final ServerId _serverId;

  ReplayAccountStore(this._cache, this._serverId);

  Future<ReplaySession?> load(String source) async {
    final row = await _cache.getAccount(_serverId, source);
    final protected = row?['v'];
    if (protected is! String) return null;
    final clear = await CredentialVault.reveal(protected);
    if (clear == null) return null;
    try {
      return ReplaySession.fromJson(jsonDecode(clear) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<void> save(String source, ReplaySession session) async {
    final protected = await CredentialVault.protect(jsonEncode(session.toJson()));
    await _cache.putAccount(_serverId, source, {'v': protected});
  }

  Future<void> delete(String source) => _cache.deleteAccount(_serverId, source);
}
