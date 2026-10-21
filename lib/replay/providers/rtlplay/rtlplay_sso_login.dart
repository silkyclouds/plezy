import 'dart:convert';

import '../../auth/replay_auth.dart';
import 'rtlplay_web_client.dart';

final _loginEndpoint = Uri.parse('https://$rtlPlaySsoHost/api/account/login');

/// Statuses of the login endpoint, grouped by what the user can do about them. The endpoint answers HTTP
/// 200 with a failure status in the body, so the body decides.
const _wrongCredentials = {'INVALID_EMAIL_CREDENTIALS', 'INVALID_PASSWORD_CREDENTIALS', 'INVALID_CREDENTIALS'};
const _captcha = {'CAPTCHA_REQUIRED', 'LOGIN_FAILED_MISSING_CAPTCHA', 'LOGIN_FAILED_WRONG_CAPTCHA'};
const _tooManyAttempts = {'TOO_MANY_REQUESTS', 'FREQUENCY_LIMIT_REACHED', 'LIMIT_REACHED'};

/// Signs in on the SSO account service the way its own page does and returns the account session token
/// the next step of the web flow needs. [createdBy] and [brand] are the values the site passed along.
Future<String> rtlPlaySsoLogin(
  RtlPlayWebClient web, {
  required String login,
  required String password,
  required String createdBy,
  required String brand,
}) async {
  final response = await web.postJson(
    _loginEndpoint,
    {'username': login.trim(), 'password': password.trim()},
    headers: {
      'accept': 'application/json',
      'origin': 'https://$rtlPlaySsoHost',
      'sso-createdby': createdBy,
      'sso-brand': brand,
      'sso-nocookie': '1',
    },
  );
  if (response.status == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
  if (response.status >= 500) {
    throw ReplayAuthException(ReplayAuthFailure.network, message: 'HTTP ${response.status}');
  }
  final body = _decode(response.body);
  final status = body?['status'];
  if (status is! String) throw ReplayAuthException(ReplayAuthFailure.rejected, message: 'HTTP ${response.status}');
  if (status != 'SUCCESS') throw _failureFor(status);
  final token = _sessionToken(body);
  if (token == null) throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'No session in the answer');
  return token;
}

Map<String, dynamic>? _decode(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String? _sessionToken(Map<String, dynamic>? body) {
  final data = body?['data'];
  final account = data is Map<String, dynamic> ? data['userAccount'] : null;
  final session = account is Map<String, dynamic> ? account['session'] : null;
  final token = session is Map<String, dynamic> ? session['encryptedToken'] : null;
  return token is String && token.isNotEmpty ? token : null;
}

ReplayAuthException _failureFor(String status) {
  if (_wrongCredentials.contains(status)) return const ReplayAuthException(ReplayAuthFailure.invalidCredentials);
  if (_captcha.contains(status)) return const ReplayAuthException(ReplayAuthFailure.captchaRequired);
  if (_tooManyAttempts.contains(status)) return const ReplayAuthException(ReplayAuthFailure.rateLimited);
  return ReplayAuthException(ReplayAuthFailure.rejected, message: status);
}
