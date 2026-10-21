import '../../../utils/app_logger.dart';
import '../../auth/replay_auth.dart';
import 'm6plus_session.dart';

/// The signed-in user of an M6+ provider and the bearer token to send for them.
///
/// A token past its expiry is renewed before it is used. If renewal fails for good the account falls
/// back to anonymous, so playback keeps working as a signed-out visitor instead of failing.
class M6plusAccount {
  final ReplayAuthenticator _authenticator;
  final DateTime Function() _clock;
  ReplaySession? _session;
  Future<void>? _renewing;

  /// Told about every session this account renews by itself, never about one set with [use].
  void Function(ReplaySession session)? onRenewed;

  M6plusAccount(this._authenticator, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  void use(ReplaySession? session) => _session = session;

  /// The token for the next request, or null when anonymous.
  Future<String?> bearer() async {
    final current = _session;
    if (current == null) return null;
    if (current.isExpiredAt(_clock())) {
      await (_renewing ??= _renew(current).whenComplete(() => _renewing = null));
    }
    final session = _session;
    if (session == null || session.isExpiredAt(_clock())) return null;
    return m6plusBearerOf(session);
  }

  Future<void> _renew(ReplaySession expired) async {
    try {
      final fresh = await _authenticator.refresh(expired);
      if (identical(_session, expired)) {
        _session = fresh;
        onRenewed?.call(fresh);
      }
    } on ReplayAuthException catch (e) {
      appLogger.w('M6+ session could not be renewed', error: e.reason.name);
      if (e.reason != ReplayAuthFailure.network && identical(_session, expired)) _session = null;
    }
  }
}
