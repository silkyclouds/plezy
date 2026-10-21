import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'm6plus_auth_config.dart';
import 'm6plus_gigya.dart';

/// The broadcaster's own token for one user and the moment it stops working.
class M6plusJwt {
  final String token;
  final DateTime expiresAt;

  const M6plusJwt(this.token, this.expiresAt);
}

/// Exchanges a signed identity for the token the catalogue API expects as a bearer.
class M6plusTokenService {
  final MediaServerHttpClient _http;

  M6plusTokenService(this._http);

  Future<M6plusJwt> exchange(M6plusGigyaUser user, {required String deviceId}) async {
    final MediaServerResponse response;
    try {
      response = await _http.get(
        m6plusGetJwtUrl,
        headers: {
          'Accept': 'application/json',
          'User-Agent': m6plusAuthUserAgent,
          'X-Customer-Name': m6plusCustomer,
          'X-Client-Release': m6plusClientRelease,
          'x-auth-device-id': deviceId,
          'X-Auth-gigya-uid': user.uid,
          'X-Auth-gigya-signature': user.signature,
          'X-Auth-gigya-signature-timestamp': user.signatureTimestamp,
        },
      );
    } on MediaServerHttpException {
      throw const ReplayAuthException(ReplayAuthFailure.network);
    }
    final status = response.statusCode;
    if (status == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
    if (status >= 500) throw const ReplayAuthException(ReplayAuthFailure.network);
    final body = _object(response.data);
    if (status >= 400) throw ReplayAuthException(ReplayAuthFailure.rejected, message: _errorMessage(body));
    final token = body?['token'];
    final expiry = token is String ? m6plusJwtExpiry(token) : null;
    if (token is! String || expiry == null) {
      throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'The token answer was not understood.');
    }
    return M6plusJwt(token, expiry);
  }

  Map<String, dynamic>? _object(Object? data) {
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _errorMessage(Map<String, dynamic>? body) {
    final error = body?['error'];
    return error is Map ? error['message']?.toString() : null;
  }
}

/// The `exp` claim of a JWT, or null when [token] is not a readable JWT. The signature is not checked:
/// the server is the only party that can.
DateTime? m6plusJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = claims is Map ? claims['exp'] : null;
    return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true) : null;
  } on FormatException {
    return null;
  }
}
