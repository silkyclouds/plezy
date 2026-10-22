// Auvio sign-in, as the website's own app does it (checked on 2026-10-21):
//
// 1. POST https://socialize.eu1.gigya.com/socialize.getIDs (form: APIKey, includeTicket, format, sdk)
//    gives a device identity: `gcid` is sent back as `gmid`, with `ucid`. Gigya answers 400006 with
//    `errorFlags: missingKey` to any request that lacks them, and hands out a placeholder login token
//    (second segment `ffs`) to a login sent without them.
// 2. POST https://accounts.eu1.gigya.com/accounts.login (form: apiKey = the public key of the website,
//    loginID, password, sessionExpiration -2, lang, gmid, ucid). Errors come as HTTP 200 with
//    `errorCode`: 403042 wrong login or password, 403043 the same for linked accounts, 403048 and
//    403120 temporary lockout. Success carries `sessionInfo.login_token`.
// 3. POST https://accounts.eu1.gigya.com/accounts.getJWT (form: login_token, authMode=cookie, fields,
//    gmid, ucid). The token is bound to the device identity of step 1. `id_token` is a JWT that
//    lives 300 seconds.
// 4. POST https://exposure.api.redbee.live/v2/customer/RTBF/businessunit/Auvio/auth/gigyaLogin
//    (JSON: jwt, device). `sessionToken` is an opaque bearer token that expires in about nine years.
//    Entitlement calls then send `Authorization: Bearer <sessionToken>` instead of the anonymous one.
//
// The session keeps the Red Bee token, the Gigya login token and the device identity that token is
// bound to, never the password. When Red Bee stops accepting its token (401 INVALID_SESSION_TOKEN) steps 3
// and 4 are repeated with the stored login token, as the website does; that token lives about a year.
// GET .../auth/session checks a stored Red Bee session. The website's own OAuth tokens
// (auth-service.rtbf.be) serve favourites and history and are not used here. No captcha is sent:
// Gigya's risk-based captcha is reported as `captchaRequired` when an answer mentions it.
import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/app_logger.dart';
import '../../auth/replay_auth.dart';
import 'rtbf_gigya.dart';
import 'rtbf_http.dart';
import 'rtbf_redbee_account.dart';

const _tokenKey = 'redbeeToken';
const _loginTokenKey = 'loginToken';
const _gmidKey = 'gmid';
const _ucidKey = 'ucid';

/// The Red Bee token of a session, which is what playback sends.
String? rtbfSessionToken(ReplaySession? session) => session?.values[_tokenKey];

/// Signs in to an Auvio account, checks stored sessions and renews dead ones.
class RtbfAuthenticator implements ReplayAuthenticator {
  final RtbfGigya _gigya;
  final RtbfRedbeeAccount _redbee;

  RtbfAuthenticator(RtbfHttp http, String deviceId)
    : _gigya = RtbfGigya(http),
      _redbee = RtbfRedbeeAccount(http, deviceId);

  @override
  Future<ReplaySession> signIn({required String login, required String password}) => _guard(() async {
    final label = login.trim();
    final identity = await _step('Gigya', () => _gigya.signIn(login: label, password: password));
    final redbee = await _step('Red Bee', () => _redbee.signIn(identity.jwt));
    return ReplaySession(
      accountLabel: label,
      values: {
        _tokenKey: redbee.token,
        _loginTokenKey: identity.loginToken,
        _gmidKey: identity.gmid,
        _ucidKey: identity.ucid,
      },
      expiresAt: redbee.expiresAt,
    );
  });

  /// Runs one step of the sign-in and, when it is refused, names the step in the failure so the user and the log
  /// can tell which service said no. The password is never part of the message.
  Future<T> _step<T>(String name, Future<T> Function() run) async {
    try {
      return await run();
    } on ReplayAuthException catch (e) {
      appLogger.w('Auvio sign-in refused at $name', error: e);
      throw ReplayAuthException(e.reason, message: '$name: ${e.message ?? e.reason.name}');
    } on MediaServerHttpException catch (e) {
      appLogger.w('Auvio sign-in failed at $name', error: e);
      throw ReplayAuthException(
        (e.statusCode ?? 500) >= 500 ? ReplayAuthFailure.network : ReplayAuthFailure.rejected,
        message: '$name: ${e.message}',
      );
    }
  }

  /// A live session is kept as it is; one Red Bee no longer accepts is renewed.
  @override
  Future<ReplaySession> refresh(ReplaySession session) => _guard(() async {
    final token = rtbfSessionToken(session);
    if (token != null) {
      try {
        await _redbee.check(token);
        return ReplaySession(accountLabel: session.accountLabel, values: session.values);
      } on ReplayAuthException catch (e) {
        if (e.reason != ReplayAuthFailure.rejected) rethrow;
      }
    }
    return _renew(session);
  });

  /// A new Red Bee session from the stored Gigya login token, without asking for the password again.
  Future<ReplaySession> renew(ReplaySession session) => _guard(() => _renew(session));

  Future<ReplaySession> _renew(ReplaySession session) async {
    final loginToken = session.values[_loginTokenKey];
    final gmid = session.values[_gmidKey];
    final ucid = session.values[_ucidKey];
    if (loginToken == null || gmid == null || ucid == null) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'The stored session cannot be renewed');
    }
    final jwt = await _gigya.identityToken(loginToken: loginToken, gmid: gmid, ucid: ucid);
    final redbee = await _redbee.signIn(jwt);
    return ReplaySession(
      accountLabel: session.accountLabel,
      values: {...session.values, _tokenKey: redbee.token},
      expiresAt: redbee.expiresAt,
    );
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on RtbfRateLimitedException catch (e) {
      throw ReplayAuthException(ReplayAuthFailure.rateLimited, message: e.toString());
    } on MediaServerHttpException catch (e) {
      final status = e.statusCode;
      final unreachable = status == null || status >= 500;
      throw ReplayAuthException(
        unreachable ? ReplayAuthFailure.network : ReplayAuthFailure.rejected,
        message: e.message,
      );
    }
  }
}
