import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/bbciplayer/bbciplayer_api.dart';
import 'package:plezy/replay/providers/bbciplayer/bbciplayer_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/bbciplayer';
const _ibl = '/ibl/v1/';
const _selector = '/mediaselector/6/select/version/2.0/mediaset/pc/vpid/';

/// The day the recorded responses were made; every availability window is judged against it.
final bbcToday = DateTime.utc(2026, 10, 22, 10);

String bbcFixtureText(String name) => File('$_fixtures/$name').readAsStringSync();

Map<String, dynamic> bbcFixture(String name) => jsonDecode(bbcFixtureText('$name.json')) as Map<String, dynamic>;

ReplayRef bbcTestRef(String id) => ReplayRef('bbciplayer', id);

/// Atoz letters of the fake catalogue and how many programmes each holds.
const bbcLetterCounts = {'0-9': 2, 'a': 3, 'b': 150};

/// Serves the recorded iBL responses and the synthetic media selector answers, and remembers every request.
class BbcFakeSite {
  final List<http.Request> requests = [];

  /// Media selector answers by version id; a missing id gets the synthetic success answer.
  final Map<String, ({int status, String body})> selector = {};
  String hlsManifest = bbcFixtureText('synthetic_master_clear.m3u8');
  String dashManifest = bbcFixtureText('synthetic_manifest_protected.mpd');
  final Map<String, Map<String, dynamic>> episodes = {};

  List<http.Request> get selectorRequests => [
    for (final r in requests)
      if (r.url.path.startsWith(_selector)) r,
  ];

  BbcIplayerProvider provider({DateTime? now}) {
    final client = MediaServerHttpClient(client: MockClient((r) async => _handle(r)));
    return BbcIplayerProvider.withApi(BbcIplayerApi(client, now: () => now ?? bbcToday), clock: () => now ?? bbcToday);
  }

  http.Response _handle(http.Request request) {
    requests.add(request);
    final path = request.url.path;
    if (path.startsWith(_ibl)) return _catalogue(request, path.substring(_ibl.length));
    if (path.startsWith(_selector)) return _mediaSelector(path.substring(_selector.length).split('/').first);
    if (path.endsWith('.m3u8')) return _text(hlsManifest, 'application/vnd.apple.mpegurl');
    if (path.endsWith('.mpd')) return _text(dashManifest, 'application/dash+xml');
    return http.Response('', 404);
  }

  http.Response _catalogue(http.Request request, String path) {
    final q = request.url.queryParameters;
    final atoz = RegExp(r'^atoz/([^/]+)/programmes$').firstMatch(path);
    if (atoz != null) return _json(_atozPage(atoz.group(1)!, int.parse(q['page']!), int.parse(q['per_page']!)));
    if (path == 'new-search' && q['q'] == 'zzzz') {
      return _json({
        'new_search': {'query': 'zzzz', 'results': []},
      });
    }
    final episode = RegExp(r'^episodes/(.+)$').firstMatch(path)?.group(1);
    if (episode != null) return _json(_episode(episode));
    final name = _routes[path];
    if (name != null) return _json(bbcFixture(name));
    if (path == 'programmes/m001fyf7/episodes') return _json(_filmEpisodes());
    if (path.startsWith('programmes/') && path.endsWith('/episodes')) {
      return _json({
        'programme_episodes': {'count': 0, 'page': 1, 'per_page': 200, 'elements': []},
      });
    }
    if (path.startsWith('programmes/')) return _json({'programmes': []});
    return http.Response('{"error":{"http_response_code":404}}', 404, headers: _jsonHeaders);
  }

  static const _routes = {
    'channels': 'channels',
    'categories': 'categories',
    'channels/bbc_one_london/highlights': 'channel_highlights',
    'channels/bbc_one_london/programmes': 'channel_programmes',
    'categories/documentaries/programmes': 'category_programmes',
    'groups/p07jlk69/episodes': 'group_episodes',
    'new-search': 'search',
    'programmes/m002csng': 'programme_brand',
    'programmes/m001fyf7': 'programme_film',
    'programmes/m002csng/episodes': 'programme_episodes_celebrity',
    'programmes/b006m8dq/episodes': 'programme_episodes_strictly',
    'programmes/m000vbrk/episodes': 'programme_episodes_bluey',
    'programmes/b006t14n/episodes': 'programme_episodes_panorama',
    'programmes/m0synth/episodes': 'synthetic_programme_episodes_structural',
  };

  Map<String, dynamic> _episode(String id) {
    final override = episodes[id];
    if (override != null) return override;
    final name = switch (id) {
      'm0030pxt' => 'episode',
      'm001fyf7' => 'episode_film',
      _ => null,
    };
    return name == null ? {'episodes': []} : bbcFixture(name);
  }

  Map<String, dynamic> _filmEpisodes() {
    final film = bbcFixture('programme_film')['programmes'][0] as Map<String, dynamic>;
    return {
      'programme_episodes': {
        'count': 1,
        'page': 1,
        'per_page': 200,
        'elements': [(bbcFixture('episode_film')['episodes'] as List).first],
        'programme': film,
      },
    };
  }

  /// Programmes cloned from a recorded one, so listings of any length can be paged.
  Map<String, dynamic> _atozPage(String letter, int page, int perPage) {
    final template =
        ((bbcFixture('atoz_b')['atoz_programmes'] as Map)['elements'] as List).first as Map<String, dynamic>;
    final count = bbcLetterCounts[letter] ?? 0;
    final from = (page - 1) * perPage;
    final to = from + perPage < count ? from + perPage : count;
    return {
      'atoz_programmes': {
        'character': letter,
        'count': count,
        'page': page,
        'per_page': perPage,
        'elements': [
          for (var i = from; i < to; i++) {...template, 'id': 'p$letter$i', 'title': 'Show $letter $i'},
        ],
      },
    };
  }

  http.Response _mediaSelector(String versionId) {
    final custom = selector[versionId];
    if (custom != null) {
      final headers = {..._jsonHeaders, if (custom.status == 429) 'retry-after': '30'};
      return http.Response.bytes(utf8.encode(custom.body), custom.status, headers: headers);
    }
    return _json(bbcFixture('synthetic_mediaselector_ok'));
  }

  static const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  http.Response _json(Map<String, dynamic> body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: _jsonHeaders);

  http.Response _text(String body, String type) =>
      http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': '$type; charset=utf-8'});
}
