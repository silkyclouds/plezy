import '../../auth/replay_auth.dart';
import 'rtbf_exposure.dart';
import 'rtbf_http.dart';

const _refusals = {400, 401, 403, 404, 409};

/// A Red Bee session of a signed-in account. The platform names its expiry; it is about nine years away.
class RtbfRedbeeSession {
  final String token;
  final DateTime? expiresAt;

  const RtbfRedbeeSession(this.token, this.expiresAt);
}

/// The account side of Red Bee: trading a Gigya identity token for a session, and checking one.
class RtbfRedbeeAccount {
  final RtbfHttp _http;
  final String _deviceId;

  RtbfRedbeeAccount(this._http, this._deviceId);

  /// Opens a session for the account behind [jwt], on this install's device id.
  Future<RtbfRedbeeSession> signIn(String jwt) async {
    final answer = await _http.postJson('$rtbfExposureV2/auth/gigyaLogin', {
      'jwt': jwt,
      ...rtbfDeviceBody(_deviceId),
    }, tolerate: _refusals);
    if (!answer.isOk) throw _refused(answer);
    final token = answer.body['sessionToken'];
    if (token is! String || token.isEmpty) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'The session answer holds no token');
    }
    return RtbfRedbeeSession(token, DateTime.tryParse(answer.body['expirationDateTime'] as String? ?? ''));
  }

  /// Throws when the platform no longer accepts [token].
  Future<void> check(String token) async {
    final answer = await _http.getJson(
      '$rtbfExposureV2/auth/session',
      headers: {'Authorization': 'Bearer $token'},
      tolerate: _refusals,
    );
    if (!answer.isOk) throw _refused(answer);
  }

  ReplayAuthException _refused(RtbfAnswer answer) {
    final message = answer.body['message'];
    return ReplayAuthException(
      ReplayAuthFailure.rejected,
      message: message is String ? message : 'HTTP ${answer.status}',
    );
  }
}
