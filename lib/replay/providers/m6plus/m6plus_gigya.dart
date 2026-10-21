import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'm6plus_auth_config.dart';

/// A signed identity as the identity service issues it. The broadcaster's token endpoint verifies the signature.
class M6plusGigyaUser {
  final String uid;
  final String signature;

  /// Seconds since the epoch, as text, exactly as issued: it is part of what was signed.
  final String signatureTimestamp;

  /// Lets the same identity be signed again later without the password. Null when the service sent none.
  final String? loginToken;

  const M6plusGigyaUser({
    required this.uid,
    required this.signature,
    required this.signatureTimestamp,
    this.loginToken,
  });
}

/// The two identity calls the web app makes: `accounts.login` with the typed credentials, and
/// `accounts.getAccountInfo` with the login token to get a fresh signature.
class M6plusGigya {
  final MediaServerHttpClient _http;

  M6plusGigya(this._http);

  /// The password travels only in the POST body of this one request and is never kept.
  Future<M6plusGigyaUser> login(String loginId, String password) =>
      _user('accounts.login', {'loginID': loginId, 'password': password});

  Future<M6plusGigyaUser> accountInfo(String loginToken) =>
      _user('accounts.getAccountInfo', {'login_token': loginToken});

  Future<M6plusGigyaUser> _user(String method, Map<String, String> params) async {
    final body = await _call(method, params);
    final uid = body['UID'];
    final signature = body['UIDSignature'];
    final timestamp = body['signatureTimestamp'];
    if (uid is! String || signature is! String || timestamp == null) {
      throw const ReplayAuthException(
        ReplayAuthFailure.rejected,
        message: 'The identity service sent no signed identity.',
      );
    }
    final session = body['sessionInfo'];
    final token = session is Map ? session['cookieValue'] : null;
    return M6plusGigyaUser(
      uid: uid,
      signature: signature,
      signatureTimestamp: '$timestamp',
      loginToken: token is String && token.isNotEmpty ? token : null,
    );
  }

  Future<Map<String, dynamic>> _call(String method, Map<String, String> params) async {
    final MediaServerResponse response;
    try {
      response = await _http.post(
        'https://$m6plusGigyaHost/$method',
        headers: const {'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': m6plusAuthUserAgent},
        body: Uri(queryParameters: {'apiKey': m6plusGigyaApiKey, 'format': 'json', ...params}).query,
      );
    } on MediaServerHttpException {
      throw const ReplayAuthException(ReplayAuthFailure.network);
    }
    if (response.statusCode == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
    final body = _decode(response.data);
    if (body == null) {
      throw ReplayAuthException(
        response.statusCode >= 500 ? ReplayAuthFailure.network : ReplayAuthFailure.rejected,
        message: 'Unreadable answer from the identity service.',
      );
    }
    final code = body['errorCode'];
    if (code is int && code != 0) throw m6plusGigyaFailure(body);
    return body;
  }

  Map<String, dynamic>? _decode(Object? data) {
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

/// Maps an identity-service error body to the failure the sign-in screen can act on.
ReplayAuthException m6plusGigyaFailure(Map<String, dynamic> body) {
  final code = body['errorCode'] as int? ?? 0;
  final message = (body['errorDetails'] ?? body['errorMessage'])?.toString();
  final reason = switch (code) {
    _ when '${body['errorDetails']} ${body['errorMessage']}'.toLowerCase().contains('captcha') =>
      ReplayAuthFailure.captchaRequired,
    403042 || 403005 || 400006 => ReplayAuthFailure.invalidCredentials,
    403120 => ReplayAuthFailure.rateLimited,
    >= 500000 && < 600000 => ReplayAuthFailure.network,
    _ => ReplayAuthFailure.rejected,
  };
  return ReplayAuthException(reason, message: message);
}
