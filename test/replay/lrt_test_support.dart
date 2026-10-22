import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/lrt/lrt_api.dart';
import 'package:plezy/replay/providers/lrt/lrt_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const lrtFixtures = 'test/replay/fixtures/lrt';

String lrtFixture(String name) => File('$lrtFixtures/$name').readAsStringSync();

ReplayRef lrtRef(String id) => ReplayRef('lrt', id);

ReplayRef lrtRecording(String postId) => ReplayRef('lrt', 'rec:$postId');

const lrtMasterUrl =
    'https://stream-vod3.lrt.lt/VIDEO/2026-10/ZIN51199_W_180dd0f9-bf13-4a84-8451-3310cfcf4ed1.mp4/playlist.m3u8';

/// Stands in for lrt.lt: serves the recorded pages, feeds and lookups by URL and keeps a log of what was asked.
class LrtFakeSite {
  final List<Uri> requests = [];

  /// Replaces the answer for a URL path (or a path plus query) without touching the recorded ones.
  final Map<String, http.Response Function(Uri)> overrides = {};

  int requestsTo(String pathPart) => requests.where((u) => u.toString().contains(pathPart)).length;

  http.Response handle(http.Request request) {
    final uri = request.url;
    requests.add(uri);
    final override = overrides[uri.path] ?? overrides[uri.toString()];
    if (override != null) return override(uri);
    if (uri.host == 'stream-vod3.lrt.lt') return _manifest(uri.path);
    return switch (uri.path) {
      '/api/json/search' => _search(uri),
      '/servisai/stream_url/vod/media_info/' => _mediaInfo(uri.queryParameters['url'] ?? ''),
      final path when path.startsWith('/rest-api/articles/mediateka/') => _article(path),
      final path when path.startsWith('/mediateka') =>
        uri.queryParameters.containsKey('rss') ? _feed(path) : _page(path),
      _ => http.Response('{}', 404),
    };
  }

  http.Response _feed(String path) {
    final name = const {
      '/mediateka': 'rss_show_head.xml',
      '/mediateka/filmai': 'rss_section_filmai_head.xml',
      '/mediateka/vaikams': 'rss_single_head.xml',
      '/mediateka/pramogos': 'rss_single_head.xml',
      '/mediateka/video/zinios': 'rss_show_head.xml',
      '/mediateka/video/zinios/2026': 'rss_show_head.xml',
      '/mediateka/video/zinios/2025': 'rss_season_2025_head.xml',
      '/mediateka/video/pazvelk-i-profesija-kitaip/2015': 'rss_numbered_head.xml',
      '/mediateka/video/mylekime-gamta': 'rss_single_head.xml',
      '/mediateka/video/mylekime-gamta/1975': 'rss_single_head.xml',
      '/mediateka/video/be-sezonu': 'rss_single_head.xml',
    }[path];
    if (name != null) return xml(lrtFixture(name));
    if (path == '/mediateka/video/zinios/2023') return xml(lrtGeneratedFeed(lrtFeedLength));
    return http.Response('<html>Not found</html>', 404, headers: {'content-type': 'text/html'});
  }

  http.Response _page(String path) {
    final name = const {
      '/mediateka/video/zinios': 'show_page_zinios.html',
      '/mediateka/video/mylekime-gamta': 'show_page_single.html',
      '/mediateka/video/be-sezonu': 'show_page_no_seasons.html',
      '/mediateka/tv-laidos': 'tv_laidos_sample.html',
    }[path];
    if (name == null) return http.Response('<html>Not found</html>', 404, headers: {'content-type': 'text/html'});
    return html(lrtFixture(name));
  }

  http.Response _search(Uri uri) {
    if (uri.queryParameters['q'] == 'zzzz') {
      return json('{"items":[],"total_found":"0","page":1,"similar_categories":[]}');
    }
    return json(lrtFixture('search_video.json'));
  }

  http.Response _article(String path) =>
      path.contains('/2000901016/') ? json(lrtFixture('article.json')) : http.Response('{}', 404);

  http.Response _mediaInfo(String url) {
    final id = RegExp(r'/irasas/(\d+)').firstMatch(url)?.group(1);
    final ok = lrtFixture('media_info_ok.json');
    return switch (id) {
      '2000901016' => json(ok),
      '2000587152' => json(lrtFixture('media_info_geo_tikLT.json')),
      '2000000001' => json(ok.replaceAll('ZIN51199_W_180dd0f9-bf13-4a84-8451-3310cfcf4ed1', 'GONE_0000')),
      '2000000002' => http.Response('slow down', 429, headers: {'retry-after': '30'}),
      '2000000003' => json(
        ok.replaceAll(RegExp(r'[^"]+playlist\.m3u8'), 'https://stream-vod3.lrt.lt/AUDIO/2026-10/radio.mp3'),
      ),
      '2000000004' => http.Response('<html>maintenance</html>', 200, headers: {'content-type': 'text/html'}),
      '2000000005' => json(
        ok.replaceAll('stream-vod3.lrt.lt/VIDEO/2026-10/ZIN51199', 'stream-vod3.lrt.lt/VIDEO/2026-10/FORBIDDEN'),
      ),
      '2000000006' => http.Response('', 503),
      '1000000' => json(lrtFixture('media_info_unknown.json')),
      _ => json(
        ok
            .replaceFirst('2000901016', id ?? '0')
            .replaceAll('ZIN51199_W_180dd0f9-bf13-4a84-8451-3310cfcf4ed1', 'OTHER_$id'),
      ),
    };
  }

  http.Response _manifest(String path) {
    if (path.contains('GONE_')) {
      return http.Response('<html>Not found</html>', 404, headers: {'content-type': 'text/html'});
    }
    if (path.contains('FORBIDDEN')) return http.Response('denied', 403);
    return http.Response(lrtFixture('master.m3u8'), 200, headers: {'content-type': 'application/vnd.apple.mpegurl'});
  }

  static http.Response xml(String body) => _bytes(body, 'application/rss+xml; charset=utf-8');

  static http.Response html(String body) => _bytes(body, 'text/html; charset=utf-8');

  static http.Response json(String body) => _bytes(body, 'application/json; charset=utf-8');

  static http.Response _bytes(String body, String type) =>
      http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': type});
}

/// Items a feed holds when the site has cut it, which is when numbering by date would be wrong.
const lrtFeedLength = 100;

/// An RSS feed of [count] daily news recordings with the same title, newest first.
String lrtGeneratedFeed(int count) {
  final start = DateTime.utc(2023, 12, 31, 18);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final items = StringBuffer();
  for (var i = 0; i < count; i++) {
    final at = start.subtract(Duration(days: i));
    final stamp =
        '${days[at.weekday - 1]}, ${at.day.toString().padLeft(2, '0')} ${months[at.month - 1]} ${at.year} 18:00:00 +0000';
    items.write(
      '<item><title><![CDATA[Žinios]]></title><link>https://www.lrt.lt/mediateka/irasas/${2000100000 + i}/zinios</link>'
      '<pubDate>$stamp</pubDate><category><![CDATA[Žinios]]></category></item>',
    );
  }
  return '<?xml version="1.0"?><rss version="2.0"><channel><title>x</title>$items</channel></rss>';
}

LrtProvider lrtProviderOver(LrtFakeSite site) => LrtProvider.withApi(
  LrtApi(MediaServerHttpClient(client: MockClient((r) async => site.handle(r))), minInterval: Duration.zero),
);
