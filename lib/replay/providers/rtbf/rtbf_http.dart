import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

const _formType = 'application/x-www-form-urlencoded';
const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';

/// The broadcaster refused a request because too many were made in a short time.
class RtbfRateLimitedException implements Exception {
  final Duration retryAfter;

  const RtbfRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// A decoded JSON answer whose status code the caller interprets.
class RtbfAnswer {
  final int status;
  final Map<String, dynamic> body;

  const RtbfAnswer(this.status, this.body);

  bool get isOk => status >= 200 && status < 300;
}

/// JSON and text requests with the identifying headers every Auvio host receives.
class RtbfHttp {
  final MediaServerHttpClient _client;

  RtbfHttp(this._client);

  /// Status codes in [tolerate] are returned instead of thrown, so the caller can read the error body.
  Future<RtbfAnswer> getJson(String url, {Map<String, String> headers = const {}, Set<int> tolerate = const {}}) async {
    final response = await _client.get(
      url,
      headers: {'Accept': 'application/json', 'User-Agent': _userAgent, ...headers},
    );
    return _answer(response, url, tolerate);
  }

  Future<RtbfAnswer> postJson(
    String url,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
    Set<int> tolerate = const {},
  }) async {
    final response = await _client.post(
      url,
      headers: {'Accept': 'application/json', 'User-Agent': _userAgent, ...headers},
      body: body,
    );
    return _answer(response, url, tolerate);
  }

  /// A form-encoded POST whose answer is JSON. Gigya labels its JSON `text/javascript`, so a text
  /// body is decoded here.
  Future<RtbfAnswer> postForm(String url, Map<String, String> fields, {Set<int> tolerate = const {}}) async {
    final response = await _client.post(
      url,
      headers: {'Accept': 'application/json', 'User-Agent': _userAgent, 'Content-Type': _formType},
      body: Uri(queryParameters: fields).query,
    );
    return _answer(_withJsonBody(response), url, tolerate);
  }

  Future<String> getText(String url) async {
    final response = await _client.get(url, headers: {'User-Agent': _userAgent});
    throwIfHttpError(response);
    final data = response.data;
    return data is String ? data : '';
  }

  MediaServerResponse _withJsonBody(MediaServerResponse response) {
    final data = response.data;
    if (data is! String) return response;
    try {
      return MediaServerResponse(
        statusCode: response.statusCode,
        data: jsonDecode(data),
        headers: response.headers,
        requestUri: response.requestUri,
      );
    } on FormatException {
      return response;
    }
  }

  RtbfAnswer _answer(MediaServerResponse response, String url, Set<int> tolerate) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw RtbfRateLimitedException(Duration(seconds: seconds));
    }
    final tolerated = tolerate.contains(response.statusCode);
    if (!tolerated) throwIfHttpError(response);
    final data = response.data;
    if (data is Map<String, dynamic>) return RtbfAnswer(response.statusCode, data);
    if (tolerated) return RtbfAnswer(response.statusCode, const {});
    throw MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      statusCode: response.statusCode,
      requestUri: Uri.parse(url),
      message: 'Unexpected response shape',
    );
  }
}
