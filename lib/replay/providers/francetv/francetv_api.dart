import 'dart:async';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';

/// The broadcaster refused a request because too many were made in a short time.
class FranceTvRateLimitedException implements Exception {
  final Duration retryAfter;

  const FranceTvRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// The answer of the stream-info endpoint, which reports refusals as a 4xx with a JSON body.
class FranceTvStreamResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const FranceTvStreamResponse(this.statusCode, this.body);
}

/// Thin JSON access to the France.tv catalogue API, the content API and the stream-info endpoint.
///
/// Only the API hosts are used, never the www.france.tv pages, whose robots.txt disallows automated access.
class FranceTvApi {
  static const _mobileHost = 'api-mobile.yatta.francetv.fr';
  static const _contentHost = 'api-front.yatta.francetv.fr';
  static const _streamHost = 'k7.ftven.fr';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };
  static const _cacheTtl = Duration(minutes: 5);
  static const _cacheLimit = 24;

  final MediaServerHttpClient _http;

  /// ISO 3166 alpha-2 code of the viewer's country, always sent with a stream request so the
  /// broadcaster applies its own rights check.
  final String countryCode;
  final Duration _requestGap;
  final Map<String, ({DateTime at, Map<String, dynamic> body})> _cache = {};
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);

  FranceTvApi(this._http, {String countryCode = 'BE', this._requestGap = const Duration(milliseconds: 150)})
    : countryCode = _validCountry(countryCode);

  /// A catalogue page. [path] is relative to the API root, for example `apps/program/france-2_dix-pour-cent`.
  Future<Map<String, dynamic>> mobile(String path, {Map<String, String> query = const {}, String platform = 'apps'}) =>
      _cached(Uri.https(_mobileHost, '/$path', {'platform': platform, ...query}));

  /// The raw content record of one video.
  Future<Map<String, dynamic>> content(int contentId) =>
      _cached(Uri.https(_contentHost, '/standard/publish/contents/$contentId'));

  /// How to play one video, or why not. Never cached: rights and links change with the moment.
  ///
  /// The HLS profile is requested. The country is the viewer's own, so the broadcaster's rights check
  /// decides, and a refusal comes back as a 4xx body that the caller reads.
  Future<FranceTvStreamResponse> stream(String streamId) async {
    final uri = Uri.https(_streamHost, '/videos/$streamId', {
      'device_type': 'mobile',
      'browser': 'safari',
      'domain': 'www.france.tv',
      'country_code': countryCode,
    });
    final response = await _get(uri);
    final data = response.data;
    return FranceTvStreamResponse(response.statusCode, data is Map<String, dynamic> ? data : const {});
  }

  /// Signs a manifest address with the token service named by the stream-info answer.
  Future<String?> signedManifest(Uri tokenService, Uri manifest) async {
    final query = {...tokenService.queryParameters, 'url': manifest.toString()};
    final response = await _get(tokenService.replace(queryParameters: query));
    throwIfHttpError(response);
    final data = response.data;
    return data is Map<String, dynamic> ? data['url'] as String? : null;
  }

  Future<Map<String, dynamic>> _cached(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheTtl) return hit.body;
    final response = await _get(uri);
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
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = (at: DateTime.now(), body: data);
    return data;
  }

  Future<MediaServerResponse> _get(Uri uri) async {
    await _waitForSlot();
    final response = await _http.get(uri.toString(), headers: _headers);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw FranceTvRateLimitedException(Duration(seconds: seconds));
    }
    return response;
  }

  /// Spaces request starts by the configured gap, so a screen that fans out does not burst.
  Future<void> _waitForSlot() async {
    final now = DateTime.now();
    final start = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = start.add(_requestGap);
    final wait = start.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  static String _validCountry(String code) {
    final upper = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(upper)) {
      throw ArgumentError.value(code, 'countryCode', 'expected a two-letter ISO 3166 country code');
    }
    return upper;
  }
}
