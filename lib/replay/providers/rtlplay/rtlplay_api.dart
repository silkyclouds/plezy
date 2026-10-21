import 'package:http/http.dart' as http;

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class RtlPlayRateLimitedException implements Exception {
  final Duration retryAfter;

  const RtlPlayRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Every app version the catalogue accepts was refused, so the version window has moved on.
class RtlPlayVersionRejectedException implements Exception {
  const RtlPlayVersionRejectedException();

  @override
  String toString() => 'RTL Play no longer accepts this app version';
}

/// App builds the catalogue accepts; it answers 426 to anything outside a narrow, moving window.
const rtlPlayAppVersions = [25, 26, 27, 28];

/// Thin JSON access to RTL Play's anonymous catalogue.
class RtlPlayApi {
  static const _base = 'https://lfvp-api.dpgmedia.net/RTL_PLAY';
  static const _ttl = Duration(minutes: 5);

  final MediaServerHttpClient _http;
  final Map<String, ({DateTime at, Map<String, dynamic>? body})> _cache = {};
  int _versionIndex = 0;

  RtlPlayApi(this._http);

  /// The raw transport, for the sign-in and stream calls that must see redirects and cookies themselves.
  http.Client get transport => _http.inner;

  Future<Map<String, dynamic>?> storefront(String id) =>
      _get('storefronts/$id', {'itemsPerSwimlane': '20', 'hideBannerRow': 'true'});

  /// The whole content of one row, for rows the storefront marks as having a detail page.
  Future<Map<String, dynamic>?> rowDetail(String storefront, String rowId) =>
      _get('storefronts/$storefront/detail/$rowId');

  /// A programme with the episodes of one season; the first season when [season] is null.
  /// Null when the programme or season does not exist.
  Future<Map<String, dynamic>?> detail(String id, {int? season}) =>
      _get('detail3/$id', season == null ? null : {'selectedSeasonIndex': '$season'});

  Future<Map<String, dynamic>?> search(String query) => _get('search', {'query': query});

  Future<Map<String, dynamic>?> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: query);
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.body;
    final body = await _fetch(uri);
    _cache[key] = (at: DateTime.now(), body: body);
    return body;
  }

  Future<Map<String, dynamic>?> _fetch(Uri uri) async {
    for (var attempt = _versionIndex; attempt < rtlPlayAppVersions.length; attempt++) {
      final response = await _http.get(uri.toString(), headers: _headers(rtlPlayAppVersions[attempt]));
      if (response.statusCode == 426) continue;
      _versionIndex = attempt;
      return _body(response, uri);
    }
    throw const RtlPlayVersionRejectedException();
  }

  Map<String, dynamic>? _body(MediaServerResponse response, Uri uri) {
    if (response.statusCode == 404) return null;
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw RtlPlayRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw MediaServerHttpException(
        type: MediaServerHttpErrorType.unknown,
        statusCode: response.statusCode,
        requestUri: uri,
        message: 'Unexpected response shape',
      );
    }
    return data;
  }

  Map<String, String> _headers(int version) => {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
    'x-app-version': '$version',
  };
}
