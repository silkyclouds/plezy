import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_auth.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_rights.dart';

import 'rtbf_auth_support.dart';
import 'rtbf_test_support.dart';

Future<ReplayAuthFailure> failureOf(Future<Object?> attempt) async {
  try {
    await attempt;
  } on ReplayAuthException catch (e) {
    return e.reason;
  }
  fail('Expected the sign-in to fail');
}

ReplaySession storedSession({String token = sessionToken}) => ReplaySession(
  accountLabel: testLogin,
  values: {
    'redbeeToken': token,
    'loginToken': 'st2.s.synthetic-login-token',
    'gmid': 'synthetic-gmid',
    'ucid': 'synthetic-ucid',
  },
);

void main() {
  group('sign-in with a synthetic successful answer', () {
    test('walks the identity service, then the playback platform', () async {
      final log = <http.Request>[];
      final provider = authProvider(log: log);
      final session = await provider.authenticator.signIn(login: ' $testLogin ', password: testPassword);

      expect(log.map((r) => r.url.path), [
        '/socialize.getIDs',
        '/accounts.login',
        '/accounts.getJWT',
        '/v2/customer/RTBF/businessunit/Auvio/auth/gigyaLogin',
      ]);
      expect(session.accountLabel, testLogin);
      expect(rtbfSessionToken(session), sessionToken);
      expect(session.expiresAt, DateTime.utc(2036, 4, 1, 8));
    });

    test('sends the device identity with the login and the identity token to the platform', () async {
      final log = <http.Request>[];
      await authProvider(log: log).authenticator.signIn(login: testLogin, password: testPassword);

      final login = Uri.splitQueryString(log[1].body);
      expect(login['loginID'], testLogin);
      expect(login['gmid'], 'synthetic-gmid');
      expect(login['ucid'], 'synthetic-ucid');
      final jwt = Uri.splitQueryString(log[2].body);
      expect(jwt['login_token'], 'st2.s.synthetic-login-token');
      expect(jwt['gmid'], 'synthetic-gmid');
      final platform = jsonDecode(log[3].body) as Map<String, dynamic>;
      expect(platform['jwt'], 'synthetic.identity.token');
      expect(platform['deviceId'], 'test-device');
    });

    test('puts the password in the login body only, never in a URL or the session', () async {
      final log = <http.Request>[];
      final session = await authProvider(log: log).authenticator.signIn(login: testLogin, password: testPassword);

      expect(log.where((r) => r.url.toString().contains(Uri.encodeQueryComponent(testPassword))), isEmpty);
      expect(log.where((r) => r.body.contains(Uri.encodeQueryComponent(testPassword))), hasLength(1));
      expect(jsonEncode(session.toJson()), isNot(contains(testPassword)));
    });
  });

  group('sign-in failures', () {
    test('a wrong password is reported as invalid credentials (recorded answer)', () async {
      final provider = authProvider(replies: {'login': (_) => gigyaReply('gigya_invalid_credentials')});
      final reason = failureOf(provider.authenticator.signIn(login: 'nobody@example.invalid', password: 'x'));
      expect(await reason, ReplayAuthFailure.invalidCredentials);
    });

    test('a lockout after too many attempts is reported as rate limited', () async {
      final provider = authProvider(replies: {'login': (_) => gigyaReply('synthetic_gigya_locked')});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: 'x')),
        ReplayAuthFailure.rateLimited,
      );
    });

    test('an HTTP 429 from any host is reported as rate limited', () async {
      final provider = authProvider(
        replies: {
          'redbeeLogin': (_) => http.Response('{}', 429, headers: {'retry-after': '20'}),
        },
      );
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: testPassword)),
        ReplayAuthFailure.rateLimited,
      );
    });

    test('an answer that asks for a captcha is reported as such', () async {
      final provider = authProvider(replies: {'login': (_) => gigyaReply('synthetic_gigya_captcha')});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: 'x')),
        ReplayAuthFailure.captchaRequired,
      );
    });

    test('a request without device identity is rejected (recorded answer)', () async {
      final provider = authProvider(replies: {'ids': (_) => gigyaReply('gigya_missing_device_identity')});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: 'x')),
        ReplayAuthFailure.rejected,
      );
    });

    test('a placeholder login token is rejected', () async {
      final provider = authProvider(replies: {'login': (_) => gigyaReply('synthetic_gigya_login_placeholder_token')});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: 'x')),
        ReplayAuthFailure.rejected,
      );
    });

    test('a refusal by the playback platform is rejected with its wording', () async {
      final provider = authProvider(
        replies: {
          'redbeeLogin': (_) => rtbfReply({'httpCode': 403, 'message': 'OVER_DEVICE_LIMIT'}, status: 403),
        },
      );
      try {
        await provider.authenticator.signIn(login: testLogin, password: testPassword);
        fail('Expected the sign-in to fail');
      } on ReplayAuthException catch (e) {
        expect(e.reason, ReplayAuthFailure.rejected);
        expect(e.message, 'Red Bee: OVER_DEVICE_LIMIT');
      }
    });

    test('a network failure is reported as such', () async {
      final provider = authProvider(replies: {'ids': (_) => throw const SocketException('unreachable')});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: 'x')),
        ReplayAuthFailure.network,
      );
    });

    test('a server error is reported as a network failure', () async {
      final provider = authProvider(replies: {'jwt': (_) => http.Response('', 503)});
      expect(
        await failureOf(provider.authenticator.signIn(login: testLogin, password: testPassword)),
        ReplayAuthFailure.network,
      );
    });
  });

  group('refresh', () {
    test('keeps a session the platform still accepts, without asking the identity service', () async {
      final log = <http.Request>[];
      final fresh = await authProvider(log: log).authenticator.refresh(storedSession());
      expect(rtbfSessionToken(fresh), sessionToken);
      expect(log.map((r) => r.url.path), ['/v2/customer/RTBF/businessunit/Auvio/auth/session']);
    });

    test('renews a dead session from the stored login token', () async {
      final provider = authProvider(replies: {'redbeeLogin': (_) => redbeeReply('synthetic_redbee_login_renewed')});
      final fresh = await provider.authenticator.refresh(storedSession(token: 'dead-token'));
      expect(rtbfSessionToken(fresh), renewedToken);
      expect(fresh.accountLabel, testLogin);
      expect(fresh.values['loginToken'], 'st2.s.synthetic-login-token');
      expect(fresh.expiresAt, DateTime.utc(2036, 4, 2, 8));
    });

    test('asks the user to sign in again when the login token is dead too (recorded answer)', () async {
      final provider = authProvider(replies: {'jwt': (_) => gigyaReply('gigya_unauthorized_user')});
      expect(
        await failureOf(provider.authenticator.refresh(storedSession(token: 'dead-token'))),
        ReplayAuthFailure.rejected,
      );
    });

    test('a session without a login token cannot be renewed', () async {
      final bare = ReplaySession(accountLabel: testLogin, values: const {'redbeeToken': 'dead-token'});
      expect(await failureOf(authProvider().authenticator.refresh(bare)), ReplayAuthFailure.rejected);
    });

    test('a network failure while checking is not mistaken for a dead session', () async {
      final provider = authProvider(replies: {'session': (_) => throw const SocketException('unreachable')});
      expect(await failureOf(provider.authenticator.refresh(storedSession())), ReplayAuthFailure.network);
    });
  });

  group('signed-in provider', () {
    test('sends the account session on the next playback request', () async {
      final (provider, log) = await signedInProvider();
      final playback = await provider.playback(rtbfRef('m3541035'));

      expect(playback.isPlayable, isTrue);
      expect(
        log.where((r) => r.url.path.contains('/entitlement/')).single.headers['Authorization'],
        'Bearer $sessionToken',
      );
      expect(log.where((r) => r.url.path.endsWith('/auth/anonymous')), isEmpty);
    });

    test('returns to anonymous playback after sign-out', () async {
      final (provider, log) = await signedInProvider();
      provider.useSession(null);
      await provider.playback(rtbfRef('m3541035'));

      expect(log.any((r) => r.url.path.endsWith('/auth/anonymous')), isTrue);
      final entitlement = log.firstWhere((r) => r.url.path.contains('/entitlement/'));
      expect(entitlement.headers['Authorization'], isNot('Bearer $sessionToken'));
    });

    test('an account-only publication counts as playable once signed in', () {
      final asset = rtbfJson('redbee_asset_login_required');
      expect(rtbfAvailabilityFromAsset(asset, rtbfNow), ReplayAvailability.loginRequired);
      expect(rtbfAvailabilityFromAsset(asset, rtbfNow, signedIn: true), ReplayAvailability.playable);
    });

    test('a dead session that cannot be renewed is reported, not swapped for an anonymous one', () async {
      final replies = <String, http.Response Function(http.Request)>{};
      final (provider, log) = await signedInProvider(replies: replies);
      replies['jwt'] = (_) => gigyaReply('gigya_unauthorized_user');
      provider.useSession(storedSession(token: 'dead-token'));
      final playback = await provider.playback(rtbfRef('m3541035'));

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.message, contains('session'));
      expect(log.any((r) => r.url.path.endsWith('/auth/anonymous')), isFalse);
    });
  });

  group('session renewal listener', () {
    test('is called with the renewed session when the platform rejects the token', () async {
      final (provider, log) = await signedInProvider(
        replies: {'redbeeLogin': (_) => redbeeReply('synthetic_redbee_login_renewed')},
      );
      final renewed = <ReplaySession>[];
      provider.onSessionRenewed = renewed.add;
      provider.useSession(storedSession(token: 'dead-token'));

      final playback = await provider.playback(rtbfRef('m3541035'));

      expect(playback.isPlayable, isTrue);
      expect(renewed, hasLength(1));
      expect(rtbfSessionToken(renewed.single), renewedToken);
      expect(renewed.single.values['loginToken'], 'st2.s.synthetic-login-token');
      final bearers = log.where((r) => r.url.path.contains('/entitlement/')).map((r) => r.headers['Authorization']);
      expect(bearers, ['Bearer dead-token', 'Bearer $renewedToken']);
    });

    test('is not called when the session is still accepted', () async {
      final (provider, _) = await signedInProvider();
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      await provider.playback(rtbfRef('m3541035'));
      expect(calls, 0);
    });

    test('is not called when renewal fails', () async {
      final replies = <String, http.Response Function(http.Request)>{};
      final (provider, _) = await signedInProvider(replies: replies);
      replies['jwt'] = (_) => gigyaReply('gigya_unauthorized_user');
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.useSession(storedSession(token: 'dead-token'));
      await provider.playback(rtbfRef('m3541035'));
      expect(calls, 0);
    });

    test('stops being called once it is cleared with null', () async {
      final (provider, _) = await signedInProvider(
        replies: {'redbeeLogin': (_) => redbeeReply('synthetic_redbee_login_renewed')},
      );
      var calls = 0;
      provider.onSessionRenewed = (_) => calls++;
      provider.onSessionRenewed = null;
      provider.useSession(storedSession(token: 'dead-token'));

      final playback = await provider.playback(rtbfRef('m3541035'));

      expect(playback.isPlayable, isTrue);
      expect(calls, 0);
    });
  });
}
