import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_api.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_authenticator.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'tf1plus_fixture_server.dart';

const _authFixtures = 'test/replay/fixtures/tf1plus/auth';

String tf1AuthFixture(String name) => File('$_authFixtures/$name.json').readAsStringSync();

/// A JWT with the given expiry. The signature segment is a placeholder: nothing here verifies it.
String tf1SyntheticJwt(DateTime expires) {
  String segment(Map<String, Object?> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = expires.millisecondsSinceEpoch ~/ 1000;
  return '${segment({'alg': 'none'})}.${segment({'exp': exp})}.synthetic';
}

http.Response tf1Json(String body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response(body, status, headers: {'content-type': 'application/json', ...headers});

/// The account routes of Gigya and TF1+, scripted per test, plus the media info route.
class Tf1AccountServer {
  final List<http.Request> requests = [];

  http.Response Function(http.Request) gigya = (_) => tf1Json(tf1AuthFixture('gigya_login_ok_synthetic'));
  http.Response Function(http.Request) exchange = (_) => throw StateError('exchange not scripted');
  http.Response Function(http.Request) refresh = (_) => throw StateError('refresh not scripted');
  http.Response Function(http.Request) mediaInfo = (_) => tf1Json(jsonEncode(tf1Fixture('mediainfo_denied_login')));

  MediaServerHttpClient get client => MediaServerHttpClient(client: MockClient((r) async => _route(r)));

  Tf1Authenticator get authenticator => Tf1Authenticator(client);

  Tf1PlusProvider provider() => Tf1PlusProvider.withApi(Tf1Api(client, pacing: Tf1Pacing.none));

  List<http.Request> to(String host, [String? path]) => [
    for (final r in requests)
      if (r.url.host == host && (path == null || r.url.path == path)) r,
  ];

  http.Response _route(http.Request request) {
    requests.add(request);
    return switch ((request.url.host, request.url.path)) {
      ('accounts.eu1.gigya.com', '/accounts.login') => gigya(request),
      ('www.tf1.fr', '/token/gigya/web') => exchange(request),
      ('www.tf1.fr', '/token/refresh') => refresh(request),
      ('mediainfo.tf1.fr', _) => mediaInfo(request),
      _ => throw StateError('unexpected request to ${request.url}'),
    };
  }
}

extension Tf1FormRequest on http.Request {
  /// The fields of a form-encoded body.
  Map<String, String> get bodyFields => Uri.splitQueryString(body);
}
