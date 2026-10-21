import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import 'tf1plus_auth_transport.dart';
import 'tf1plus_json.dart';

/// Public key of the TF1+ web app, served to every visitor in the page configuration and in the
/// identity script URL. It names the site to Gigya and authenticates nobody.
const tf1GigyaApiKey = '3_hWgJdARhz_7l1oOp3a8BDLoR9cuWZpUaKG4aqF7gum9_iK3uTZ2VlDBl8ANf8FVk';

const _loginUrl = 'https://accounts.eu1.gigya.com/accounts.login';

/// What Gigya vouches for after a successful sign-in: the user id and its signature, which the TF1+
/// token endpoint accepts for a few minutes.
class Tf1GigyaIdentity {
  final String uid;
  final String signature;
  final int timestamp;

  const Tf1GigyaIdentity({required this.uid, required this.signature, required this.timestamp});
}

/// Signs in with e-mail address and password at Gigya, the identity service behind compte.tf1.fr.
Future<Tf1GigyaIdentity> tf1GigyaLogin(
  MediaServerHttpClient http, {
  required String login,
  required String password,
}) async {
  final response = await tf1AuthPost(
    http,
    _loginUrl,
    contentType: 'application/x-www-form-urlencoded',
    body: tf1FormBody({
      'apiKey': tf1GigyaApiKey,
      'loginID': login,
      'password': password,
      'loginMode': 'standard',
      'format': 'json',
    }),
  );
  final body = tf1AuthJson(response.data);
  final code = (body['errorCode'] as num?)?.toInt();
  if (code == null) throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'Unexpected answer');
  if (code != 0) throw tf1GigyaFailure(code, body);

  final uid = tf1Text(body['UID']);
  final signature = tf1Text(body['UIDSignature']);
  final timestamp = int.tryParse('${body['signatureTimestamp']}');
  if (uid == null || signature == null || timestamp == null) {
    throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'Sign-in answer incomplete');
  }
  return Tf1GigyaIdentity(uid: uid, signature: signature, timestamp: timestamp);
}

/// Maps a Gigya error. The numbers are the ones the TF1+ web app itself tests for.
ReplayAuthException tf1GigyaFailure(int code, Map<String, dynamic> body) {
  final reason = switch (code) {
    403042 || 403047 => ReplayAuthFailure.invalidCredentials,
    403048 || 403120 => ReplayAuthFailure.rateLimited,
    _ when _mentionsCaptcha(body) => ReplayAuthFailure.captchaRequired,
    >= 500000 => ReplayAuthFailure.network,
    _ => ReplayAuthFailure.rejected,
  };
  return ReplayAuthException(reason, message: tf1Text(body['errorMessage']) ?? 'Gigya error $code');
}

/// Gigya has no dedicated code for a challenge, so it is recognised by wording.
bool _mentionsCaptcha(Map<String, dynamic> body) {
  final text = '${body['errorMessage']} ${body['errorDetails']}'.toLowerCase();
  return text.contains('captcha');
}
