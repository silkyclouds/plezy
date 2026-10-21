import '../../auth/replay_auth.dart';
import 'rtlplay_cookie_jar.dart';
import 'rtlplay_jwt.dart';
import 'rtlplay_web_client.dart';

/// Cookie that holds the viewer's access token on the web host.
const rtlPlayAuthCookie = 'lfvp_rtlplay_auth';

/// Cookie of the in-progress sign-in (the PKCE verifier): useless once the sign-in is done.
const _pendingSignInCookie = 'rtlplay_lfvp-private_auth_state';

/// The session worth keeping from [jar]: the web host's cookies minus the sign-in leftovers, which is what
/// the site itself keeps. Null when the sign-in did not produce an access token.
ReplaySession? rtlPlaySessionFromJar(RtlPlayCookieJar jar, {required String accountLabel}) {
  final cookies = {...jar.cookiesOf(rtlPlayWebHost)}..remove(_pendingSignInCookie);
  final token = cookies[rtlPlayAuthCookie];
  if (token == null || token.isEmpty) return null;
  return ReplaySession(accountLabel: accountLabel, values: cookies, expiresAt: rtlPlayJwtExpiry(token));
}

/// A jar holding the web cookies of [session].
RtlPlayCookieJar rtlPlayJarFromSession(ReplaySession session) =>
    RtlPlayCookieJar.seeded(rtlPlayWebHost, session.values);
