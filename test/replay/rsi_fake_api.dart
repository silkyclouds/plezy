import 'package:http/http.dart' as http;
import 'package:plezy/replay/providers/rsi/rsi_provider.dart';
import 'package:plezy/replay/providers/rsi/rsi_unit.dart';
import 'package:plezy/replay/providers/srg/srg_api.dart';

import 'srg_test_support.dart';

const rsiDir = 'rsi';
const rsiNewsTopic = '7';
const rsiQuotidianoVideo = '4141490';
const rsiTelegiornaleVideo = '4141499';
const rsiFaloVideo = '4181717';
const rsiGeoVideo = '4122904';
const rsiAlpinismoShow = '2649987';
const rsiAgentShow = '3063383';

/// A provider over [route], which defaults to the recorded RSI Play responses plus a few made-up shows.
RsiProvider rsiProvider({List<http.Request>? log, http.Response Function(http.Request)? route}) {
  return RsiProvider.withApi(SrgApi(rsiUnit, srgClient(route ?? rsiRoute, log: log)));
}

/// Serves recorded Integration Layer responses by path; anything unknown is an empty list or a 404.
http.Response rsiRoute(http.Request request) {
  final path = srgPath(request);
  final q = request.url.queryParameters;
  if (path.startsWith('mediaComposition/byUrn/urn:rsi:video:')) return _playback(path.split(':').last);
  if (!path.startsWith('rsi/')) return srgJson('{"status":404}', 404);
  final unit = path.substring(4);
  if (unit.startsWith('searchResult')) return _search(unit, q);
  if (unit.startsWith('show/tv/')) return _show(unit.split('/').last);
  if (unit.startsWith('mediaList/video/latest/byShow/')) return _episodes(unit.split('/').last, q);
  if (unit.startsWith('section/')) return _section(unit.split('/')[1]);
  return _lists(unit, q);
}

http.Response _lists(String path, Map<String, String> q) {
  return switch (path) {
    'topicList/tv' => srgJson(srgFixture(rsiDir, 'topics')),
    'page/byTopicUrn/urn:rsi:topic:tv:$rsiNewsTopic' => srgJson(srgFixture(rsiDir, 'topic_page')),
    'mediaList/video/trending' => srgJson(srgFixture(rsiDir, 'trending')),
    'mediaList/video/latestEpisodes' => srgJson(srgFixture(rsiDir, 'show_episodes')),
    'showList/tv/alphabetical' => srgJson(q['next'] == '1' ? srgEmptyLists : srgFixture(rsiDir, 'shows_page0')),
    _ => srgJson(srgEmptyLists),
  };
}

/// Every row of a topic page answers with a recorded list of the right kind.
http.Response _section(String type) {
  return srgJson(type == 'showSection' ? srgFixture(rsiDir, 'shows_page0') : srgFixture(rsiDir, 'trending'));
}

http.Response _search(String path, Map<String, String> q) {
  final text = q['q'];
  if (path == 'searchResultShowList') {
    return srgJson(switch (text) {
      'falo' => srgFixture(rsiDir, 'search_shows'),
      'quotidiano' => {
        'searchResultShowList': [
          for (final title in [
            'Il Quotidiano',
            'Il Quotidiano LIS',
            'Eurovision - LIS',
            'Blind (con audiodescrizione)',
            'Blind',
            'Scuola (con audiodescrizione)',
          ])
            {'id': title.hashCode.toString(), 'title': title, 'numberOfEpisodes': 20},
        ],
      },
      _ => srgEmptyLists,
    });
  }
  return srgJson(switch (text) {
    'falo' => srgFixture(rsiDir, 'search_media'),
    'romancio' => {
      'searchResultMediaList': [
        srgVideo('rtr', 'r1', '2026-10-01T20:00:00+02:00'),
        srgVideo('rsi', 'i1', '2026-10-01T20:00:00+02:00'),
      ],
    },
    _ => srgEmptyLists,
  });
}

http.Response _show(String id) {
  final body = switch (id) {
    rsiAlpinismoShow => srgFixture(rsiDir, 'show_alpinismo'),
    rsiAgentShow => srgFixture(rsiDir, 'show_agent'),
    '703565' => '{"id":"703565","title":"Falò","numberOfEpisodes":2924}',
    'daily' => '{"id":"daily","title":"Telegiornale","numberOfEpisodes":450}',
    _ => null,
  };
  return body == null ? srgJson('{"status":404}', 404) : srgJson(body);
}

http.Response _episodes(String id, Map<String, String> q) {
  return switch (id) {
    rsiAlpinismoShow => srgJson(srgFixture(rsiDir, 'show_alpinismo_episodes')),
    rsiAgentShow => srgJson(srgFixture(rsiDir, 'show_agent_episodes')),
    'daily' => srgDailyPage('rsi', int.parse(q['next'] ?? '0'), 450),
    _ => srgJson(srgEmptyLists),
  };
}

http.Response _playback(String id) {
  return switch (id) {
    rsiQuotidianoVideo => srgJson(srgFixture(rsiDir, 'media_composition_clear_il')),
    rsiTelegiornaleVideo => srgJson(srgFixture(rsiDir, 'media_composition_clear_telegiornale')),
    rsiFaloVideo => srgJson(srgFixture(rsiDir, 'media_composition_clear_falo')),
    rsiGeoVideo => srgJson(srgFixture(rsiDir, 'media_composition_geoblocked')),
    'drm' => srgJson(
      srgComposition(
        'rsi',
        resources: [
          srgResource(
            'HLS',
            'https://cdn.example/ww/x/master.m3u8',
            drm: [
              {'type': 'FAIRPLAY'},
            ],
          ),
        ],
      ),
    ),
    'mp4' => srgJson(srgComposition('rsi', resources: [srgResource('PROGRESSIVE', 'https://cdn.example/a.mp4')])),
    'ended' => srgJson(srgComposition('rsi', blockReason: 'ENDDATE')),
    _ => srgJson('{"status":404}', 404),
  };
}
