import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/err/err_api.dart';
import 'package:plezy/replay/providers/err/err_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/err';

/// The text of a recorded answer, with its extension.
String errFixtureText(String file) => File('$_fixtures/$file').readAsStringSync();

/// The decoded JSON of a recorded answer `name` (without extension).
Map<String, dynamic> errFixture(String name) => jsonDecode(errFixtureText('$name.json')) as Map<String, dynamic>;

/// Content page ids and the recorded page that answers each. A programme id and the id of its first episode share a
/// page, as they do on the real site.
const errPages = {
  1038279: 'series_page',
  903574: 'series_page',
  906025: 'seasonal_page_season2',
  1092236: 'episode_page_ok',
  1092243: 'episode_page_ok',
  1608311720: 'movie_page_drm',
  1609804523: 'movie_page_geoblocked',
  1210984: 'movie_page_ok',
  1038506: 'monthly_show_page',
  1610160944: 'monthly_show_page',
  1610140841: 'monthly_page_2026_09',
  1609876568: 'monthly_page_2025_12',
  1609850767: 'monthly_page_2025_11',
  1610145704: 'short_series_page',
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _notFound() => _json({
  'apiVersion': '2.0',
  'error': {'code': 404, 'message': 'File Not Found'},
}, 404);

/// A stand-in for ERR's services and CDN that serves recorded answers and remembers what was asked.
class ErrFakeSite {
  final List<http.Request> requests = [];

  /// Pages replaced for one test, by content id.
  final Map<int, Map<String, dynamic>> pageOverrides = {};

  /// When true the stream CDN treats the viewer as being in Estonia.
  bool viewerInEstonia = false;

  ErrProvider provider() =>
      ErrProvider.withApi(ErrApi(MediaServerHttpClient(client: MockClient((r) async => _route(r)))));

  Iterable<http.Request> requestsTo(String host) => requests.where((r) => r.url.host == host);

  int pageRequests(int id) => requests
      .where((r) => r.url.path.endsWith('getContentPageData') && r.url.queryParameters['contentId'] == '$id')
      .length;

  http.Response _route(http.Request request) {
    requests.add(request);
    final url = request.url;
    if (url.host == 'vod.err.ee') return _stream(url);
    final query = url.queryParameters;
    switch (url.path) {
      case '/api/v2/vodContent/getContentPageData':
        return _page(query['contentId'] ?? '');
      case '/api/v2/category/getByUrl':
        return _category(query['url'] ?? '');
      case '/api/v2/series/getSeriesData':
        return _json({'apiVersion': '2.0', 'data': errFixture('series_list_sample')});
      case '/api/search/getVodContents2/':
        final phrase = (jsonDecode(query['options']!) as Map)['phrase'];
        return phrase == 'zzzz'
            ? _json({
                'video': {'contents': [], 'totalFound': 0},
              })
            : _json(errFixture('search'));
    }
    return _notFound();
  }

  http.Response _page(String rawId) {
    final id = int.tryParse(rawId);
    if (id == 429) return http.Response('slow down', 429, headers: {'retry-after': '30'});
    final override = pageOverrides[id];
    if (override != null) return _json({'apiVersion': '2.0', 'data': override});
    final name = errPages[id];
    return name == null ? _notFound() : _json({'apiVersion': '2.0', 'data': errFixture(name)});
  }

  http.Response _category(String slug) {
    final category = switch (slug) {
      'video' => errFixture('home_video'),
      'filmid' => errFixture('category_filmid'),
      'eesti' => errFixture('genre_eesti'),
      _ => null,
    };
    return category == null
        ? _notFound()
        : _json({
            'apiVersion': '2.0',
            'data': {'category': category},
          });
  }

  http.Response _stream(Uri url) {
    if (url.path.contains('/gone/')) return http.Response('', 404);
    if (url.path.contains('/gb/') && !viewerInEstonia) {
      return http.Response(errFixtureText('hls_geoblocked.html'), 403, headers: {'content-type': 'text/html'});
    }
    return http.Response(
      errFixtureText('master_hls.m3u8'),
      200,
      headers: {'content-type': 'application/vnd.apple.mpegurl'},
    );
  }
}
