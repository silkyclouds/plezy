import 'dart:async';
import 'dart:convert';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The web app that ships the API settings to every visitor.
const orfWebPage = 'https://on.orf.at/';

const _defaultApiBase = 'https://api-tvthek.orf.at/api/v4.3/';

/// The API settings could not be read from the web app's page.
class OrfCredentialsException implements Exception {
  const OrfCredentialsException();

  @override
  String toString() => 'The ORF ON page no longer carries its API settings';
}

/// Address and Basic-auth pair of the ORF ON API, as the web app publishes them in its own page.
class OrfApiSettings {
  final Uri baseUri;
  final String _user;
  final String _password;

  const OrfApiSettings(this.baseUri, this._user, this._password);

  /// Value of the `Authorization` header. Only ever sent to the API host.
  String get authorization => 'Basic ${base64Encode(utf8.encode('$_user:$_password'))}';
}

final _apiObject = RegExp(r'''\bapi["']?\s*:\s*\{([^{}]*\bpassword["']?\s*:[^{}]*)\}''');

/// Reads the `api` object of the web app's inline configuration, or returns null when it is not there.
///
/// The settings are only taken from a page of the broadcaster; a base address outside `orf.at` is ignored so the
/// credentials can never be sent to another host.
OrfApiSettings? parseOrfApiSettings(String page) {
  final body = _apiObject.firstMatch(page)?.group(1);
  if (body == null) return null;
  final user = _stringField(body, 'user');
  final password = _stringField(body, 'password');
  if (user == null || password == null) return null;
  return OrfApiSettings(_trustedBase(_stringField(body, 'baseUrl')), user, password);
}

String? _stringField(String body, String name) {
  final match = RegExp('(?:^|[\\s,{"\'])$name["\']?\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(body);
  final raw = match?.group(1);
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode('"$raw"') as String;
  } on FormatException {
    return raw;
  }
}

Uri _trustedBase(String? candidate) {
  final uri = candidate == null ? null : Uri.tryParse(candidate);
  final trusted = uri != null && uri.scheme == 'https' && (uri.host == 'orf.at' || uri.host.endsWith('.orf.at'));
  final base = trusted ? candidate! : _defaultApiBase;
  return Uri.parse(base.endsWith('/') ? base : '$base/');
}

/// Fetches the API settings once and hands them to every request. [refresh] reads the page again, which is what a
/// new web build needs after the old pair stops working.
class OrfCredentials {
  final MediaServerHttpClient _http;
  final Map<String, String> _headers;
  Future<OrfApiSettings>? _loading;

  OrfCredentials(this._http, this._headers);

  Future<OrfApiSettings> current() => _loading ??= _load();

  Future<OrfApiSettings> refresh() => _loading = _load();

  Future<OrfApiSettings> _load() async {
    try {
      final response = await _http.get(orfWebPage, headers: _headers);
      throwIfHttpError(response);
      final data = response.data;
      final settings = data is String ? parseOrfApiSettings(data) : null;
      if (settings == null) throw const OrfCredentialsException();
      return settings;
    } on OrfCredentialsException {
      _loading = null;
      rethrow;
    } on MediaServerHttpException {
      _loading = null;
      rethrow;
    }
  }
}
