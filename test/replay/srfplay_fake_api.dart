import 'package:http/http.dart' as http;
import 'package:plezy/replay/providers/srfplay/srfplay_provider.dart';
import 'package:plezy/replay/providers/srfplay/srfplay_unit.dart';
import 'package:plezy/replay/providers/srg/srg_api.dart';

import 'srg_test_support.dart';

const srfDir = 'srfplay';
const srfDokId = 'c66487b3-0990-0001-d92c-55501cb0144d';
const srfTagesschauVideo = '3e408dd4-2e13-4d03-ab6f-55ef0d0e9019';
const srfGeoVideo = 'f28c7b5e-d2ef-4ff9-bd6a-73fe15ec29c3';
const srfDokTopic = '516421f0-ec89-43ba-823b-1b5ceec262f3';
const srfRowWithBlocked = '16b39727-1133-488a-a581-88c34c5f71d6';

const _rowOfShows = 'f0c9649d-c8e3-4761-84d5-5e7522443bed';
const _rowWithShow = '86c7af51-be89-4492-8c79-817abc938ba5';

/// A provider over [route], which defaults to the recorded SRF Play responses plus a few made-up shows.
SrfPlayProvider srfProvider({List<http.Request>? log, http.Response Function(http.Request)? route}) {
  return SrfPlayProvider.withApi(SrgApi(srfPlayUnit, srgClient(route ?? srfRoute, log: log)));
}

/// Serves recorded Integration Layer responses by path; anything unknown is an empty list or a 404.
http.Response srfRoute(http.Request request) {
  final path = srgPath(request);
  final q = request.url.queryParameters;
  if (path.startsWith('mediaComposition/byUrn/urn:srf:video:')) return _playback(path.split(':').last);
  if (!path.startsWith('srf/')) return srgJson('{"status":404}', 404);
  final unit = path.substring(4);
  if (unit.startsWith('searchResult')) return _search(unit, q);
  if (unit.startsWith('show/tv/')) return _show(unit.split('/').last);
  if (unit.startsWith('mediaList/video/latest/byShow/')) return _episodes(unit.split('/').last, q);
  if (unit.startsWith('section/')) return _section(unit.split('/').last);
  return _lists(unit, q);
}

http.Response _lists(String path, Map<String, String> q) {
  return switch (path) {
    'topicList/tv' => srgJson(srgFixture(srfDir, 'topics')),
    'page/byTopicUrn/urn:srf:topic:tv:$srfDokTopic' => srgJson(srgFixture(srfDir, 'topic_page')),
    'mediaList/video/trending' => srgJson(srgFixture(srfDir, 'trending')),
    'mediaList/video/latestEpisodes' => srgJson(srgFixture(srfDir, 'latest_episodes')),
    'showList/tv/alphabetical' => srgJson(q['next'] == '1' ? srgEmptyLists : srgFixture(srfDir, 'shows_page0')),
    _ => srgJson(srgEmptyLists),
  };
}

http.Response _section(String id) {
  return switch (id) {
    _rowOfShows => srgJson(srgFixture(srfDir, 'section_show')),
    srfRowWithBlocked => srgJson({
      ...srgFixtureMap(srfDir, 'section_media'),
      'next': 'https://il.srgssr.ch/integrationlayer/2.0/srf/section/mediaSection/$id?next=1',
    }),
    _rowWithShow => srgJson(srgFixture(srfDir, 'section_media_with_show')),
    _ => srgJson(srgEmptyLists),
  };
}

http.Response _search(String path, Map<String, String> q) {
  final text = q['q'];
  if (path == 'searchResultShowList') {
    return srgJson(switch (text) {
      'kassensturz' => srgFixture(srfDir, 'search_shows'),
      'bestatter' => {
        'searchResultShowList': [
          {'id': 'b1', 'title': 'Der Bestatter mit Audiodeskription', 'numberOfEpisodes': 12},
        ],
      },
      'arena' => {
        'searchResultShowList': [
          {'id': 'a1', 'title': 'Arena', 'numberOfEpisodes': 300},
          {'id': 'a2', 'title': 'Arena mit Audiodeskription', 'numberOfEpisodes': 300},
        ],
      },
      _ => srgEmptyLists,
    });
  }
  return srgJson(switch (text) {
    'kassensturz' => srgFixture(srfDir, 'search_media'),
    'radio' => {
      'searchResultMediaList': [
        {'id': 'a1', 'urn': 'urn:srf:audio:a1', 'mediaType': 'AUDIO', 'type': 'EPISODE', 'title': 'Radio'},
        ...(srgFixtureMap(srfDir, 'search_media')['searchResultMediaList'] as List).take(1),
      ],
    },
    _ => srgEmptyLists,
  });
}

http.Response _show(String id) {
  final body = switch (id) {
    srfDokId => srgFixture(srfDir, 'show_dok'),
    'daily' => '{"id":"daily","title":"Journal","numberOfEpisodes":450}',
    'geo' => '{"id":"geo","title":"DOK","numberOfEpisodes":3}',
    'closed' => '{"id":"closed","title":"Kinderserie","numberOfEpisodes":2}',
    _ => null,
  };
  return body == null ? srgJson('{"status":404}', 404) : srgJson(body);
}

http.Response _episodes(String id, Map<String, String> q) {
  switch (id) {
    case srfDokId:
      return srgJson(_dokEpisodes());
    case 'daily':
      return srgDailyPage('srf', int.parse(q['next'] ?? '0'), 450);
    case 'geo':
      return srgJson({...srgFixtureMap(srfDir, 'show_episodes_with_geoblock'), 'next': null});
    case 'closed':
      return srgJson({
        'mediaList': [
          for (var n = 1; n <= 2; n++)
            srgVideo('srf', 'k$n', '2026-03-0${n}T10:00:00+01:00', show: 'closed', count: 2, playableAbroad: false),
        ],
      });
  }
  return srgJson(srgEmptyLists);
}

/// Four numbered episodes of season 4 and a making-of clip that carries no number.
Map<String, dynamic> _dokEpisodes() {
  final recorded = srgFixtureMap(srfDir, 'show_episodes_with_seasons');
  final items = [...(recorded['mediaList'] as List)];
  final clip = {...(items.first as Map<String, dynamic>), 'id': 'clip1', 'urn': 'urn:srf:video:clip1', 'type': 'CLIP'}
    ..remove('episode')
    ..['title'] = 'Making of';
  return {
    'mediaList': [...items, clip],
  };
}

http.Response _playback(String id) {
  const hls = 'https://cdn.example/world/x/master.m3u8';
  return switch (id) {
    srfTagesschauVideo => srgJson(srgFixture(srfDir, 'media_composition_clear')),
    srfGeoVideo => srgJson(srgFixture(srfDir, 'media_composition_geoblocked')),
    'no-stream-abroad' => srgJson(srgComposition('srf', playableAbroad: false)),
    'no-stream' => srgJson(srgComposition('srf')),
    'ended' => srgJson(srgComposition('srf', blockReason: 'ENDDATE')),
    'upcoming' => srgJson(srgComposition('srf', blockReason: 'STARTDATE')),
    'age' => srgJson(srgComposition('srf', blockReason: 'AGERATING12')),
    'drm' => srgJson(
      srgComposition(
        'srf',
        resources: [
          srgResource(
            'HLS',
            hls,
            drm: [
              {'type': 'WIDEVINE'},
            ],
          ),
        ],
      ),
    ),
    'mp4' => srgJson(srgComposition('srf', resources: [srgResource('PROGRESSIVE', 'https://cdn.example/a.mp4')])),
    'limited' => srgJson('{}', 429, {'retry-after': '30'}),
    _ => srgJson('{"status":404}', 404),
  };
}
