import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_api.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_authenticator.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'm6plus_fixture_server.dart';

const _authFixtures = 'test/replay/fixtures/m6plus/auth';
const _login = 'nobody@example.invalid';
const _password = 'made-up-password-1';
const _deviceId = '11111111-2222-4333-8444-555555555555';

/// Fixed so token lifetimes are exact: the same instant the catalogue fixtures use.
final _now = fixtureNow;

String _fixture(String name) => File('$_authFixtures/$name.json').readAsStringSync();

String _segment(Map<String, Object?> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A made-up token with a readable `exp`, not a real credential.
String _syntheticJwt(DateTime expiresAt) =>
    '${_segment({'alg': 'none'})}.${_segment({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.c2lnbmF0dXJl';

/// Stands in for the identity service, the token endpoint and the catalogue, and keeps every request.
class _Backend {
  final M6plusFixtureServer catalogue = M6plusFixtureServer();
  final List<http.Request> requests = [];
  late http.Response Function(http.Request) identity = (_) => _synthetic('success');
  late http.Response Function(http.Request) tokens = (_) => _jwtAnswer(_now.add(const Duration(hours: 8)));

  /// Synthetic success answer in the documented shape of the identity service.
  http.Response _synthetic(String loginToken) => http.Response(
    jsonEncode({
      'errorCode': 0,
      'UID': 'synthetic-uid',
      'UIDSignature': 'synthetic-signature',
      'signatureTimestamp': '1792569000',
      'sessionInfo': {
        'cookieName': 'glt_synthetic',
        'cookieValue': loginToken == 'success' ? 'synthetic-login-token' : loginToken,
      },
    }),
    200,
    headers: {'content-type': 'text/javascript; charset=utf-8'},
  );

  http.Response _handle(http.Request request) {
    requests.add(request);
    final host = request.url.host;
    if (host == 'accounts.eu1.gigya.com') return identity(request);
    if (host == 'front-auth.6cloud.fr') return tokens(request);
    return catalogue.handle(request);
  }

  MediaServerHttpClient get client => MediaServerHttpClient(client: MockClient((r) async => _handle(r)));

  M6plusAuthenticator get authenticator => M6plusAuthenticator(client, newDeviceId: () => _deviceId);

  M6plusProvider provider({DateTime Function()? clock}) => M6plusProvider.withApi(
    M6plusApi(client, minInterval: Duration.zero),
    clock: clock ?? () => _now,
    authenticator: authenticator,
  );

  Iterable<http.Request> to(String host) => requests.where((r) => r.url.host == host);
}

http.Response _jwtAnswer(DateTime expiresAt) =>
    http.Response(jsonEncode({'token': _syntheticJwt(expiresAt)}), 200, headers: {'content-type': 'application/json'});

http.Response _identityError(String body) =>
    http.Response(body, 200, headers: {'content-type': 'text/javascript; charset=utf-8'});

Future<ReplayAuthFailure> _failureOf(Future<Object?> attempt) async {
  try {
    await attempt;
  } on ReplayAuthException catch (e) {
    return e.reason;
  }
  fail('expected a ReplayAuthException');
}

void main() {
  late _Backend backend;

  setUp(() => backend = _Backend());

  group('M6plus sign-in', () {
    test('success with a synthetic answer gives a session that ends before the token does', () async {
      final session = await backend.authenticator.signIn(login: _login, password: _password);

      expect(session.accountLabel, _login);
      expect(session.values['deviceId'], _deviceId);
      expect(session.values['loginToken'], 'synthetic-login-token');
      expect(session.values['jwt'], _syntheticJwt(_now.add(const Duration(hours: 8))));
      expect(session.expiresAt, _now.add(const Duration(hours: 8)).subtract(const Duration(minutes: 1)));
      expect(session.isExpiredAt(_now), isFalse);
    });

    test('the password goes in the POST body only, never in the address', () async {
      await backend.authenticator.signIn(login: _login, password: _password);

      final request = backend.to('accounts.eu1.gigya.com').single;
      expect(request.method, 'POST');
      expect(request.url.path, '/accounts.login');
      expect(request.url.toString(), isNot(contains(_password)));
      expect(request.url.hasQuery, isFalse);
      expect(Uri.splitQueryString(request.body), containsPair('password', _password));
      expect(Uri.splitQueryString(request.body), containsPair('loginID', _login));
    });

    test('the signed identity is passed on to the token endpoint', () async {
      await backend.authenticator.signIn(login: _login, password: _password);

      final headers = backend.to('front-auth.6cloud.fr').single.headers;
      expect(headers['X-Auth-gigya-uid'], 'synthetic-uid');
      expect(headers['X-Auth-gigya-signature'], 'synthetic-signature');
      expect(headers['X-Auth-gigya-signature-timestamp'], '1792569000');
      expect(headers['x-auth-device-id'], _deviceId);
      expect(headers['X-Customer-Name'], 'm6web');
    });

    test('the recorded invalid-credentials answer is reported as such', () async {
      backend.identity = (_) => _identityError(_fixture('gigya_invalid_credentials'));

      final attempt = backend.authenticator.signIn(login: _login, password: _password);

      expect(await _failureOf(attempt), ReplayAuthFailure.invalidCredentials);
      expect(backend.to('front-auth.6cloud.fr'), isEmpty);
    });

    test('a temporary lock-out is rate limiting (synthetic answer)', () async {
      backend.identity = (_) => _identityError(jsonEncode({'errorCode': 403120, 'errorDetails': 'locked'}));

      expect(
        await _failureOf(backend.authenticator.signIn(login: _login, password: _password)),
        ReplayAuthFailure.rateLimited,
      );
    });

    test('HTTP 429 from the token endpoint is rate limiting', () async {
      backend.tokens = (_) => http.Response('', 429);

      expect(
        await _failureOf(backend.authenticator.signIn(login: _login, password: _password)),
        ReplayAuthFailure.rateLimited,
      );
    });

    test('a challenge that mentions a captcha is reported as one (synthetic answer)', () async {
      backend.identity = (_) => _identityError(jsonEncode({'errorCode': 401020, 'errorDetails': 'Captcha required'}));

      expect(
        await _failureOf(backend.authenticator.signIn(login: _login, password: _password)),
        ReplayAuthFailure.captchaRequired,
      );
    });

    test('a dropped connection is a network failure', () async {
      final client = MediaServerHttpClient(client: MockClient((_) async => throw const SocketException('offline')));
      final authenticator = M6plusAuthenticator(client);

      expect(await _failureOf(authenticator.signIn(login: _login, password: _password)), ReplayAuthFailure.network);
    });

    test('a server error from the token endpoint is a network failure', () async {
      backend.tokens = (_) => http.Response('', 503);

      expect(
        await _failureOf(backend.authenticator.signIn(login: _login, password: _password)),
        ReplayAuthFailure.network,
      );
    });

    test('the recorded bad-signature answer from the token endpoint is a rejection', () async {
      backend.tokens = (_) =>
          http.Response(_fixture('getjwt_invalid_signature'), 498, headers: {'content-type': 'application/json'});

      final attempt = backend.authenticator.signIn(login: _login, password: _password);

      expect(await _failureOf(attempt), ReplayAuthFailure.rejected);
    });
  });

  group('M6plus session renewal', () {
    test('renewing signs the identity again from the login token and keeps the device', () async {
      final session = await backend.authenticator.signIn(login: _login, password: _password);
      backend.requests.clear();
      backend.tokens = (_) => _jwtAnswer(_now.add(const Duration(hours: 16)));

      final fresh = await backend.authenticator.refresh(session);

      final request = backend.to('accounts.eu1.gigya.com').single;
      expect(request.url.path, '/accounts.getAccountInfo');
      expect(Uri.splitQueryString(request.body), containsPair('login_token', 'synthetic-login-token'));
      expect(Uri.splitQueryString(request.body), isNot(contains('password')));
      expect(fresh.accountLabel, _login);
      expect(fresh.values['deviceId'], _deviceId);
      expect(fresh.expiresAt, _now.add(const Duration(hours: 16)).subtract(const Duration(minutes: 1)));
    });

    test('a login token the service refuses ends the session (recorded answer)', () async {
      final session = await backend.authenticator.signIn(login: _login, password: _password);
      backend.identity = (_) => _identityError(_fixture('gigya_unauthorized_token'));

      expect(await _failureOf(backend.authenticator.refresh(session)), ReplayAuthFailure.invalidCredentials);
    });

    test('a session without a login token cannot be renewed', () async {
      const session = ReplaySession(accountLabel: _login, values: {'jwt': 'x'});

      expect(await _failureOf(backend.authenticator.refresh(session)), ReplayAuthFailure.invalidCredentials);
      expect(backend.requests, isEmpty);
    });
  });

  group('M6plus provider with an account', () {
    final ref = ReplayRef('m6plus', 'clip_13094113');

    Future<M6plusProvider> signedIn({DateTime Function()? clock}) async {
      final provider = backend.provider(clock: clock);
      provider.useSession(await provider.authenticator.signIn(login: _login, password: _password));
      return provider;
    }

    Iterable<http.Request> videoCalls() =>
        backend.to('pc.middleware.6play.fr').where((r) => r.url.path.contains('/videos'));

    test('the next video request carries the session', () async {
      final provider = await signedIn();

      await provider.playback(ref);

      final headers = videoCalls().single.headers;
      expect(headers['Authorization'], 'Bearer ${_syntheticJwt(_now.add(const Duration(hours: 8)))}');
      expect(headers['X-Customer-Name'], 'm6web');
    });

    test('programme requests and the manifest probe stay anonymous', () async {
      final provider = await signedIn();

      await provider.playback(ref);
      await provider.title(ReplayRef('m6plus', '28545'));

      final others = backend.requests.where(
        (r) =>
            !videoCalls().contains(r) && r.url.host != 'accounts.eu1.gigya.com' && r.url.host != 'front-auth.6cloud.fr',
      );
      expect(others, isNotEmpty);
      expect(others.every((r) => !r.headers.containsKey('Authorization')), isTrue);
    });

    test('signing out sends anonymous requests again and keeps account-independent caches', () async {
      final provider = await signedIn();
      await provider.title(ReplayRef('m6plus', '28545'));
      await provider.playback(ref);
      final programCalls = backend
          .to('pc.middleware.6play.fr')
          .where((r) => r.url.path.endsWith('/programs/28545'))
          .length;

      provider.useSession(null);
      await provider.title(ReplayRef('m6plus', '28545'));
      await provider.playback(ref);

      expect(videoCalls().last.headers.containsKey('Authorization'), isFalse);
      expect(
        backend.to('pc.middleware.6play.fr').where((r) => r.url.path.endsWith('/programs/28545')).length,
        programCalls,
      );
    });

    test('an expired session is renewed before the request', () async {
      var clock = _now;
      final provider = await signedIn(clock: () => clock);
      clock = _now.add(const Duration(hours: 9));
      backend.tokens = (_) => _jwtAnswer(_now.add(const Duration(hours: 17)));

      await provider.playback(ref);

      expect(backend.to('accounts.eu1.gigya.com').last.url.path, '/accounts.getAccountInfo');
      expect(
        videoCalls().single.headers['Authorization'],
        'Bearer ${_syntheticJwt(_now.add(const Duration(hours: 17)))}',
      );
    });

    test('a session that cannot be renewed falls back to anonymous playback', () async {
      var clock = _now;
      final provider = await signedIn(clock: () => clock);
      clock = _now.add(const Duration(hours: 9));
      backend.identity = (_) => _identityError(_fixture('gigya_unauthorized_token'));

      final playback = await provider.playback(ref);

      expect(playback.isPlayable, isTrue);
      expect(videoCalls().single.headers.containsKey('Authorization'), isFalse);
    });

    test('the listener gets the session an automatic renewal produces', () async {
      var clock = _now;
      final provider = await signedIn(clock: () => clock);
      final renewed = <ReplaySession>[];
      provider.onSessionRenewed = renewed.add;
      clock = _now.add(const Duration(hours: 9));
      backend.tokens = (_) => _jwtAnswer(_now.add(const Duration(hours: 17)));

      await provider.playback(ref);

      expect(renewed, hasLength(1));
      expect(renewed.single.values['jwt'], _syntheticJwt(_now.add(const Duration(hours: 17))));
      expect(renewed.single.values['loginToken'], 'synthetic-login-token');
    });

    test('the listener is not called when nothing was renewed', () async {
      final provider = await signedIn();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;

      await provider.playback(ref);
      await provider.playback(ref);

      expect(calls, 0);
    });

    test('the listener is not called after sign-out or when renewal fails', () async {
      var clock = _now;
      final provider = await signedIn(clock: () => clock);
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      clock = _now.add(const Duration(hours: 9));

      provider.useSession(null);
      await provider.playback(ref);
      expect(calls, 0);

      provider.useSession(await provider.authenticator.signIn(login: _login, password: _password));
      backend.identity = (_) => _identityError(_fixture('gigya_unauthorized_token'));
      await provider.playback(ref);
      expect(calls, 0);
    });

    test('a cleared listener is no longer called', () async {
      var clock = _now;
      final provider = await signedIn(clock: () => clock);
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.onSessionRenewed = null;
      clock = _now.add(const Duration(hours: 9));

      await provider.playback(ref);

      expect(calls, 0);
    });
  });
}
