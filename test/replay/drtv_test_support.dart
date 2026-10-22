import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/drtv/drtv_api.dart';
import 'package:plezy/replay/providers/drtv/drtv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/drtv';
const _json = {'content-type': 'application/json'};

dynamic drtvFixture(String name) => jsonDecode(File('$_fixtures/$name.json').readAsStringSync());

/// A deep copy of a fixture that [edit] may change.
Map<String, dynamic> drtvEdited(String name, void Function(Map<String, dynamic> json) edit) {
  final copy = jsonDecode(jsonEncode(drtvFixture(name))) as Map<String, dynamic>;
  edit(copy);
  return copy;
}

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: _json);

/// Serves recorded DR responses by path. Everything it does not know is a 404.
class DrtvFakeSite {
  final List<http.Request> requests = [];

  /// What the CDN answers for a manifest on the Denmark-only path.
  int manifestStatus = 403;

  /// How many catalogue calls to refuse with 401 before answering.
  int refuseCatalogue = 0;

  /// Extra items served by `/items/{id}`, keyed by id.
  final Map<String, Map<String, dynamic>> items = {};

  List<http.Request> where(String path) => requests.where((r) => r.url.path.endsWith(path)).toList();

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.url.host == 'isl.dr-massive.com') return _ok(drtvFixture('anonymous_sso'));
    if (request.url.host.endsWith('akamaized.net')) return http.Response('#EXTM3U', manifestStatus);
    if (refuseCatalogue > 0) {
      refuseCatalogue--;
      return http.Response('Unauthorized', 401);
    }
    if (path == '/api/page') return _page(request.url.queryParameters['path'] ?? '');
    if (path.startsWith('/api/lists/')) return _list(path.split('/').last, request.url.queryParameters);
    if (path.startsWith('/api/items/')) return _item(path.split('/').last);
    if (path == '/api/v2/search') {
      return _ok(
        request.url.queryParameters['term'] == 'zzzz' ? {'term': 'zzzz', 'total': 0} : drtvFixture('search_natur'),
      );
    }
    if (path.endsWith('/videos')) return _videos(path.split('/')[4]);
    return http.Response('{}', 404, headers: _json);
  }

  http.Response _page(String path) => switch (path) {
    '/' || '/kategorier/natur' => _ok(drtvFixture('home_page')),
    '/serie/x_6954' || '/saeson/x_567443' => _ok(drtvFixture('show_page')),
    '/serie/x_7001' => _ok(drtvEdited('show_page', (j) => (j['item']['show'] as Map).remove('seasons'))),
    '/serie/x_7002' => _ok(
      drtvEdited('show_page', (j) {
        (j['item']['show'] as Map)
          ..remove('seasons')
          ..['id'] = '7002';
        j['item']['type'] = 'show';
      }),
    ),
    '/serie/x_7003' => _ok(drtvEdited('show_page', _scrambleSeasons)),
    _ => http.Response('{}', 404, headers: _json),
  };

  /// Seasons out of order, one empty, one without any number.
  static void _scrambleSeasons(Map<String, dynamic> json) {
    final seasons = (json['item']['show']['seasons']['items'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic> copy(Map<String, dynamic> s) => jsonDecode(jsonEncode(s)) as Map<String, dynamic>;
    final empty = copy(seasons[0])
      ..['id'] = '7101'
      ..['availableEpisodeCount'] = 0;
    final unnumbered = copy(seasons[2])
      ..['id'] = '7102'
      ..remove('seasonNumber');
    (unnumbered['customFields'] as Map).remove('ExtraDetails');
    json['item']['show']['seasons']['items'] = [seasons[3], seasons[1], empty, unnumbered];
  }

  http.Response _list(String id, Map<String, String> query) {
    final page = int.parse(query['page'] ?? '1');
    final param = query['param'];
    if (id == '348') return _letter(param ?? '', page);
    final shows = (drtvFixture('search_natur')['series']['items'] as List);
    return switch (id) {
      '209529' => _ok({
        'id': id,
        'items': shows.take(3).toList(),
        'paging': {'total': 1, 'page': 1, 'size': 24},
      }),
      '559087' when page == 1 => _ok({
        'id': id,
        'items': shows.take(3).toList(),
        'paging': {'total': 2, 'page': 1, 'size': 24, 'next': '/lists/559087?page_size=24&page=2'},
      }),
      '559087' => _ok({
        'id': id,
        'items': shows.skip(3).toList(),
        'paging': {'total': 2, 'page': 2, 'size': 24},
      }),
      _ => _ok({
        'id': id,
        'items': <Object>[],
        'paging': {'total': 1, 'page': 1, 'size': 24},
      }),
    };
  }

  /// Letter "a" holds the first six cards over two pages (two of them repeated), "ø" the recorded eight.
  http.Response _letter(String param, int page) {
    final all = (drtvFixture('az_letter_oe')['items'] as List);
    final empty = {
      'items': <Object>[],
      'paging': {'total': 1, 'page': 1, 'size': 100},
    };
    return switch ((param, page)) {
      ('TitleGroupKey:a', 1) => _ok({
        'items': all.sublist(0, 4),
        'paging': {'total': 2, 'page': 1, 'size': 100, 'next': '/lists/348?page=2'},
      }),
      ('TitleGroupKey:a', 2) => _ok({
        'items': all.sublist(2, 6),
        'paging': {'total': 2, 'page': 2, 'size': 100},
      }),
      ('TitleGroupKey:ø', _) => _ok(drtvFixture('az_letter_oe')),
      _ => _ok(empty),
    };
  }

  http.Response _item(String id) {
    final extra = items[id];
    if (extra != null) return _ok(extra);
    return switch (id) {
      '622110' => _ok(drtvFixture('item_episode')),
      '578151' => _ok(drtvFixture('item_program')),
      _ => http.Response('{}', 404, headers: _json),
    };
  }

  http.Response _videos(String id) => switch (id) {
    '622110' => _ok(drtvFixture('videos_clear_all')),
    '616476' => _ok(drtvFixture('videos_denmark_only')),
    '543349' => _ok(drtvFixture('videos_drm_playready')),
    '500000' => _ok(<Object>[]),
    '429429' => http.Response('slow down', 429, headers: {'retry-after': '30'}),
    _ => http.Response('{}', 404, headers: _json),
  };

  DrtvApi api({String Function()? newId}) => DrtvApi(
    MediaServerHttpClient(client: MockClient(handle)),
    minInterval: Duration.zero,
    newId: newId ?? () => 'device-test',
  );

  /// A provider over this site; [clock] fixes "now" for expiry and release dates.
  DrtvProvider provider({DateTime? clock}) =>
      DrtvProvider.withApi(api(), clock: () => clock ?? DateTime.utc(2026, 10, 23));
}
