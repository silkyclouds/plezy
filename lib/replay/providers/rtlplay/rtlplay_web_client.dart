import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'rtlplay_cookie_jar.dart';

const rtlPlayWebHost = 'www.rtlplay.be';
const rtlPlaySsoHost = 'sso.rtl.be';

const _hosts = {rtlPlayWebHost, rtlPlaySsoHost};
const _timeout = Duration(seconds: 20);
const _userAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';

/// One answer from RTL's web or SSO host, with the body already read.
class RtlPlayWebResponse {
  final int status;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  const RtlPlayWebResponse({required this.status, required this.uri, required this.headers, required this.body});

  bool get isRedirect => status >= 300 && status < 400 && location != null;

  String? get location => headers['location'];

  /// The redirect target resolved against the request address.
  Uri? get redirectTarget => location == null ? null : uri.resolve(location!);
}

/// Plain HTTP against the two hosts of the web sign-in, with cookies and redirects handled by hand.
///
/// The sign-in hands tokens over in redirect chains, so every hop must be seen: this client follows a
/// redirect only to RTL's own two hosts, which keeps the session token from ever leaving them. It
/// deliberately bypasses the app's logging client, whose debug log prints request addresses.
class RtlPlayWebClient {
  final http.Client _client;
  final RtlPlayCookieJar jar;

  RtlPlayWebClient(this._client, this.jar);

  Future<RtlPlayWebResponse> get(Uri uri, {Map<String, String> headers = const {}}) => _send('GET', uri, headers, null);

  Future<RtlPlayWebResponse> postJson(Uri uri, Map<String, Object?> body, {Map<String, String> headers = const {}}) =>
      _send('POST', uri, {...headers, 'content-type': 'application/json'}, jsonEncode(body));

  /// Follows redirects from [start] until a hop answers with something else, [stopWhen] says enough, or
  /// a redirect leaves RTL's hosts. The last response is returned.
  Future<RtlPlayWebResponse> follow(
    Uri start, {
    bool Function(RtlPlayWebResponse response)? stopWhen,
    int maxHops = 10,
  }) async {
    var response = await get(start);
    for (var hop = 0; hop < maxHops; hop++) {
      final target = response.redirectTarget;
      if (!response.isRedirect || target == null || !isRtlPlayHost(target)) return response;
      if (stopWhen != null && stopWhen(response)) return response;
      response = await get(target);
    }
    return response;
  }

  static bool isRtlPlayHost(Uri uri) => uri.scheme == 'https' && _hosts.contains(uri.host);

  Future<RtlPlayWebResponse> _send(String method, Uri uri, Map<String, String> headers, String? body) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)..followRedirects = false;
    request.headers.addAll({'user-agent': _userAgent, ...headers});
    final cookie = jar.header(uri.host);
    if (cookie != null) request.headers['cookie'] = cookie;
    if (body != null) request.body = body;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      jar.store(uri.host, response.headers['set-cookie']);
      return RtlPlayWebResponse(
        status: response.statusCode,
        uri: uri,
        headers: response.headers,
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on TimeoutException {
      abort.complete();
      rethrow;
    }
  }
}
