/// Sign-in to RTL Play with an RTL account (e-mail address and password), as the website does it.
///
/// The site is an OpenID Connect client (`lfvp-private`, PKCE, code flow) whose token exchange happens on its
/// own server, so the app drives the site's own redirects and keeps the cookies the site sets:
///
/// 1. `GET www.rtlplay.be/rtlplay` sets the `lfvp_device_id` cookie.
/// 2. `GET /rtlplay/connexion` answers 307 to `sso.rtl.be/oidc/connect/authorize` and sets the PKCE state
///    cookie `rtlplay_lfvp-private_auth_state`; the authorize request answers 302 to the account page whose
///    query holds `oidc_callback` (the authorize path to resume), `created_by` and `brand`.
/// 3. `POST sso.rtl.be/api/account/login` with JSON `username` and `password`, headers `SSO-CreatedBy`,
///    `SSO-Brand`, `SSO-NoCookie: 1`. The answer is HTTP 200 with a `status` in the body: `SUCCESS` carries
///    `data.userAccount.session.encryptedToken`, `INVALID_EMAIL_CREDENTIALS` / `INVALID_PASSWORD_CREDENTIALS`
///    are wrong credentials, `*_CAPTCHA` statuses want a captcha, `TOO_MANY_REQUESTS` is throttling.
/// 4. `GET sso.rtl.be/oidc/account/authenticate?redirectUrl=<oidc_callback>&token=<encryptedToken>` redirects
///    through authorize to `www.rtlplay.be/rtlplay/api/auth/callback/rtlplay`, which sets `lfvp_rtlplay_auth`.
///
/// The session is the web host's cookies without the PKCE state; its expiry is the `exp` claim of
/// `lfvp_rtlplay_auth`. The password is only ever the body of step 3 and the token only a query value to
/// the SSO host, and neither is stored or logged. No captcha is solved or bypassed.
///
/// Steps 1, 2 and the invalid-credentials answer of step 3 were checked against the live site. Steps 3
/// (success) and 4, the cookie names set by the callback and the token lifetime need a real account.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../auth/replay_auth.dart';
import 'rtlplay_cookie_jar.dart';
import 'rtlplay_session.dart';
import 'rtlplay_sso_login.dart';
import 'rtlplay_web_client.dart';

final _siteHome = Uri.parse('https://$rtlPlayWebHost/rtlplay');
final _siteLogin = Uri.parse('https://$rtlPlayWebHost/rtlplay/connexion');
final _authenticate = Uri.parse('https://$rtlPlaySsoHost/oidc/account/authenticate');
const _authorizePath = '/oidc/connect/authorize';

/// Everything the account page's address tells the sign-in to carry along.
typedef _AccountPage = ({String resumePath, String createdBy, String brand});

/// Signs in to RTL Play and renews the session it produced.
class RtlPlayAuthenticator implements ReplayAuthenticator {
  final http.Client _client;
  final DateTime Function() _now;

  RtlPlayAuthenticator(this._client, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  @override
  Future<ReplaySession> signIn({required String login, required String password}) {
    return _guarded(() async {
      final jar = RtlPlayCookieJar();
      final web = RtlPlayWebClient(_client, jar);
      _requireReachable(await web.get(_siteHome));
      final page = await _openAccountPage(web);
      final token = await rtlPlaySsoLogin(
        web,
        login: login,
        password: password,
        createdBy: page.createdBy,
        brand: page.brand,
      );
      await _completeWebSignIn(web, page.resumePath, token);
      final session = rtlPlaySessionFromJar(jar, accountLabel: login.trim());
      if (session == null) {
        throw const ReplayAuthException(
          ReplayAuthFailure.rejected,
          message: 'RTL Play gave no access token: finish setting up the account on sso.rtl.be first',
        );
      }
      return session;
    });
  }

  /// Asks the site for the cookies again: the site renews its own access token while the visitor is known.
  /// A session that stays expired has to be replaced by a new sign-in.
  @override
  Future<ReplaySession> refresh(ReplaySession session) {
    return _guarded(() async {
      final jar = rtlPlayJarFromSession(session);
      _requireReachable(await RtlPlayWebClient(_client, jar).get(_siteHome));
      final renewed = rtlPlaySessionFromJar(jar, accountLabel: session.accountLabel);
      if (renewed == null || renewed.isExpiredAt(_now())) {
        throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'The session expired, sign in again');
      }
      return renewed;
    });
  }

  Future<_AccountPage> _openAccountPage(RtlPlayWebClient web) async {
    final response = await web.follow(_siteLogin, stopWhen: (r) => _accountPageOf(r.redirectTarget) != null);
    _requireReachable(response);
    final page = _accountPageOf(response.redirectTarget);
    if (page == null) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'The sign-in page is not the expected one');
    }
    return page;
  }

  _AccountPage? _accountPageOf(Uri? target) {
    if (target == null || target.host != rtlPlaySsoHost) return null;
    final resume = target.queryParameters['oidc_callback'];
    if (resume == null || !resume.startsWith(_authorizePath)) return null;
    return (
      resumePath: resume,
      createdBy: target.queryParameters['created_by'] ?? 'rtlplay-web',
      brand: target.queryParameters['brand'] ?? 'RTL Play',
    );
  }

  Future<void> _completeWebSignIn(RtlPlayWebClient web, String resumePath, String token) async {
    final address = _authenticate.replace(
      query: 'redirectUrl=${Uri.encodeComponent(resumePath)}&token=${Uri.encodeComponent(token)}',
    );
    final response = await web.follow(
      address,
      stopWhen: (_) => web.jar.value(rtlPlayWebHost, rtlPlayAuthCookie) != null,
    );
    if (response.status == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
    // The step answers 500 to a token it does not accept, so a server error here is a refusal.
    if (response.status >= 500) {
      throw ReplayAuthException(ReplayAuthFailure.rejected, message: 'HTTP ${response.status} while signing in');
    }
  }

  void _requireReachable(RtlPlayWebResponse response) {
    if (response.status == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
    if (response.status >= 500) {
      throw ReplayAuthException(ReplayAuthFailure.network, message: 'HTTP ${response.status}');
    }
  }

  Future<T> _guarded<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on http.ClientException catch (e) {
      throw ReplayAuthException(ReplayAuthFailure.network, message: e.message);
    } on TimeoutException {
      throw const ReplayAuthException(ReplayAuthFailure.network, message: 'Timed out');
    }
  }
}
