import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_cookie_jar.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_jwt.dart';

import 'rtlplay_auth_support.dart';

Future<ReplayAuthException> _signInFailure(FakeRtlPlay rtl) async {
  try {
    await rtl.provider().authenticator.signIn(login: syntheticLogin, password: syntheticPassword);
  } on ReplayAuthException catch (e) {
    return e;
  }
  throw StateError('sign-in unexpectedly succeeded');
}

void main() {
  group('RtlPlay sign-in', () {
    test('the provider offers an authenticator and a session switch', () {
      expect(FakeRtlPlay().provider(), isA<ReplayAccountSupport>());
    });

    test('a synthetic success yields the web cookies and the token expiry', () async {
      final rtl = FakeRtlPlay();
      final session = await rtl.provider().authenticator.signIn(
        login: ' $syntheticLogin ',
        password: syntheticPassword,
      );

      expect(session.accountLabel, syntheticLogin);
      expect(session.values.keys, containsAll(['lfvp_device_id', 'lfvp_rtlplay_auth']));
      expect(session.values.keys, isNot(contains('rtlplay_lfvp-private_auth_state')));
      expect(rtlPlayJwtExpiry(session.values['lfvp_rtlplay_auth']!), session.expiresAt);
      expect(session.expiresAt!.difference(DateTime.now()).inMinutes, inInclusiveRange(58, 61));
    });

    test('the password travels only in the login body', () async {
      final rtl = FakeRtlPlay();
      final session = await rtl.provider().authenticator.signIn(login: syntheticLogin, password: syntheticPassword);

      final carriers = rtl.log.where(
        (r) => r.url.toString().contains(syntheticPassword) || r.body.contains(syntheticPassword),
      );
      expect(carriers.map((r) => '${r.method} ${r.url.path}'), ['POST /api/account/login']);
      expect(jsonDecode(carriers.single.body), {'username': syntheticLogin, 'password': syntheticPassword});
      expect(jsonEncode(session.toJson()), isNot(contains(syntheticPassword)));
    });

    test('the SSO token only goes to the SSO host', () async {
      final rtl = FakeRtlPlay();
      await rtl.provider().authenticator.signIn(login: syntheticLogin, password: syntheticPassword);

      final withToken = rtl.log.where((r) => r.url.toString().contains(Uri.encodeComponent(syntheticSsoToken)));
      expect(withToken.map((r) => r.url.host).toSet(), {'sso.rtl.be'});
      expect(withToken.single.url.path, '/oidc/account/authenticate');
    });

    test('the login request carries the brand headers the site sends', () async {
      final rtl = FakeRtlPlay();
      await rtl.provider().authenticator.signIn(login: syntheticLogin, password: syntheticPassword);

      final login = rtl.log.singleWhere((r) => r.url.path == '/api/account/login');
      expect(login.headers['sso-createdby'], 'rtlplay-web');
      expect(login.headers['sso-brand'], 'RTL Play');
      expect(login.headers['content-type'], startsWith('application/json'));
    });

    test('the recorded invalid-credentials answer is reported and stops the flow', () async {
      final rtl = FakeRtlPlay()..loginBody = authFixture('sso_login_invalid_credentials.json');
      final failure = await _signInFailure(rtl);

      expect(failure.reason, ReplayAuthFailure.invalidCredentials);
      expect(rtl.log.where((r) => r.url.path == '/oidc/account/authenticate'), isEmpty);
    });

    test('throttling is reported as rate limited, in the body or as HTTP 429', () async {
      final inBody = FakeRtlPlay()..loginBody = authFixture('sso_login_throttled_synthetic.json');
      expect((await _signInFailure(inBody)).reason, ReplayAuthFailure.rateLimited);

      final http429 = FakeRtlPlay()
        ..loginBody = ''
        ..loginStatus = 429;
      expect((await _signInFailure(http429)).reason, ReplayAuthFailure.rateLimited);
    });

    test('a captcha wall is reported, never worked around', () async {
      final rtl = FakeRtlPlay()..loginBody = authFixture('sso_login_captcha_synthetic.json');
      final failure = await _signInFailure(rtl);

      expect(failure.reason, ReplayAuthFailure.captchaRequired);
      expect(rtl.log.where((r) => r.url.path == '/api/account/login'), hasLength(1));
    });

    test('an unknown status is a rejection that names the status', () async {
      final rtl = FakeRtlPlay()..loginBody = '{"status":"EMAIL_NOT_VERIFIED","httpStatusCode":400}';
      final failure = await _signInFailure(rtl);

      expect(failure.reason, ReplayAuthFailure.rejected);
      expect(failure.message, 'EMAIL_NOT_VERIFIED');
    });

    test('a connection failure is a network failure', () async {
      final rtl = FakeRtlPlay()..failure = http.ClientException('offline');
      expect((await _signInFailure(rtl)).reason, ReplayAuthFailure.network);
    });

    test('a server error at the login endpoint is a network failure', () async {
      final rtl = FakeRtlPlay()
        ..loginBody = ''
        ..loginStatus = 503;
      expect((await _signInFailure(rtl)).reason, ReplayAuthFailure.network);
    });

    test('a failing authentication step is a rejection, not a session', () async {
      final rtl = FakeRtlPlay()..authenticateStatus = 500;
      expect((await _signInFailure(rtl)).reason, ReplayAuthFailure.rejected);
    });
  });

  group('RtlPlay refresh', () {
    test('a renewed access cookie gives a fresh session with a later expiry', () async {
      final rtl = FakeRtlPlay();
      final provider = rtl.provider();
      final stale = ReplaySession(
        accountLabel: syntheticLogin,
        values: {
          'lfvp_device_id': 'device-1',
          'lfvp_rtlplay_auth': syntheticJwt(DateTime.now().toUtc().subtract(const Duration(minutes: 5))),
        },
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      final renewed = syntheticJwt(DateTime.now().toUtc().add(const Duration(hours: 1)));
      rtl.homeSetCookie = 'lfvp_rtlplay_auth=$renewed; Path=/; HttpOnly';

      final fresh = await provider.authenticator.refresh(stale);

      expect(fresh.values['lfvp_rtlplay_auth'], renewed);
      expect(fresh.values['lfvp_device_id'], 'device-1');
      expect(fresh.accountLabel, syntheticLogin);
      expect(fresh.isExpiredAt(DateTime.now()), isFalse);
      expect(rtl.log.single.headers['cookie'], contains('lfvp_rtlplay_auth=${stale.values['lfvp_rtlplay_auth']}'));
    });

    test('a site that does not renew the cookie asks for a new sign-in', () async {
      final rtl = FakeRtlPlay();
      final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final stale = ReplaySession(
        accountLabel: syntheticLogin,
        values: {'lfvp_rtlplay_auth': syntheticJwt(expiry)},
        expiresAt: expiry,
      );

      await expectLater(
        rtl.provider().authenticator.refresh(stale),
        throwsA(isA<ReplayAuthException>().having((e) => e.reason, 'reason', ReplayAuthFailure.rejected)),
      );
    });

    test('a refresh without connection is a network failure', () async {
      final rtl = FakeRtlPlay()..failure = http.ClientException('offline');
      final session = ReplaySession(accountLabel: 'x', values: {'lfvp_rtlplay_auth': 'a.b.c'});

      await expectLater(
        rtl.provider().authenticator.refresh(session),
        throwsA(isA<ReplayAuthException>().having((e) => e.reason, 'reason', ReplayAuthFailure.network)),
      );
    });
  });

  group('RtlPlay cookies and tokens', () {
    test('a Set-Cookie header with dates and several cookies is read apart', () {
      final jar = RtlPlayCookieJar()
        ..store('h', 'a=1; Expires=Wed, 21 Oct 2026 08:52:27 GMT; Path=/, b=2; Max-Age=60; HttpOnly, c=3; Secure');
      expect(jar.cookiesOf('h'), {'a': '1', 'b': '2', 'c': '3'});
    });

    test('an emptied or zero-age cookie is removed', () {
      final jar = RtlPlayCookieJar.seeded('h', {'a': '1', 'b': '2'})..store('h', 'a=; Max-Age=0, b=9; Max-Age=0');
      expect(jar.header('h'), isNull);
    });

    test('a JWT expiry is read, anything else has none', () {
      final at = DateTime.utc(2030, 1, 2, 3, 4, 5);
      expect(rtlPlayJwtExpiry(syntheticJwt(at)), at);
      expect(rtlPlayJwtExpiry('not-a-token'), isNull);
      expect(rtlPlayJwtExpiry('a.!!!.c'), isNull);
    });
  });
}
