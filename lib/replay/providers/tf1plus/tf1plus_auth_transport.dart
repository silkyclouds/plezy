import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';

const _headers = {'Accept': 'application/json', 'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'};

/// Form body for an account endpoint. Credentials travel in the body, never in the URL.
String tf1FormBody(Map<String, String> fields) => Uri(queryParameters: fields).query;

/// POSTs to an account endpoint. Transport trouble becomes [ReplayAuthFailure.network] and an HTTP 429
/// becomes [ReplayAuthFailure.rateLimited], so callers only read the answer.
Future<MediaServerResponse> tf1AuthPost(
  MediaServerHttpClient http,
  String url, {
  required String contentType,
  required String body,
  Map<String, String> headers = const {},
}) async {
  final MediaServerResponse response;
  try {
    response = await http.post(url, headers: {..._headers, 'Content-Type': contentType, ...headers}, body: body);
  } on MediaServerHttpException catch (e) {
    throw ReplayAuthException(ReplayAuthFailure.network, message: e.type.name);
  }
  if (response.statusCode == 429) throw const ReplayAuthException(ReplayAuthFailure.rateLimited);
  return response;
}

/// The JSON object an account endpoint answered with. Gigya labels its JSON as JavaScript, so the body
/// may still be text. Anything else is a [ReplayAuthFailure.rejected].
Map<String, dynamic> tf1AuthJson(Object? data) {
  try {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Falls through to the rejection below.
  }
  throw const ReplayAuthException(ReplayAuthFailure.rejected, message: 'Unexpected answer');
}
