import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

const drtvUserAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';

/// The anonymous token DR's own web app asks for on every visit. It opens no account and carries no identity.
class DrtvSession {
  static const _url = 'https://isl.dr-massive.com/api/authorization/anonymous-sso';
  static const _fallbackLifetime = Duration(hours: 8);
  static const _margin = Duration(minutes: 5);

  final MediaServerHttpClient _http;
  final String Function() _newDeviceId;
  final DateTime Function() _now;

  String? _token;
  DateTime? _expires;
  Future<String>? _pending;

  DrtvSession(this._http, {required this._newDeviceId, required DateTime Function() clock}) : _now = clock;

  Future<String> token() {
    final current = _token;
    final expires = _expires;
    if (current != null && expires != null && _now().isBefore(expires.subtract(_margin))) {
      return Future.value(current);
    }
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  /// Forgets the token, after the catalogue refused it.
  void invalidate() {
    _token = null;
    _expires = null;
  }

  Future<String> _fetch() async {
    final response = await _http.post(
      _url,
      queryParameters: const {
        'device': 'web_browser',
        'ff': 'idp,ldp,rpt',
        'lang': 'da',
        'supportFallbackToken': 'true',
      },
      headers: const {'Accept': 'application/json', 'User-Agent': drtvUserAgent},
      body: {
        'deviceId': _newDeviceId(),
        'scopes': ['Catalog'],
        'optout': true,
      },
    );
    throwIfHttpError(response);
    final data = response.data;
    final first = data is List && data.isNotEmpty ? data.first : null;
    final value = first is Map<String, dynamic> ? first['value'] : null;
    if (value is! String || value.isEmpty) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: response.requestUri,
        message: 'No token in the sign-in response',
      );
    }
    _token = value;
    final expiry = DateTime.tryParse('${(first as Map)['expirationDate'] ?? ''}');
    _expires = expiry ?? _now().add(_fallbackLifetime);
    return value;
  }
}
