import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:plezy/replay/providers/rtbf/rtbf_provider.dart';

import 'rtbf_test_support.dart';

const _authFixtures = 'test/replay/fixtures/rtbf/auth';

const testLogin = 'viewer@example.invalid';
const testPassword = 'correct horse battery staple';
const sessionToken = 'synthetic-session-token';
const renewedToken = 'synthetic-renewed-token';

String authFixture(String name) => File('$_authFixtures/$name.json').readAsStringSync();

/// Gigya labels its JSON `text/javascript` and reports errors with HTTP 200.
http.Response gigyaReply(String fixture, {int status = 200}) =>
    http.Response(authFixture(fixture), status, headers: {'content-type': 'text/javascript; charset=utf-8'});

http.Response redbeeReply(String fixture, {int status = 200}) => rtbfReply(authFixture(fixture), status: status);

/// The account endpoints over fixtures. [replies] swaps one step for another answer, by step name:
/// `ids`, `login`, `jwt`, `redbeeLogin`, `session`, `entitlement`.
http.Response? Function(http.Request) authServer({
  Map<String, http.Response Function(http.Request request)> replies = const {},
  List<http.Request>? log,
}) {
  return (request) {
    log?.add(request);
    final step = _step(request);
    final override = replies[step];
    if (override != null) return override(request);
    return switch (step) {
      'ids' => gigyaReply('synthetic_gigya_ids'),
      'login' => gigyaReply('synthetic_gigya_login'),
      'jwt' => gigyaReply('synthetic_gigya_jwt'),
      'redbeeLogin' => redbeeReply('synthetic_redbee_login'),
      'session' => _session(request),
      'entitlement' => _entitlement(request),
      _ => null,
    };
  };
}

http.Response _session(http.Request request) => request.headers['Authorization'] == 'Bearer $sessionToken'
    ? redbeeReply('synthetic_redbee_session')
    : redbeeReply('redbee_invalid_session', status: 401);

http.Response _entitlement(http.Request request) {
  final bearer = request.headers['Authorization'];
  if (bearer == 'Bearer $sessionToken' || bearer == 'Bearer $renewedToken') {
    return rtbfReply(rtbfFixture('entitlement_clear_audio_mp3'));
  }
  return redbeeReply('redbee_invalid_session', status: 401);
}

String? _step(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/socialize.getIDs')) return 'ids';
  if (path.endsWith('/accounts.login')) return 'login';
  if (path.endsWith('/accounts.getJWT')) return 'jwt';
  if (path.endsWith('/auth/gigyaLogin')) return 'redbeeLogin';
  if (path.endsWith('/auth/session')) return 'session';
  if (path.contains('/entitlement/')) return 'entitlement';
  return null;
}

RtbfProvider authProvider({
  Map<String, http.Response Function(http.Request request)> replies = const {},
  List<http.Request>? log,
}) => rtbfProvider(
  handler: authServer(replies: replies, log: log),
);

/// A provider that is already signed in, with the session a successful sign-in produced.
Future<(RtbfProvider, List<http.Request>)> signedInProvider({
  Map<String, http.Response Function(http.Request request)> replies = const {},
}) async {
  final log = <http.Request>[];
  final provider = authProvider(replies: replies, log: log);
  final session = await provider.authenticator.signIn(login: testLogin, password: testPassword);
  provider.useSession(session);
  log.clear();
  return (provider, log);
}
