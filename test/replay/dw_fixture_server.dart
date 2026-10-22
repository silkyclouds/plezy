import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/dw/dw_api.dart';
import 'package:plezy/replay/providers/dw/dw_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/dw';

String dwFixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

Map<String, dynamic> dwFixtureJson(String name) => jsonDecode(dwFixture(name)) as Map<String, dynamic>;

http.Response _json(String body, [int status = 200, Map<String, String> extra = const {}]) =>
    http.Response(body, status, headers: {'content-type': 'application/json; charset=utf-8', ...extra});

http.Response _notFound() =>
    http.Response('<html><title>404 Not Found</title></html>', 404, headers: {'content-type': 'text/html'});

/// Programme that the fake search engine answers with [dwBigTotal] hits.
const dwBigProgramme = 111;
const dwBigTotal = 450;

/// Programme that the fake search engine answers with [dwSmallTotal] hits.
const dwSmallProgramme = 112;
const dwSmallTotal = 130;

/// Serves recorded DW responses by path and search request, and remembers every request it saw.
class DwFixtureServer {
  final List<http.Request> requests = [];

  MediaServerHttpClient client() => MediaServerHttpClient(
    client: MockClient((request) async {
      requests.add(request);
      return request.method == 'POST' ? _search(request) : _graph(request.url.path);
    }),
  );

  DwProvider provider({DateTime Function()? clock}) => DwProvider.withApi(DwApi(client(), clock: clock), clock: clock);

  List<http.Request> get searches => [
    for (final r in requests)
      if (r.method == 'POST') r,
  ];

  http.Response _graph(String path) {
    final id = path.split('/').last;
    if (path.endsWith('/programs-overview')) return _json(dwFixture('programs_overview'));
    if (path.contains('/content/unified-program/')) {
      return switch (id) {
        '294010' => _json(dwFixture('unified_program_docfilm')),
        '78363545' => _json(dwFixture('video_docfilm')),
        _ => _json('{"data":{}}'),
      };
    }
    if (path.contains('/content/video/')) return _video(id);
    return _notFound();
  }

  http.Response _video(String id) => switch (id) {
    '78363545' => _json(dwFixture('video_docfilm')),
    '79610229' => _json(dwFixture('video_with_subtitles')),
    '1111' => _json('{"data":{}}'),
    '3333' => _json(_withoutStream('2020-01-01T00:00:00Z')),
    '4444' => _json(_withoutStream('2999-01-01T00:00:00Z')),
    '5555' => http.Response('slow down', 429, headers: {'retry-after': '30'}),
    '6666' => http.Response('unavailable', 451),
    _ => _notFound(),
  };

  String _withoutStream(String published) {
    final document = dwFixtureJson('video_docfilm');
    final content = (document['data'] as Map)['content'] as Map<String, dynamic>;
    content.remove('hlsVideoSrc');
    content['firstPublicationDate'] = published;
    return jsonEncode(document);
  }

  http.Response _search(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final filters = ((body['filters'] as Map)['all'] as List).cast<Map<String, dynamic>>();
    final programme = filters.map((f) => f['unifiedPrograms.id']).whereType<num>().firstOrNull?.toInt();
    final query = body['query'] as String;
    if (body.containsKey('facets')) return _json(dwFixture('search_year_counts_docfilm'));
    if (query == 'qqq') return _json(dwFixture('search_no_results'));
    if (query.isNotEmpty) return _json(dwFixture('search_climate'));
    if (programme == dwBigProgramme) return _json(_synthetic(body, dwBigTotal));
    if (programme == dwSmallProgramme) return _json(_synthetic(body, dwSmallTotal));
    return _json(dwFixture(programme == null ? 'search_latest' : 'search_docfilm_2026'));
  }

  /// A page of [total] made-up hits, newest first, each a copy of a recorded hit with its own id and date.
  String _synthetic(Map<String, dynamic> body, int total) {
    final page = body['page'] as Map<String, dynamic>;
    final size = page['size'] as int;
    final first = ((page['current'] as int) - 1) * size;
    final template = (dwFixtureJson('search_docfilm_2026')['results'] as List).first as Map<String, dynamic>;
    final newest = DateTime.utc(2026, 10, 21, 12);
    final hits = <Map<String, dynamic>>[];
    for (var n = first; n < first + size && n < total; n++) {
      final hit = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
      (hit['_meta'] as Map)['id'] = '${80000000 + n}';
      (hit['title'] as Map)['raw'] = 'Episode $n';
      (hit['contentDate'] as Map)['raw'] = newest.subtract(Duration(hours: n)).toIso8601String();
      hits.add(hit);
    }
    return jsonEncode({
      'meta': {
        'page': {'current': page['current'], 'size': size, 'total_results': total},
      },
      'results': hits,
    });
  }
}
