import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const authFixtures = 'test/replay/fixtures/rtlplay/auth';
const _catalogueFixtures = 'test/replay/fixtures/rtlplay';

const film = 'd1cb72af-01ae-49ef-84bc-d41dc7a87e9b';
const series = '0fda66b9-e270-4ffd-b4ca-f0687711a7c3';
const seriesEpisode = 'e28a86f0-6f2a-47b6-a5c5-f8cdf9a42a1b';
const syntheticSsoToken = 'synthetic-sso-token+with/chars=';
const syntheticPassword = 'synthetic-password-1';
const syntheticLogin = 'viewer@example.invalid';
const _ssoSessionCookie = 'sso_synthetic_session';

String authFixture(String name) => File('$authFixtures/$name').readAsStringSync();

Map<String, dynamic> redirectChain() => jsonDecode(authFixture('web_redirect_chain.json')) as Map<String, dynamic>;

/// A JWT-shaped string with the given expiry; the signature is meaningless.
String syntheticJwt(DateTime expiry) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.synthetic';
}

/// A stand-in for RTL's web host, SSO host, catalogue and stream service.
///
/// The redirect locations are the recorded ones; the account answers, cookie values and stream answers
/// are synthetic. The callback only succeeds when the sign-in state cookie came back, and the
/// authentication step only when it received the token the login handed out.
class FakeRtlPlay {
  final List<http.Request> log = [];

  String loginBody = authFixture('sso_login_success_synthetic.json');
  int loginStatus = 200;
  int authenticateStatus = 302;
  Object? failure;

  /// Fails only the requests to one host.
  (String, Object)? failureForHost;
  DateTime tokenExpiry = DateTime.now().toUtc().add(const Duration(hours: 1));

  /// Set-Cookie value the web home answers with, to simulate the site renewing the access token.
  String? homeSetCookie;

  /// Answer of the stream service as status and body.
  (int, String) playConfig = (200, authFixture('play_config_clear_synthetic.json'));

  /// Status of the player page; 200 serves the synthetic page, 302 the redirect an unknown visitor gets.
  int playerStatus = 200;

  /// Set-Cookie value the player page answers with, to simulate the site rotating its cookies.
  String? playerSetCookie;
  late final String bearer = syntheticJwt(tokenExpiry.add(const Duration(minutes: 30)));

  MediaServerHttpClient get client => MediaServerHttpClient(client: MockClient(_handle));

  RtlPlayProvider provider() => RtlPlayProvider(client);

  Iterable<http.Request> requestsTo(String host) => log.where((r) => r.url.host == host);

  Future<http.Response> _handle(http.Request request) async {
    log.add(request);
    if (failure != null) throw failure!;
    if (failureForHost case (final host, final error) when host == request.url.host) throw error;
    final url = request.url;
    return switch ((request.method, url.host, url.path)) {
      ('GET', 'www.rtlplay.be', '/rtlplay') => _page(homeSetCookie ?? 'lfvp_device_id=device-1; Max-Age=3600; Path=/'),
      ('GET', 'www.rtlplay.be', '/rtlplay/connexion') => _redirect(
        redirectChain()['connexion']['location'] as String,
        'rtlplay_lfvp-private_auth_state=pkce-state; Max-Age=3600; Path=/; HttpOnly',
        307,
      ),
      ('GET', 'sso.rtl.be', '/oidc/connect/authorize') => _authorize(request),
      ('GET', 'sso.rtl.be', '/oidc/account/login') => _redirect(redirectChain()['login']['location'] as String),
      ('POST', 'sso.rtl.be', '/api/account/login') => http.Response(loginBody, loginStatus),
      ('GET', 'sso.rtl.be', '/oidc/account/authenticate') => _authenticate(request),
      ('GET', 'www.rtlplay.be', '/rtlplay/api/auth/callback/rtlplay') => _callback(request),
      ('GET', 'www.rtlplay.be', final path) when path.startsWith('/rtlplay/player/') => _player(request),
      ('POST', 'videoplayer-service.dpgmedia.net', _) => http.Response(playConfig.$2, playConfig.$1),
      ('GET', 'lfvp-api.dpgmedia.net', '/RTL_PLAY/detail3/$film') => _catalogue('show_film'),
      ('GET', 'lfvp-api.dpgmedia.net', '/RTL_PLAY/detail3/$series') => _catalogue('show_series_season3'),
      _ => http.Response('{}', 404),
    };
  }

  http.Response _page(String setCookie) => http.Response('<html></html>', 200, headers: {'set-cookie': setCookie});

  http.Response _redirect(String location, [String? setCookie, int status = 302]) =>
      http.Response('', status, headers: {'location': location, 'set-cookie': ?setCookie});

  http.Response _authorize(http.Request request) {
    if ((request.headers['cookie'] ?? '').contains(_ssoSessionCookie)) {
      return _redirect('https://www.rtlplay.be/rtlplay/api/auth/callback/rtlplay?code=synthetic-code');
    }
    return _redirect(redirectChain()['authorize']['location'] as String);
  }

  http.Response _authenticate(http.Request request) {
    if (authenticateStatus != 302) return http.Response('', authenticateStatus);
    final resume = redirectChain()['login']['location'] as String;
    final expectedResume = Uri.parse(resume).queryParameters['oidc_callback'];
    final query = request.url.queryParameters;
    if (query['redirectUrl'] != expectedResume || query['token'] != syntheticSsoToken) {
      return http.Response('', 400);
    }
    return _redirect(expectedResume!.replaceFirst('/oidc', 'https://sso.rtl.be/oidc'), '$_ssoSessionCookie=1; Path=/');
  }

  http.Response _callback(http.Request request) {
    if (!(request.headers['cookie'] ?? '').contains('rtlplay_lfvp-private_auth_state=pkce-state')) {
      return http.Response('', 400);
    }
    final cookies =
        'lfvp_rtlplay_auth=${syntheticJwt(tokenExpiry)}; Path=/; HttpOnly; Max-Age=3600, '
        'rtlplay_lfvp-private_auth_state=; Max-Age=0; Path=/';
    return _redirect('https://www.rtlplay.be/rtlplay', cookies);
  }

  http.Response _player(http.Request request) {
    if (playerStatus != 200) return _redirect(redirectChain()['connexion']['location'] as String, null, playerStatus);
    final id = request.url.pathSegments.last;
    final page = authFixture(
      'player_page_synthetic.html',
    ).replaceAll('{{CONTENT_ID}}', id).replaceAll('{{TOKEN}}', bearer);
    return http.Response(page, 200, headers: {'set-cookie': ?playerSetCookie});
  }

  http.Response _catalogue(String name) {
    final body = File('$_catalogueFixtures/$name.json').readAsStringSync();
    return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});
  }
}
