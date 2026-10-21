import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_authenticator.dart';

import 'tf1plus_auth_support.dart';
import 'tf1plus_fixture_server.dart';

const _login = 'nobody@example.invalid';
const _password = 'made-up-password-0';

final _tokenEnds = DateTime.utc(2030, 1, 1, 12);

Future<ReplayAuthException> _failureOf(Future<Object?> attempt) async {
  try {
    await attempt;
  } on ReplayAuthException catch (e) {
    return e;
  }
  fail('Expected the sign-in to fail');
}

Tf1AccountServer _serverWithTokens({String? cookie = 'refresh_token=cookie-one; Path=/; HttpOnly'}) {
  final server = Tf1AccountServer();
  server.exchange = (_) =>
      tf1Json(jsonEncode({'token': tf1SyntheticJwt(_tokenEnds)}), headers: {'set-cookie': ?cookie});
  return server;
}

ReplaySession _session({DateTime? expiresAt, String? refresh = 'cookie-one'}) => ReplaySession(
  accountLabel: _login,
  values: {Tf1SessionKey.accessToken: 'old-token', 'refresh_token': ?refresh},
  expiresAt: expiresAt,
);

void main() {
  group('signing in', () {
    test('a synthetic success becomes a session with the token, the refresh cookie and its lifetime', () async {
      final server = _serverWithTokens();

      final session = await server.authenticator.signIn(login: ' $_login ', password: _password);

      expect(session.accountLabel, _login);
      expect(session.values[Tf1SessionKey.accessToken], tf1SyntheticJwt(_tokenEnds));
      expect(session.values[Tf1SessionKey.refreshToken], 'cookie-one');
      expect(session.values.keys, unorderedEquals(['token', 'refresh_token']));
      expect(session.expiresAt, _tokenEnds.subtract(const Duration(minutes: 1)));
    });

    test('the password goes in the Gigya request body and in no URL', () async {
      final server = _serverWithTokens();
      await server.authenticator.signIn(login: _login, password: _password);

      final login = server.to('accounts.eu1.gigya.com').single;
      expect(login.method, 'POST');
      expect(login.url.hasQuery, isFalse);
      expect(login.bodyFields, containsPair('loginID', _login));
      expect(login.bodyFields, containsPair('password', _password));
      expect(login.bodyFields['apiKey'], startsWith('3_'));
      expect(server.requests.map((r) => r.url.toString()).join(' '), isNot(contains(_password)));
      expect(server.to('www.tf1.fr').single.body, isNot(contains(_password)));
    });

    test('the Gigya identity is traded at the token route with a numeric timestamp', () async {
      final server = _serverWithTokens();
      await server.authenticator.signIn(login: _login, password: _password);

      final exchange = jsonDecode(server.to('www.tf1.fr', '/token/gigya/web').single.body) as Map<String, dynamic>;
      expect(exchange['UID'], 'synthetic-uid-0001');
      expect(exchange['signature'], 'synthetic-signature');
      expect(exchange['timestamp'], 1700000000);
      expect(exchange['consent_ids'], isNotEmpty);
    });

    test('several cookies in one header still yield the refresh cookie', () async {
      final server = _serverWithTokens(cookie: 'tracker=1; Path=/, refresh_token=cookie-two; Path=/; HttpOnly');

      final session = await server.authenticator.signIn(login: _login, password: _password);

      expect(session.values[Tf1SessionKey.refreshToken], 'cookie-two');
    });

    test('a token that is not a readable JWT gives a session without an expiry', () async {
      final server = Tf1AccountServer()..exchange = (_) => tf1Json('{"token":"opaque"}');

      final session = await server.authenticator.signIn(login: _login, password: _password);

      expect(session.expiresAt, isNull);
      expect(session.values.containsKey(Tf1SessionKey.refreshToken), isFalse);
    });

    test('wrong credentials, as recorded from Gigya, stop before the token route', () async {
      final server = _serverWithTokens();
      server.gigya = (_) => tf1Json(tf1AuthFixture('gigya_invalid_credentials'));

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.invalidCredentials);
      expect(failure.toString(), isNot(contains(_password)));
      expect(server.to('www.tf1.fr'), isEmpty);
    });

    test('Gigya rate limit and lockout are rate limited', () async {
      for (final fixture in ['gigya_rate_limit_synthetic', 'gigya_locked_out_synthetic']) {
        final server = _serverWithTokens()..gigya = (_) => tf1Json(tf1AuthFixture(fixture));
        final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));
        expect(failure.reason, ReplayAuthFailure.rateLimited, reason: fixture);
      }
    });

    test('an HTTP 429 from either route is rate limited', () async {
      final atGigya = _serverWithTokens()..gigya = (_) => tf1Json('{}', status: 429);
      expect(
        (await _failureOf(atGigya.authenticator.signIn(login: _login, password: _password))).reason,
        ReplayAuthFailure.rateLimited,
      );

      final atToken = _serverWithTokens()..exchange = (_) => tf1Json('{}', status: 429);
      expect(
        (await _failureOf(atToken.authenticator.signIn(login: _login, password: _password))).reason,
        ReplayAuthFailure.rateLimited,
      );
    });

    test('a challenge in the Gigya answer is captcha required', () async {
      final server = _serverWithTokens()..gigya = (_) => tf1Json(tf1AuthFixture('gigya_captcha_required_synthetic'));

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.captchaRequired);
    });

    test('an account that still has to be confirmed is rejected with Gigya wording', () async {
      final server = _serverWithTokens()
        ..gigya = (_) => tf1Json(tf1AuthFixture('gigya_pending_verification_synthetic'));

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.rejected);
      expect(failure.message, 'Account Pending Verification');
    });

    test('a refused identity at the token route is rejected with the route wording', () async {
      final server = _serverWithTokens()
        ..exchange = (_) => tf1Json(tf1AuthFixture('token_signature_outdated'), status: 400);

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.rejected);
      expect(failure.message, 'signature timestamp outdated');
    });

    test('a Gigya answer without the signature is rejected', () async {
      final server = _serverWithTokens()..gigya = (_) => tf1Json('{"errorCode":0,"UID":"synthetic-uid-0001"}');

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.rejected);
    });

    test('a connection failure is a network failure', () async {
      final server = _serverWithTokens()..gigya = (_) => throw http.ClientException('connection reset');

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.network);
    });

    test('a server error at the token route is a network failure', () async {
      final server = _serverWithTokens()..exchange = (_) => tf1Json('{}', status: 503);

      final failure = await _failureOf(server.authenticator.signIn(login: _login, password: _password));

      expect(failure.reason, ReplayAuthFailure.network);
    });
  });

  group('refreshing', () {
    test('the refresh cookie is sent and the new token and cookie replace the old ones', () async {
      final server = _serverWithTokens();
      server.refresh = (_) => tf1Json(
        jsonEncode({'token': tf1SyntheticJwt(_tokenEnds)}),
        headers: {'set-cookie': 'refresh_token=cookie-two; Path=/; HttpOnly'},
      );

      final fresh = await server.authenticator.refresh(_session(expiresAt: DateTime.utc(2020)));

      final request = server.to('www.tf1.fr', '/token/refresh').single;
      expect(request.headers['Cookie'], 'refresh_token=cookie-one');
      expect(fresh.accountLabel, _login);
      expect(fresh.values[Tf1SessionKey.accessToken], tf1SyntheticJwt(_tokenEnds));
      expect(fresh.values[Tf1SessionKey.refreshToken], 'cookie-two');
      expect(fresh.expiresAt, _tokenEnds.subtract(const Duration(minutes: 1)));
    });

    test('the old cookie is kept when the answer sets none', () async {
      final server = Tf1AccountServer()..refresh = (_) => tf1Json(jsonEncode({'token': tf1SyntheticJwt(_tokenEnds)}));

      final fresh = await server.authenticator.refresh(_session());

      expect(fresh.values[Tf1SessionKey.refreshToken], 'cookie-one');
    });

    test('a refused cookie, as recorded from TF1+, is rejected', () async {
      final server = Tf1AccountServer()
        ..refresh = (_) => tf1Json(tf1AuthFixture('refresh_token_not_found'), status: 401);

      final failure = await _failureOf(server.authenticator.refresh(_session()));

      expect(failure.reason, ReplayAuthFailure.rejected);
      expect(failure.message, 'refresh token not found');
    });

    test('a session without a refresh cookie is rejected without any request', () async {
      final server = Tf1AccountServer();

      final failure = await _failureOf(server.authenticator.refresh(_session(refresh: null)));

      expect(failure.reason, ReplayAuthFailure.rejected);
      expect(server.requests, isEmpty);
    });

    test('a connection failure while refreshing is a network failure', () async {
      final server = Tf1AccountServer()..refresh = (_) => throw http.ClientException('offline');

      final failure = await _failureOf(server.authenticator.refresh(_session()));

      expect(failure.reason, ReplayAuthFailure.network);
    });
  });

  group('the provider acting as the user', () {
    final ref = ReplayRef('tf1plus', Tf1TestVideo.loginRequired);

    test('a session puts its bearer token on the media info request', () async {
      final server = Tf1AccountServer();
      final provider = server.provider()..useSession(_session(expiresAt: DateTime.now().add(const Duration(hours: 1))));

      await provider.playback(ref);

      expect(server.to('mediainfo.tf1.fr').single.headers['Authorization'], 'Bearer old-token');
    });

    test('anonymous requests carry no authorization', () async {
      final server = Tf1AccountServer();

      await server.provider().playback(ref);

      expect(
        server.to('mediainfo.tf1.fr').single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });

    test('signing out returns to anonymous requests', () async {
      final server = Tf1AccountServer();
      final provider = server.provider()..useSession(_session(expiresAt: DateTime.now().add(const Duration(hours: 1))));
      await provider.playback(ref);
      provider.useSession(null);
      await provider.playback(ref);

      final calls = server.to('mediainfo.tf1.fr');
      expect(calls.first.headers['Authorization'], 'Bearer old-token');
      expect(calls.last.headers.containsKey('Authorization'), isFalse);
    });

    test('an expired token is renewed once before the request', () async {
      final server = _serverWithTokens();
      server.refresh = (_) =>
          tf1Json(jsonEncode({'token': 'renewed-token'}), headers: {'set-cookie': 'refresh_token=cookie-two; Path=/'});
      final provider = server.provider()..useSession(_session(expiresAt: DateTime.utc(2020)));

      await provider.playback(ref);
      await provider.playback(ref);

      expect(server.to('www.tf1.fr', '/token/refresh'), hasLength(1));
      expect(
        server.to('mediainfo.tf1.fr').map((r) => r.headers['Authorization']),
        everyElement('Bearer renewed-token'),
      );
    });

    test('a refused renewal leaves the request anonymous and drops the session', () async {
      final server = Tf1AccountServer()
        ..refresh = (_) => tf1Json(tf1AuthFixture('refresh_token_not_found'), status: 401);
      final provider = server.provider()..useSession(_session(expiresAt: DateTime.utc(2020)));

      await provider.playback(ref);
      await provider.playback(ref);

      expect(server.to('mediainfo.tf1.fr').every((r) => !r.headers.containsKey('Authorization')), isTrue);
      expect(server.to('www.tf1.fr', '/token/refresh'), hasLength(1));
    });

    test('a signed-in user who is still refused is told the account lacks the right', () async {
      final server = Tf1AccountServer();
      final provider = server.provider()..useSession(_session(expiresAt: DateTime.now().add(const Duration(hours: 1))));

      final playback = await provider.playback(ref);

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.message, contains('not entitled'));
    });

    test('catalogue requests stay anonymous and keep their cache across sign-in', () async {
      final fixtures = Tf1FixtureServer();
      final provider = fixtures.provider();

      await provider.listing('series');
      provider.useSession(_session(expiresAt: DateTime.now().add(const Duration(hours: 1))));
      await provider.listing('series');

      expect(fixtures.requests, hasLength(1));
    });

    test('the provider offers the authenticator of the same client', () {
      final server = Tf1AccountServer();

      expect(server.provider().authenticator, isA<Tf1Authenticator>());
    });
  });

  group('storing a renewed session', () {
    final ref = ReplayRef('tf1plus', Tf1TestVideo.loginRequired);
    final stale = DateTime.utc(2020);

    Tf1AccountServer renewingServer() => Tf1AccountServer()
      ..refresh = (_) =>
          tf1Json(jsonEncode({'token': 'renewed-token'}), headers: {'set-cookie': 'refresh_token=cookie-two; Path=/'});

    test('the listener gets the renewed session with the rotated refresh token', () async {
      final provider = renewingServer().provider();
      final renewed = <ReplaySession>[];
      provider.onSessionRenewed = renewed.add;
      provider.useSession(_session(expiresAt: stale));

      await provider.playback(ref);
      await provider.playback(ref);

      expect(renewed, hasLength(1));
      expect(renewed.single.values[Tf1SessionKey.accessToken], 'renewed-token');
      expect(renewed.single.values[Tf1SessionKey.refreshToken], 'cookie-two');
      expect(renewed.single.accountLabel, _login);
    });

    test('the listener is not called when the token is still valid', () async {
      final provider = renewingServer().provider();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.useSession(_session(expiresAt: DateTime.now().add(const Duration(hours: 1))));

      await provider.playback(ref);

      expect(calls, 0);
    });

    test('the listener is not called when the renewal fails', () async {
      final server = Tf1AccountServer()
        ..refresh = (_) => tf1Json(tf1AuthFixture('refresh_token_not_found'), status: 401);
      final provider = server.provider();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.useSession(_session(expiresAt: stale));

      await provider.playback(ref);

      expect(calls, 0);
    });

    test('the listener is not called after signing out', () async {
      final provider = renewingServer().provider();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.useSession(_session(expiresAt: stale));
      provider.useSession(null);

      await provider.playback(ref);

      expect(calls, 0);
    });

    test('a cleared listener is not called', () async {
      final provider = renewingServer().provider();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.onSessionRenewed = null;
      provider.useSession(_session(expiresAt: stale));

      await provider.playback(ref);

      expect(calls, 0);
    });
  });
}
