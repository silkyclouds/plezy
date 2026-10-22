import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/nfb/nfb_api.dart';
import 'package:plezy/replay/providers/nfb/nfb_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/nfb';

String nfbFixture(String name) => File('$_fixtures/$name').readAsStringSync();

/// A fixed clock so availability does not depend on the day the tests run.
final nfbTestNow = DateTime.utc(2026, 10, 22);

/// Serves recorded NFB responses by address and remembers every request made.
class NfbFakeSite {
  final List<http.Request> requests = [];
  final Map<String, http.Response Function(http.Request)> overrides = {};

  http.Response handle(http.Request request) {
    requests.add(request);
    final override = overrides[request.url.path];
    if (override != null) return override(request);
    return _route(request);
  }

  NfbApi api({Duration interval = Duration.zero}) => NfbApi(
    MediaServerHttpClient(client: MockClient((r) async => handle(r))),
    interval: interval,
    now: () => nfbTestNow,
  );

  NfbProvider provider() => NfbProvider.withApi(api(), now: () => nfbTestNow);

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

http.Response _json(String fixture) =>
    http.Response(nfbFixture(fixture), 200, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _jsonText(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _html(String fixture) =>
    http.Response(nfbFixture(fixture), 200, headers: {'content-type': 'text/html; charset=utf-8'});

http.Response _page(String body, [int status = 200]) =>
    http.Response(body, status, headers: {'content-type': 'text/html; charset=utf-8'});

http.Response _route(http.Request request) {
  final path = request.url.path;
  final query = request.url.queryParameters['query'];
  if (path == '/api/v5/films') {
    if (query == 'ryan') return _json('films_search_ryan.json');
    if (query == 'zzzz') return _jsonText('{"items":[],"meta":{"pagination":{"total":0}}}');
    return _json('films_page.json');
  }
  if (path == '/api/v5/series') return _json('series_list.json');
  if (path == '/feeds/new_additions/') {
    return http.Response(
      nfbFixture('feed_new_additions.xml'),
      200,
      headers: {'content-type': 'application/rss+xml; charset=utf-8'},
    );
  }
  const pages = {
    '/series/the-great-list-of-everything-series/': 'series_page_great_list.html',
    '/series/beauty-begins-inside/': 'series_page_beauty_begins_inside.html',
    '/film/i_want_a_dog/': 'film_page_i_want_a_dog.html',
    '/film/great-list-of-everything-e1-the-phone/': 'film_page_episode_phone.html',
    '/film/ryan/embed/player/': 'embed_ryan.html',
    '/film/i_want_a_dog/embed/player/': 'embed_i_want_a_dog.html',
    '/film/1_2_3_coco/embed/player/': 'embed_geoblocked.html',
    '/film/acting_blind/embed/player/': 'embed_paid.html',
  };
  final fixture = pages[path];
  if (fixture != null) return _html(fixture);
  if (path == '/film/plain/embed/player/') {
    return _page(
      'window.IFRAME_OPTIONS = {"language": "en", "dvSource": false, "source": '
      '"https://d3acx5b8mnvbua.cloudfront.net/hls/a/a.m3u8?Policy=p&Signature=s&Key-Pair-Id=k#expires=1"}',
    );
  }
  if (path == '/film/limited/embed/player/') return http.Response('slow down', 429, headers: {'retry-after': '30'});
  if (path == '/film/mangled/embed/player/') {
    return _page('<script>window.IFRAME_OPTIONS = {"source": "https://x.test/a.m3u8", </script>');
  }
  if (path == '/film/blank/') return _page('<html><body>Nothing structured here</body></html>');
  if (path == '/series/broken/') return _page('<script type="application/ld+json">{ not json</script>');
  return http.Response('Not found', 404);
}
