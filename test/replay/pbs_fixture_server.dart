import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/pbs/pbs_api.dart';
import 'package:plezy/replay/providers/pbs/pbs_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/pbs';

String pbsFixture(String name) => File('$_fixtures/$name').readAsStringSync();

/// Season ids of the recorded FRONTLINE show page and of NOVA season 53.
const frontline2023 = '9bff00dd-84c8-43b8-b244-a07079c464ef';
const nova53 = 'f72458fd-42e6-4878-b05b-2eac9e18ad97';

/// Media ids of the recorded player pages.
const playableId = '3104283534';
const refusedId = '1000000001';
const passportId = '1000000002';
const drmId = '1000000003';
const expiredId = '1000000004';
const mp4OnlyId = '1000000005';
const redirectRefusedId = '1000000006';
const passportPageId = '1000000007';
const missingId = '1000000008';
const rateLimitedId = '1000000009';
const redirect403Id = '1000000010';

const _hlsRedirect = '1480223c96e7497c85824907af3400fe';
const _mp4Redirect = '9b560318c41f4fd79389932489574e5e';
const _refusedRedirect = '6af082941db3467a94996c777f6d086e';

const _players = {
  playableId: 'player_ok.html',
  refusedId: 'player_unavailable.html',
  passportId: 'player_passport.html',
  drmId: 'player_drm.html',
  expiredId: 'player_expired.html',
  mp4OnlyId: 'player_mp4_only.html',
  redirectRefusedId: 'player_redirect_refused.html',
  redirect403Id: 'player_redirect_403.html',
  passportPageId: 'player_passport_page.html',
};

/// Serves recorded pbs.org answers and remembers what was asked.
class PbsFixtureServer {
  final List<Uri> requests = [];
  final List<String?> userAgents = [];
  final List<DateTime> times = [];

  PbsApi api({Duration interval = Duration.zero}) =>
      PbsApi(MediaServerHttpClient(client: MockClient(_handle)), interval: interval);

  PbsProvider provider() => PbsProvider.withApi(api());

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);
    userAgents.add(request.headers['User-Agent']);
    times.add(DateTime.now());
    return _answer(request.url);
  }

  http.Response _answer(Uri url) {
    switch (url.host) {
      case 'www.pbs.org':
        return _site(url);
      case 'player.pbs.org':
        return _player(url.pathSegments[1]);
      case 'urs.pbs.org':
        return _redirect(url.pathSegments[1]);
    }
    return _reply('{}', status: 404);
  }

  http.Response _site(Uri url) {
    final path = url.path;
    if (path == '/api/v1/search/') return _search(url.queryParameters['q'] ?? '');
    final season = RegExp(r'^/api/show/([^/]+)/season/([^/]+)/(episodes|extras)/$').firstMatch(path);
    if (season != null) return _seasonList(season.group(1)!, season.group(2)!, season.group(3)!);
    const pages = {
      '/show/frontline/': 'show_frontline.html',
      '/show/nova/': 'show_nova.html',
      '/explore/science-and-nature/': 'genre_science.html',
      '/': 'front.html',
      '/video/inside-the-uvalde-response-fgxvhb/': 'video_page_uvalde.html',
    };
    final page = pages[path];
    if (page != null) return _reply(pbsFixture(page), type: 'text/html; charset=utf-8');
    if (path.startsWith('/explore/')) return _reply('<html></html>', type: 'text/html; charset=utf-8');
    return _reply('Not found', status: 404, type: 'text/html; charset=utf-8');
  }

  http.Response _search(String query) => switch (query) {
    'zzzz' => _reply(pbsFixture('search_popular.json')),
    'nova' => _reply(pbsFixture('search_nova.json')),
    _ => _reply(pbsFixture('search_empty.json')),
  };

  http.Response _seasonList(String show, String season, String kind) {
    if (show == 'frontline' && season == frontline2023 && kind == 'episodes') {
      return _reply(pbsFixture('season_episodes_frontline_2023.json'));
    }
    if (show == 'nova' && season == nova53 && kind == 'extras') return _reply(pbsFixture('season_extras_nova_53.json'));
    return _reply('[]');
  }

  http.Response _player(String mediaId) {
    if (mediaId == rateLimitedId) return _reply('Slow down', status: 429, extra: {'retry-after': '30'});
    final page = _players[mediaId];
    if (page == null) return _reply('Not found', status: 404, type: 'text/html; charset=utf-8');
    return _reply(pbsFixture(page), type: 'text/html; charset=utf-8');
  }

  http.Response _redirect(String id) => switch (id) {
    _hlsRedirect => _reply(pbsFixture('urs_hls.json')),
    _mp4Redirect => _reply(pbsFixture('urs_mp4.json')),
    _refusedRedirect => _reply(pbsFixture('urs_refused.json')),
    _ => _reply('Redirect is unavailable in your region', status: 403, type: 'text/html; charset=utf-8'),
  };
}

http.Response _reply(
  String body, {
  int status = 200,
  String type = 'text/plain;charset=UTF-8',
  Map<String, String> extra = const {},
}) => http.Response.bytes(utf8.encode(body), status, headers: {'content-type': type, ...extra});
