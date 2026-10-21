import '../../auth/replay_auth.dart';
import 'm6plus_auth_config.dart';
import 'm6plus_token_service.dart';

const _jwtKey = 'jwt';
const _loginTokenKey = 'loginToken';
const _deviceIdKey = 'deviceId';

/// Packs what a signed-in M6+ user needs into the neutral session: the bearer token, the stable device
/// identifier the token was issued for, and the login token that lets the session be renewed.
ReplaySession m6plusBuildSession({
  required String label,
  required M6plusJwt jwt,
  required String deviceId,
  String? loginToken,
}) => ReplaySession(
  accountLabel: label,
  values: {_jwtKey: jwt.token, _deviceIdKey: deviceId, _loginTokenKey: ?loginToken},
  expiresAt: jwt.expiresAt.subtract(m6plusSessionMargin),
);

String? m6plusBearerOf(ReplaySession session) => session.values[_jwtKey];

String? m6plusLoginTokenOf(ReplaySession session) => session.values[_loginTokenKey];

String? m6plusDeviceIdOf(ReplaySession session) => session.values[_deviceIdKey];
