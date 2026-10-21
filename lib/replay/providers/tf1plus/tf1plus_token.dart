import 'dart:convert';

import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'tf1plus_auth_transport.dart';
import 'tf1plus_gigya.dart';
import 'tf1plus_json.dart';

const _exchangeUrl = 'https://www.tf1.fr/token/gigya/web';
const _refreshUrl = 'https://www.tf1.fr/token/refresh';

/// The one consent the web app sends when it has no consent banner to read from.
const _technicalConsent = 'technique-HWZ9HRWz';

/// How long before its real end a token counts as expired, so a refresh finishes before a request fails.
const tf1TokenMargin = Duration(minutes: 1);

/// The broadcaster's credentials for a signed-in user.
class Tf1Tokens {
  /// Bearer token for the media info route, a JWT.
  final String accessToken;

  /// Value of the `refresh_token` cookie the token routes set, or null when none came back.
  final String? refreshToken;
  final DateTime? expiresAt;

  const Tf1Tokens({required this.accessToken, this.refreshToken, this.expiresAt});
}

/// Trades a Gigya identity for a TF1+ bearer token.
Future<Tf1Tokens> tf1ExchangeIdentity(MediaServerHttpClient http, Tf1GigyaIdentity identity) async {
  final response = await tf1AuthPost(
    http,
    _exchangeUrl,
    contentType: 'application/json',
    body: jsonEncode({
      'UID': identity.uid,
      'signature': identity.signature,
      'timestamp': identity.timestamp,
      'consent_ids': [_technicalConsent],
    }),
  );
  return _tokensFrom(response);
}

/// Asks for a new token with the refresh cookie of the previous one.
Future<Tf1Tokens> tf1RefreshToken(MediaServerHttpClient http, String refreshToken) async {
  final response = await tf1AuthPost(
    http,
    _refreshUrl,
    contentType: 'application/json',
    headers: {'Cookie': 'refresh_token=$refreshToken'},
    body: jsonEncode({
      'consent_ids': [_technicalConsent],
    }),
  );
  return _tokensFrom(response, previousRefresh: refreshToken);
}

Tf1Tokens _tokensFrom(MediaServerResponse response, {String? previousRefresh}) {
  final status = response.statusCode;
  if (status >= 500) throw ReplayAuthException(ReplayAuthFailure.network, message: 'HTTP $status');
  final body = tf1AuthJson(response.data);
  if (status >= 400) {
    throw ReplayAuthException(ReplayAuthFailure.rejected, message: tf1Text(body['error']) ?? 'HTTP $status');
  }
  final token = tf1Text(body['token']);
  if (token == null) throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'No token in answer');
  final expiry = tf1JwtExpiry(token);
  return Tf1Tokens(
    accessToken: token,
    refreshToken: _refreshCookie(response.headers) ?? previousRefresh,
    expiresAt: expiry?.subtract(tf1TokenMargin),
  );
}

/// The refresh cookie from a `Set-Cookie` header, which the HTTP client joins with commas when several
/// were sent. An emptied cookie, which is how the server ends a session, gives null.
String? _refreshCookie(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'set-cookie') continue;
    final match = RegExp(r'(?:^|[\s,;])refresh_token=([^;,\s]+)').firstMatch(entry.value);
    if (match != null) return match.group(1);
  }
  return null;
}

/// When a JWT ends, from its `exp` claim, or null when the token is not a readable JWT.
DateTime? tf1JwtExpiry(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = claims is Map ? claims['exp'] : null;
    return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true) : null;
  } on FormatException {
    return null;
  }
}
