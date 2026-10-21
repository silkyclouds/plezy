// Sign-in rules, as the TF1+ web app (www.tf1.fr) performs them.
//
// 1. POST https://accounts.eu1.gigya.com/accounts.login, form-encoded: apiKey (public, see
//    tf1GigyaApiKey), loginID, password, loginMode=standard, format=json. HTTP status is 200 even for
//    refusals; `errorCode` decides. 0 is success and carries UID, UIDSignature and signatureTimestamp.
//    403042 and 403047 mean wrong credentials, 403048 and 403120 a rate limit or a temporary lockout.
//    206001 and 206002 mean the account still has to be completed or confirmed, so they are rejected.
// 2. POST https://www.tf1.fr/token/gigya/web, JSON: UID, signature, timestamp (number), consent_ids.
//    The answer holds `token`, a JWT used as `Authorization: Bearer <token>` on the media info route,
//    and the response sets an HttpOnly `refresh_token` cookie. A stale signature gets HTTP 400.
// 3. POST https://www.tf1.fr/token/refresh, JSON: consent_ids, with the `refresh_token` cookie. It
//    answers like step 2. Without a valid cookie it answers HTTP 401 and clears the cookie.
//
// The session keeps the bearer token and the refresh cookie value, nothing else. `expiresAt` is the
// token's own `exp` minus one minute. The password is sent once, in the body of step 1.

import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'tf1plus_gigya.dart';
import 'tf1plus_token.dart';

/// Keys of [ReplaySession.values] for a TF1+ session.
abstract final class Tf1SessionKey {
  static const accessToken = 'token';
  static const refreshToken = 'refresh_token';
}

/// Signs in to TF1+ and keeps the session alive.
class Tf1Authenticator implements ReplayAuthenticator {
  final MediaServerHttpClient _http;

  Tf1Authenticator(this._http);

  @override
  Future<ReplaySession> signIn({required String login, required String password}) async {
    final address = login.trim();
    final identity = await tf1GigyaLogin(_http, login: address, password: password);
    return _session(address, await tf1ExchangeIdentity(_http, identity));
  }

  @override
  Future<ReplaySession> refresh(ReplaySession session) async {
    final refreshToken = session.values[Tf1SessionKey.refreshToken];
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'Session cannot be refreshed');
    }
    return _session(session.accountLabel, await tf1RefreshToken(_http, refreshToken));
  }

  ReplaySession _session(String accountLabel, Tf1Tokens tokens) => ReplaySession(
    accountLabel: accountLabel,
    values: {
      Tf1SessionKey.accessToken: tokens.accessToken,
      if (tokens.refreshToken != null) Tf1SessionKey.refreshToken: tokens.refreshToken!,
    },
    expiresAt: tokens.expiresAt,
  );
}
