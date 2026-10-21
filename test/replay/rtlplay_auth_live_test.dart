import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

/// Sends one deliberately invalid sign-in to the real site. Run with
/// `PLEZY_LIVE_TESTS=1 flutter test test/replay/rtlplay_auth_live_test.dart`. It never uses a real account.
void main() {
  final live = Platform.environment['PLEZY_LIVE_TESTS'] == '1';

  test('a made-up account is refused as invalid credentials', () async {
    final provider = RtlPlayProvider(MediaServerHttpClient());
    await expectLater(
      provider.authenticator.signIn(login: 'nobody@example.invalid', password: 'not-a-real-password-1'),
      throwsA(isA<ReplayAuthException>().having((e) => e.reason, 'reason', ReplayAuthFailure.invalidCredentials)),
    );
  }, skip: live ? false : 'set PLEZY_LIVE_TESTS=1 to reach the network');
}
