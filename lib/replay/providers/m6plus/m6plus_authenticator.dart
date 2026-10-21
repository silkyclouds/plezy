// Sign-in to M6+, as the site's own web app does it (rules only).
//
// 1. POST https://accounts.eu1.gigya.com/accounts.login, form body: apiKey (public key of the site),
//    loginID, password, format=json. The password is only ever in this body. HTTP status is 200 and the
//    outcome is the `errorCode` field: 0 success, 403042 wrong login or password, 403120 temporarily
//    locked out, 403005 unauthorised token. Success carries UID, UIDSignature, signatureTimestamp and
//    sessionInfo.cookieValue (the login token).
// 2. GET https://front-auth.6cloud.fr/v2/platforms/m6group_web/getJwt with headers X-Customer-Name,
//    X-Client-Release, x-auth-device-id (a random UUID kept for the session) and X-Auth-gigya-uid,
//    X-Auth-gigya-signature, X-Auth-gigya-signature-timestamp copied from step 1. The signed
//    X-Auth-Token of the anonymous call is not sent in this form. Answer: {"token": <JWT>}; a bad
//    signature gives HTTP 498 (ERR 04004). The JWT carries its own `exp`.
// 3. The JWT is sent as `Authorization: Bearer` (with X-Customer-Name) on video calls.
//
// Renewal: GET accounts.getAccountInfo with login_token=<login token> returns a freshly signed identity
// (the web app does this after 4 hours), then step 2 again. A login token the service no longer accepts
// ends the session: the user signs in again.
//
// Not used: the web app has an OpenID Connect path behind a feature flag that is off, so it is not built.
// The optional X-Auth-profile-id header (multi-profile accounts) is not sent.

import 'package:uuid/uuid.dart';

import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'm6plus_gigya.dart';
import 'm6plus_session.dart';
import 'm6plus_token_service.dart';

/// Signs in to M6+ and renews the resulting session.
class M6plusAuthenticator implements ReplayAuthenticator {
  final M6plusGigya _gigya;
  final M6plusTokenService _tokens;
  final String Function() _newDeviceId;

  M6plusAuthenticator(MediaServerHttpClient http, {String Function()? newDeviceId})
    : _gigya = M6plusGigya(http),
      _tokens = M6plusTokenService(http),
      _newDeviceId = newDeviceId ?? (() => const Uuid().v4());

  @override
  Future<ReplaySession> signIn({required String login, required String password}) async {
    final user = await _gigya.login(login, password);
    final deviceId = _newDeviceId();
    final jwt = await _tokens.exchange(user, deviceId: deviceId);
    return m6plusBuildSession(label: login, jwt: jwt, deviceId: deviceId, loginToken: user.loginToken);
  }

  @override
  Future<ReplaySession> refresh(ReplaySession session) async {
    final loginToken = m6plusLoginTokenOf(session);
    if (loginToken == null) {
      throw const ReplayAuthException(ReplayAuthFailure.invalidCredentials, message: 'The session cannot be renewed.');
    }
    final user = await _gigya.accountInfo(loginToken);
    final deviceId = m6plusDeviceIdOf(session) ?? _newDeviceId();
    final jwt = await _tokens.exchange(user, deviceId: deviceId);
    return m6plusBuildSession(
      label: session.accountLabel,
      jwt: jwt,
      deviceId: deviceId,
      loginToken: user.loginToken ?? loginToken,
    );
  }
}
