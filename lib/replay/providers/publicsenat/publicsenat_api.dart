import 'dart:async';

import '../../../utils/media_server_http_client.dart';
import 'publicsenat_models.dart';
import 'publicsenat_parser.dart';

/// The site asked for fewer requests.
class PublicSenatRateLimitedException implements Exception {
  final Duration retryAfter;

  const PublicSenatRateLimitedException(this.retryAfter);

  @override
  String toString() => 'Rate limited, retry in ${retryAfter.inSeconds}s';
}

/// Plain HTML access to publicsenat.fr, which has no API.
///
/// The site's robots.txt allows every path used here, including the "load more" call of programme pages.
/// Requests are spaced by [minInterval] so a programme with many pages never turns into a burst. Callers
/// cache what they parse.
class PublicSenatApi {
  static const _ajaxUrl = '$publicSenatOrigin/wp/wp-admin/admin-ajax.php';
  static const _headers = {
    'Accept': 'text/html,application/json;q=0.9',
    'Accept-Language': 'fr',
    'User-Agent': 'Plezy-Replay (+https://github.com/silkyclouds/plezy)',
  };

  final MediaServerHttpClient _http;
  final Duration minInterval;
  Future<void> _turn = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  PublicSenatApi(this._http, {this.minInterval = const Duration(milliseconds: 700)});

  /// The programme index page.
  Future<String?> programmes() => _page('/emissions');

  /// The replay landing page, which lists the newest videos across programmes.
  Future<String?> replays() => _page('/replay');

  /// A programme page, or null when the site has no such programme.
  Future<String?> show(String slug) => _page('/emission/${Uri.encodeComponent(slug)}');

  /// The next batch of cards of a programme, as the HTML fragment the site's own "load more" button receives.
  Future<String?> moreCards(PsPaging paging, int page) async {
    await _throttle();
    final response = await _http.post(
      _ajaxUrl,
      headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
      body: Uri(
        queryParameters: {
          'action': paging.action,
          'security': paging.nonce,
          'termID': paging.termId,
          'limit': '${paging.limit}',
          'paged': '$page',
          'order': 'desc',
          'total': '${paging.total}',
        },
      ).query,
    );
    _checkStatus(response);
    return parseMoreTemplate(response.data);
  }

  Future<String?> _page(String path) async {
    await _throttle();
    final response = await _http.get('$publicSenatOrigin$path', headers: _headers);
    if (response.statusCode == 404) return null;
    _checkStatus(response);
    final data = response.data;
    return data is String ? data : null;
  }

  void _checkStatus(MediaServerResponse response) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw PublicSenatRateLimitedException(Duration(seconds: seconds));
    }
    throwIfHttpError(response);
  }

  /// Queues the caller behind earlier requests and waits until [minInterval] has passed since the last one.
  Future<void> _throttle() {
    final previous = _turn;
    final mine = Completer<void>();
    _turn = mine.future;
    return previous.then((_) async {
      final wait = minInterval - DateTime.now().difference(_lastRequest);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastRequest = DateTime.now();
      mine.complete();
    });
  }
}
