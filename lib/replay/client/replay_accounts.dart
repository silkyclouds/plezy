import 'dart:async';

import '../../utils/app_logger.dart';
import '../auth/replay_auth.dart';
import '../provider/replay_provider.dart';
import 'replay_account_store.dart';

/// Signs the user in and out of the broadcasters that have accounts, and hands each provider its session.
class ReplayAccounts {
  final Map<String, ReplayProvider> _providers;
  final ReplayAccountStore _store;
  final Map<String, ReplaySession> _sessions = {};

  ReplayAccounts(this._providers, this._store);

  bool supportsAccount(String source) => _providers[source] is ReplayAccountSupport;

  /// The account the user is signed in as, or null when signed out or when the source has no accounts.
  String? accountLabel(String source) => _sessions[source]?.accountLabel;

  /// Loads stored sessions into the providers, refreshing expired ones. A session that cannot be
  /// refreshed is dropped so the user is asked to sign in again instead of failing at playback.
  Future<void> restore({DateTime? now}) async {
    final at = now ?? DateTime.now();
    for (final entry in _providers.entries) {
      final ReplayAccountSupport provider;
      switch (entry.value) {
        case final ReplayAccountSupport account:
          provider = account;
        default:
          continue;
      }
      final stored = await _store.load(entry.key);
      if (stored == null) continue;
      try {
        provider.onSessionRenewed = (renewed) => _remember(entry.key, renewed);
        final session = stored.isExpiredAt(at) ? await provider.authenticator.refresh(stored) : stored;
        provider.useSession(session);
        _sessions[entry.key] = session;
        if (!identical(session, stored)) await _store.save(entry.key, session);
      } on ReplayAuthException catch (e) {
        if (e.reason == ReplayAuthFailure.network || e.reason == ReplayAuthFailure.rateLimited) {
          // Offline or throttled at launch: keep the stored session, the provider renews it when it can.
          provider.useSession(stored);
          _sessions[entry.key] = stored;
          continue;
        }
        appLogger.w('Catch-up TV session for ${entry.key} dropped', error: e.reason.name);
        provider.onSessionRenewed = null;
        await _store.delete(entry.key);
      }
    }
  }

  Future<void> signIn(String source, {required String login, required String password}) async {
    final provider = _providers[source];
    if (provider is! ReplayAccountSupport) throw ArgumentError.value(source, 'source', 'has no account support');
    final account = provider as ReplayAccountSupport;
    final session = await account.authenticator.signIn(login: login, password: password);
    account.onSessionRenewed = (renewed) => _remember(source, renewed);
    account.useSession(session);
    _sessions[source] = session;
    await _store.save(source, session);
  }

  Future<void> signOut(String source) async {
    final provider = _providers[source];
    if (provider is ReplayAccountSupport) {
      final account = provider as ReplayAccountSupport;
      account.onSessionRenewed = null;
      account.useSession(null);
    }
    _sessions.remove(source);
    await _store.delete(source);
  }

  void _remember(String source, ReplaySession session) {
    _sessions[source] = session;
    unawaited(_store.save(source, session));
  }
}
