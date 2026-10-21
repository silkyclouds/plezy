import '../../auth/replay_auth.dart';
import 'tf1plus_authenticator.dart';

/// The session the provider acts under. A token that ran out while the app stayed open is renewed
/// on demand, so playback does not fail between two restarts of the app.
class Tf1SessionHolder {
  final ReplayAuthenticator _authenticator;
  final DateTime Function() _clock;
  ReplaySession? _session;
  Future<String?>? _renewing;

  /// Told about each session this holder renewed by itself, so the app can store it.
  void Function(ReplaySession session)? onRenewed;

  Tf1SessionHolder(this._authenticator, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  bool get isSignedIn => _session != null;

  void use(ReplaySession? session) {
    _session = session;
    _renewing = null;
  }

  /// The bearer token to send, or null when anonymous or when the session could not be renewed.
  Future<String?> bearer() {
    final session = _session;
    if (session == null) return Future.value();
    if (!session.isExpiredAt(_clock())) return Future.value(session.values[Tf1SessionKey.accessToken]);
    return _renewing ??= _renew(session).whenComplete(() => _renewing = null);
  }

  Future<String?> _renew(ReplaySession expired) async {
    try {
      final fresh = await _authenticator.refresh(expired);
      if (identical(_session, expired)) {
        _session = fresh;
        onRenewed?.call(fresh);
      }
      return fresh.values[Tf1SessionKey.accessToken];
    } on ReplayAuthException catch (e) {
      final transient = e.reason == ReplayAuthFailure.network || e.reason == ReplayAuthFailure.rateLimited;
      if (!transient && identical(_session, expired)) _session = null;
      return null;
    }
  }
}
