import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/tvlocales/telemb_provider.dart';
import 'package:plezy/replay/providers/tvlocales/telesambre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvlux_provider.dart';

import 'tvlocales_fixtures.dart';

/// An episode of the fake Télé MB whose page and video both exist.
const mbEpisode = 'les-infos/les-infos-du-mardi-20-octobre-2026/41114';

/// Folder of the Télé MB video that the fake Freecaster serves.
const hlsOfTelemb = 'https://tvlocales-vod-cmaf.freecaster.com/telemb/a30728c1-8f75-4470-8c04-ff1008c4a6ea';

/// Episode pages of the fake Télé MB, each leading to a different Freecaster answer.
final _episodePages = <String, String Function()>{
  '/replay/emission/$mbEpisode': () => tvLocalesFixture('drupal_episode_telemb.html'),
  '/replay/emission/les-infos/expired/1': () => tvLocalesPlayerPage('10000000-0000-0000-0000-000000000001'),
  '/replay/emission/les-infos/limited/2': () => tvLocalesPlayerPage('20000000-0000-0000-0000-000000000002'),
  '/replay/emission/les-infos/no-streams/3': () => tvLocalesPlayerPage('30000000-0000-0000-0000-000000000003'),
  '/replay/emission/les-infos/mp4-only/4': () => tvLocalesPlayerPage('40000000-0000-0000-0000-000000000004'),
  '/replay/emission/le-22h30/article/5': () => tvLocalesFixture('drupal_episode_article_tvcom.html'),
  '/replay/jt/jt-du-20-10-2026_52614': () => tvLocalesFixture('tvlux_episode_jt.html'),
  '/replay/archeosphere/archeosphere-2eme-partie_19074': () => tvLocalesFixture('tvlux_episode_archeosphere.html'),
};

http.Response? _freecaster(http.Request request) {
  final id = request.url.pathSegments.last.replaceAll('.json', '');
  if (id.startsWith('10000000')) return http.Response('', 404);
  if (id.startsWith('20000000')) return http.Response('', 429, headers: {'retry-after': '30'});
  final fixture = tvLocalesVideos[id];
  return fixture == null ? null : jsonResponse(tvLocalesFixture(fixture));
}

http.Response? tvLocalesSitePage(http.Request request) {
  final url = request.url;
  final path = url.path;
  final query = url.query;
  final fixtures = <String, String>{
    '/emissions': url.host == 'www.telemb.be' ? 'drupal_emissions_telemb.html' : 'drupal_emissions_telesambre.html',
    '/emission/les-infos': query.isEmpty
        ? 'drupal_show_telemb_les_infos.html'
        : 'drupal_show_telemb_les_infos_last.html',
    '/emission/le-jt': query.contains('59856')
        ? 'drupal_show_telesambre_le_jt_2023.html'
        : 'drupal_show_telesambre_le_jt.html',
    '/emission/pedagoscope': 'drupal_show_tvcom_pedagoscope.html',
    '/emission/le-22h30': 'drupal_show_tvcom_articles_only.html',
    '/emission/flaky': query.isEmpty ? 'flaky' : '',
    '/replay': 'tvlux_replay_index.html',
    '/replay/jt': 'tvlux_show_jt.html',
  };
  final name = fixtures[path];
  if (name == '') return http.Response('boom', 500);
  if (name == 'flaky') {
    final body = tvLocalesFixture(
      'drupal_show_telemb_les_infos.html',
    ).replaceAll('/emission/les-infos/', '/emission/flaky/');
    return htmlResponse(body);
  }
  if (name != null) return htmlResponse(tvLocalesFixture(name));
  final page = _episodePages[path];
  return page == null ? null : htmlResponse(page());
}

http.Response? tvLocalesRoute(http.Request request) =>
    request.url.host == 'tvlocales-player.freecaster.com' ? _freecaster(request) : tvLocalesSitePage(request);

TelesambreProvider fakeTelesambre({TvLocalesLog? log}) =>
    TelesambreProvider.withApi(tvLocalesApi(tvLocalesRoute, log: log));

TeleMbProvider fakeTelemb({TvLocalesLog? log}) => TeleMbProvider.withApi(tvLocalesApi(tvLocalesRoute, log: log));

TvLuxProvider fakeTvlux({TvLocalesLog? log}) => TvLuxProvider.withApi(tvLocalesApi(tvLocalesRoute, log: log));

ReplayRef mbRef(String id) => ReplayRef('telemb', id);

ReplayRef sambreRef(String id) => ReplayRef('telesambre', id);

ReplayRef luxRef(String id) => ReplayRef('tvlux', id);
