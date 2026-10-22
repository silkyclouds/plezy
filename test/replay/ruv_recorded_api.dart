import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/ruv/ruv_api.dart';
import 'package:plezy/replay/providers/ruv/ruv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/ruv';

/// Recorded programmes. Fleiri pabbahelgar is Iceland-only, Kastljós and the film are worldwide.
const domesticProgram = 36160;
const filmProgram = 34778;
const newsProgram = 39455;
const vikinglottoProgram = 39082;
const seriesProgram = 29393;
const dailyProgram = 32541;
const filmCategorySeries = 34266;

/// Recorded episodes.
const domesticEpisode = 'aor501';
const newsEpisode = 'bo8mok';
const filmEpisode = 'ablct1';

final testNow = DateTime.utc(2026, 10, 22, 8);

String fixtureText(String name) => File('$_fixtures/$name').readAsStringSync();

Map<String, dynamic> fixture(String name) => jsonDecode(fixtureText('$name.json')) as Map<String, dynamic>;

/// Serves recorded RÚV responses from a fake GraphQL endpoint and fake CDN.
///
/// Programme and card batches are answered from an index of every programme in the fixtures, so any combination of
/// ids behaves like the real endpoint: unknown ids come back as null.
class RecordedRuv {
  /// Whether the CDN serves Iceland-only masters, as it does to a viewer in Iceland.
  bool inIceland = false;

  /// Changes an episode before it is served, to stage expiry and missing files.
  void Function(Map<String, dynamic> episode)? editEpisode;

  final List<http.Request> requests = [];
  late final Map<int, Map<String, dynamic>> _programs = _indexPrograms();

  RuvProvider provider({DateTime? clock}) =>
      RuvProvider.withApi(RuvApi(_client(), now: () => clock ?? testNow), clock: () => clock ?? testNow);

  MediaServerHttpClient _client() => MediaServerHttpClient(client: MockClient((r) async => _handle(r)));

  /// Number of GraphQL requests whose query text contains [part].
  int queriesWith(String part) => requests.where((r) => r.method == 'POST' && r.body.contains(part)).length;

  http.Response _handle(http.Request request) {
    requests.add(request);
    if (request.method == 'GET') return _cdn(request.url);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    final variables = (body['variables'] as Map?)?.cast<String, dynamic>() ?? const {};
    return _json(_answer(query, variables));
  }

  http.Response _cdn(Uri url) {
    final folder = url.pathSegments.first;
    if (folder == 'opid' || (folder == 'lokad' && inIceland)) {
      return http.Response(
        fixtureText('master_global.m3u8'),
        200,
        headers: {'content-type': 'application/vnd.apple.mpegurl'},
      );
    }
    if (folder == 'lokad') {
      return http.Response('<html>Access Denied</html>', 403, headers: {'content-type': 'text/html'});
    }
    return http.Response('', 404);
  }

  Map<String, dynamic> _answer(String query, Map<String, dynamic> variables) {
    if (query.contains('Featured(')) return fixture('panels');
    if (query.contains('Search(')) {
      return variables['x'] == 'zzzz'
          ? {
              'data': {'Search': <Object>[]},
            }
          : fixture('search_natturu');
    }
    if (query.contains('Category(station:\$s){')) return fixture('categories');
    if (query.contains('Category(')) return _category('${variables['c']}');
    if (query.startsWith('{a0:Program')) return _batch(query);
    if (query.contains('id:{value:')) return _episode(query, variables['p'] as int);
    if (query.contains('Program(id:\$p)')) return _program(variables['p'] as int);
    return {
      'data': null,
      'errors': [
        {'message': 'unrecognised query'},
      ],
    };
  }

  Map<String, dynamic> _category(String slug) {
    final known = const {'kvikmyndir', 'heimildarefni'};
    if (known.contains(slug)) return fixture('category_$slug');
    return {
      'data': {
        'Category': {
          'categories': <Object>[
            {'title': slug, 'slug': slug, 'programs': <Object>[]},
          ],
        },
      },
    };
  }

  Map<String, dynamic> _batch(String query) {
    final ids = [for (final m in RegExp(r'a\d+:Program\(id:(\d+)\)').allMatches(query)) int.parse(m.group(1)!)];
    final scopeOnly = query.contains('episodes(limit:1){scope}');
    return {
      'data': {
        for (var i = 0; i < ids.length; i++)
          'a$i': _programs[ids[i]] == null
              ? null
              : scopeOnly
              ? {
                  'episodes': (_programs[ids[i]]!['episodes'] as List)
                      .take(1)
                      .map((e) => {'scope': e['scope']})
                      .toList(),
                }
              : _programs[ids[i]],
      },
    };
  }

  Map<String, dynamic> _program(int id) {
    final name = const {
      domesticProgram: 'program_domestic',
      filmProgram: 'program_film',
      vikinglottoProgram: 'program_global',
      seriesProgram: 'program_series',
      dailyProgram: 'program_daily',
      filmCategorySeries: 'program_multi_film',
    }[id];
    return name == null
        ? {
            'data': {'Program': null},
          }
        : fixture(name);
  }

  Map<String, dynamic> _episode(String query, int programId) {
    final id = RegExp(r'value:\["([^"]+)"\]').firstMatch(query)!.group(1);
    final name = const {
      newsEpisode: 'episode_global',
      domesticEpisode: 'episode_domestic',
      filmEpisode: 'episode_film',
    }[id];
    if (name == null) {
      return {
        'data': {
          'Program': programId == 999 ? null : {'episodes': <Object>[]},
        },
      };
    }
    final answer = fixture(name);
    final episode = ((answer['data'] as Map)['Program'] as Map)['episodes'][0] as Map<String, dynamic>;
    editEpisode?.call(episode);
    return answer;
  }

  Map<int, Map<String, dynamic>> _indexPrograms() {
    final index = <int, Map<String, dynamic>>{};
    void add(Object? program) {
      if (program is Map<String, dynamic> && program['programID'] != null) index[program['programID'] as int] = program;
    }

    for (final panel in (fixture('panels')['data']['Featured']['panels'] as List)) {
      (panel['programs'] as List).forEach(add);
    }
    for (final slug in ['kvikmyndir', 'heimildarefni']) {
      (fixture('category_$slug')['data']['Category']['categories'][0]['programs'] as List).forEach(add);
    }
    final hits = (fixture('search_natturu')['data']['Search'] as List).map((h) => int.parse(h['id'] as String));
    final cards = fixture('cards_search')['data'] as Map<String, dynamic>;
    final order = hits.toSet().toList();
    for (var i = 0; i < order.length; i++) {
      add(cards['a$i']);
    }
    for (final name in [
      'program_domestic',
      'program_film',
      'program_global',
      'program_series',
      'program_daily',
      'program_multi_film',
    ]) {
      add(fixture(name)['data']['Program']);
    }
    return index;
  }

  http.Response _json(Map<String, dynamic> body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
}
