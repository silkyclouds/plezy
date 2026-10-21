import 'dart:convert';

import '../../auth/replay_auth.dart';
import 'rtbf_http.dart';

const _apiKey = '4_Ml_fJ47GnBAW6FrPzMxh0w';
const _accounts = 'https://accounts.eu1.gigya.com';
const _socialize = 'https://socialize.eu1.gigya.com';
const _sdk = 'js_latest';
const _common = {'apiKey': _apiKey, 'format': 'json', 'sdk': _sdk};

/// What a sign-in leaves: the login token and the device identity it is bound to, and a fresh identity token.
class RtbfGigyaIdentity {
  final String loginToken;
  final String gmid;
  final String ucid;
  final String jwt;

  const RtbfGigyaIdentity({required this.loginToken, required this.gmid, required this.ucid, required this.jwt});
}

/// The identity service behind the Auvio account, called the way its web SDK calls it.
class RtbfGigya {
  final RtbfHttp _http;

  RtbfGigya(this._http);

  /// Signs in. The password goes only into the login request body.
  Future<RtbfGigyaIdentity> signIn({required String login, required String password}) async {
    final ids = await _call('$_socialize/socialize.getIDs', {'APIKey': _apiKey, 'includeTicket': 'true', ..._common});
    final gmid = ids['gcid'];
    final ucid = ids['ucid'];
    if (gmid is! String || ucid is! String) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'No device identity was issued');
    }
    final loginToken = await _login(gmid, ucid, login, password);
    return RtbfGigyaIdentity(
      loginToken: loginToken,
      gmid: gmid,
      ucid: ucid,
      jwt: await identityToken(loginToken: loginToken, gmid: gmid, ucid: ucid),
    );
  }

  /// A signed identity token valid for five minutes, from a login token and the device identity it was
  /// issued to.
  Future<String> identityToken({required String loginToken, required String gmid, required String ucid}) async {
    final body = await _call('$_accounts/accounts.getJWT', {
      ..._common,
      'login_token': loginToken,
      'authMode': 'cookie',
      'fields': 'email, firstName, lastName',
      'gmid': gmid,
      'ucid': ucid,
    });
    final jwt = body['id_token'];
    if (jwt is! String) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'No identity token was issued');
    }
    return jwt;
  }

  Future<String> _login(String gmid, String ucid, String login, String password) async {
    final body = await _call('$_accounts/accounts.login', {
      ..._common,
      'loginID': login,
      'password': password,
      'sessionExpiration': '-2',
      'lang': 'fr',
      'gmid': gmid,
      'ucid': ucid,
    });
    final info = body['sessionInfo'];
    final token = info is Map<String, dynamic> ? info['login_token'] : body['login_token'];
    if (token is! String || token.split('.').elementAtOrNull(1) == 'ffs') {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'No login token was issued');
    }
    return token;
  }

  /// Gigya answers errors with HTTP 200 and an `errorCode` in the body.
  Future<Map<String, dynamic>> _call(String url, Map<String, String> fields) async {
    final answer = await _http.postForm(url, fields);
    final code = answer.body['errorCode'];
    if (code == 0) return answer.body;
    throw rtbfGigyaFailure(answer.body);
  }
}

/// Maps a Gigya error body to a sign-in failure. Codes 403042 and 403043 are a wrong login or password,
/// 403048 and 403120 a temporary lockout after too many attempts.
ReplayAuthException rtbfGigyaFailure(Map<String, dynamic> body) {
  final code = body['errorCode'];
  final detail = (body['errorDetails'] ?? body['errorMessage']) as String?;
  final reason = switch (code) {
    403042 || 403043 => ReplayAuthFailure.invalidCredentials,
    403048 || 403120 => ReplayAuthFailure.rateLimited,
    _ when jsonEncode(body).toLowerCase().contains('captcha') => ReplayAuthFailure.captchaRequired,
    _ => ReplayAuthFailure.rejected,
  };
  return ReplayAuthException(reason, message: code == null ? detail : '${detail ?? 'error'} ($code)');
}
