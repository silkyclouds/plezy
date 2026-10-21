import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_api.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/rtbf';
const _bff = '/auvio/v1.23/';
const _exposure = '/v2/customer/RTBF/businessunit/Auvio/';
const _assets = '/v1/customer/RTBF/businessunit/Auvio/content/asset/';

/// The moment every test runs at; recorded publication windows are all open then.
final rtbfNow = DateTime.utc(2026, 10, 21, 10);

ReplayRef rtbfRef(String nativeId) => ReplayRef('auvio', nativeId);

String rtbfFixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

Map<String, dynamic> rtbfJson(String name) => jsonDecode(rtbfFixture(name)) as Map<String, dynamic>;

http.Response rtbfReply(Object body, {int status = 200, Map<String, String> headers = const {}}) => http.Response(
  body is String ? body : jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

/// The API over recorded responses. [log] collects every request, [handler] can answer first.
RtbfApi rtbfApi({DateTime? now, List<http.Request>? log, http.Response? Function(http.Request request)? handler}) {
  final client = MockClient((request) async {
    log?.add(request);
    return handler?.call(request) ?? rtbfRoute(request);
  });
  return RtbfApi(
    MediaServerHttpClient(client: client),
    deviceId: 'test-device',
    now: () => now ?? rtbfNow,
  );
}

RtbfProvider rtbfProvider({
  DateTime? now,
  List<http.Request>? log,
  http.Response? Function(http.Request request)? handler,
}) => RtbfProvider.withApi(
  rtbfApi(now: now, log: log, handler: handler),
  now: () => now ?? rtbfNow,
);

/// Serves recorded Auvio responses by path; anything unknown is the BFF's own 404.
http.Response rtbfRoute(http.Request request) {
  final path = request.url.path;
  if (path.startsWith(_bff)) return _bffRoute(request, path.substring(_bff.length));
  if (path.startsWith(_exposure)) return _exposureRoute(request, path.substring(_exposure.length));
  if (path.startsWith(_assets)) return _assetRoute(path.substring(_assets.length));
  return http.Response('', 404);
}

http.Response _bffRoute(http.Request request, String rest) {
  final query = request.url.queryParameters;
  if (rest.startsWith('widgets/')) return _widget(rest.substring(8), query);
  if (rest.startsWith('pages/emission/')) return _programPage(rest.substring(15));
  if (rest.startsWith('pages/media/')) return _mediaPage(rest.substring(12));
  return switch (rest) {
    'pages/home' => rtbfReply(rtbfFixture('home')),
    'pages/categorie/series-35' => rtbfReply(rtbfFixture('category_series')),
    'search' => query['query'] == 'planete' ? rtbfReply(rtbfFixture('search')) : rtbfReply({'status': 200, 'data': []}),
    'mosaic/program' => _mosaic(query['_page']),
    'mosaic/widget' => _widgetMosaic(),
    _ => rtbfReply(rtbfFixture('error_not_found'), status: 404),
  };
}

http.Response _widget(String id, Map<String, String> query) {
  final program = query['context[programId]'];
  return switch (id) {
    '17226' => rtbfReply(rtbfFixture('widget_category_list')),
    '18601' => rtbfReply(rtbfFixture('widget_media_list')),
    '22683' || '19799' => rtbfReply(rtbfFixture('widget_program_list')),
    '18801' => _tabList(program),
    '18800' => _episodes(program, query),
    _ => rtbfReply({
      'data': {'id': id, 'content': <Object>[]},
      'links': {'next': null},
    }),
  };
}

http.Response _tabList(String? programId) => switch (programId) {
  '32284' => rtbfReply(rtbfFixture('show_tablist_seasons')),
  '29169' => rtbfReply(rtbfFixture('show_tablist_years')),
  '32462' => rtbfReply(rtbfFixture('show_tablist_single')),
  '29170' => rtbfReply(rtbfFixture('show_tablist_single').replaceAll('32462', '29170')),
  '29171' => rtbfReply(_oneYearTab('29171')),
  _ => rtbfReply(rtbfFixture('error_not_found'), status: 404),
};

/// The recorded year tabs cut down to the first one, for a show that has a single year.
Map<String, dynamic> _oneYearTab(String programId) {
  final tabs = rtbfJson('show_tablist_years');
  final content = (tabs['data'] as Map<String, dynamic>)['content'] as List;
  content.removeLast();
  return jsonDecode(jsonEncode(tabs).replaceAll('29169', programId)) as Map<String, dynamic>;
}

http.Response _episodes(String? programId, Map<String, String> query) {
  if (programId == '32284' && query['context[season]'] == '2') return rtbfReply(rtbfFixture('season'));
  if (programId == '29169' && query['context[year]'] == '2026') return rtbfReply(rtbfFixture('show_year_episodes'));
  if (programId == '29170' || programId == '29171') return rtbfReply(rtbfFixture('show_year_episodes'));
  if (programId == '32462') return rtbfReply(_numberedWithoutSeason());
  return rtbfReply(rtbfFixture('error_not_found'), status: 404);
}

/// Two episodes of a series whose titles carry no season marker, cut from a recorded media list.
Map<String, dynamic> _numberedWithoutSeason() {
  final cards = (rtbfJson('widget_media_list')['data'] as Map)['content'] as List;
  final card = cards.cast<Map<String, dynamic>>().firstWhere((c) => c['title'] == 'Les disparus des Argonnes');
  final second = {...card, 'id': '3540623', 'subtitle': '02 - Episode 2'};
  return {
    'data': {
      'content': [card, second],
    },
    'links': {'next': null},
  };
}

http.Response _programPage(String id) {
  return switch (id) {
    '32284' => rtbfReply(rtbfFixture('show_serie')),
    '32596' => rtbfReply(rtbfFixture('show_standalone_film')),
    '21283' => rtbfReply(rtbfFixture('show_audio')),
    '29169' => rtbfReply(_programLike(id, 'SHOW', 'Table Média')),
    '32462' => rtbfReply(_programLike(id, 'SERIE', 'Louca')),
    '29170' => rtbfReply(_programLike(id, 'SHOW', 'Magazine')),
    '29171' => rtbfReply(_programLike(id, 'SERIE', 'Fiction du jour')),
    _ => rtbfReply(rtbfFixture('error_not_found'), status: 404),
  };
}

/// A programme page of another show, with the recorded page's shape and its own tab list.
Map<String, dynamic> _programLike(String id, String type, String title) {
  final page = rtbfJson('show_serie');
  final data = page['data'] as Map<String, dynamic>;
  final content = data['content'] as Map<String, dynamic>;
  content
    ..['id'] = id
    ..['type'] = type
    ..['title'] = title
    ..['seasonCount'] = null;
  final widget = (data['widgets'] as List).first as Map<String, dynamic>;
  widget['contentPath'] = 'https://bff-service.rtbf.be/auvio/v1.23/widgets/18801?context%5BprogramId%5D=$id';
  return page;
}

http.Response _mediaPage(String id) => switch (id) {
  '3507958' => rtbfReply(rtbfFixture('media_page_episode')),
  '3530011' => rtbfReply(rtbfFixture('media_page_film')),
  '3516005' => rtbfReply(rtbfFixture('media_page_free_magazine')),
  _ => rtbfReply(rtbfFixture('error_not_found'), status: 404),
};

/// The recorded row as a complete grid.
http.Response _widgetMosaic() {
  final row = rtbfJson('widget_program_list');
  return rtbfReply({
    'data': (row['data'] as Map)['content'],
    'links': {'next': null},
  });
}

/// Page 1 is recorded. Page 2 reuses its cards under new ids and adds one audio programme, which the
/// provider must drop.
http.Response _mosaic(String? page) {
  final first = rtbfJson('mosaic_program');
  if (page != '2') return rtbfReply(first);
  final cards = [
    for (final c in (first['data'] as List).cast<Map<String, dynamic>>())
      {...c, 'id': '9${c['id']}', 'title': '${c['title']} bis'},
    {'resourceType': 'PROGRAM', 'id': '99001', 'title': 'Podcast', 'type': 'AUDIO_SHOW'},
  ];
  return rtbfReply({
    'data': cards,
    'meta': first['meta'],
    'links': {'next': null},
  });
}

http.Response _exposureRoute(http.Request request, String rest) {
  if (rest == 'auth/anonymous') return rtbfReply(rtbfFixture('redbee_anonymous_login'));
  final match = RegExp(r'^entitlement/(\d+)_6BA97Bb/play$').firstMatch(rest);
  if (match == null) return http.Response('', 404);
  if (request.headers['Authorization'] != 'Bearer <redacted>') {
    return rtbfReply({'httpCode': 401, 'message': 'INVALID_SESSION_TOKEN'}, status: 401);
  }
  return _entitlement(match.group(1)!);
}

http.Response _entitlement(String mediaId) {
  if (mediaId.startsWith('35079')) return rtbfReply(rtbfFixture('entitlement_not_entitled_login'), status: 403);
  return switch (mediaId) {
    '3516005' => rtbfReply(rtbfFixture('entitlement_clear_vod')),
    '3529347' => rtbfReply(rtbfFixture('entitlement_clear_vod_subtitles')),
    '3541035' => rtbfReply(rtbfFixture('entitlement_clear_audio_mp3')),
    '3516216' => rtbfReply(rtbfFixture('entitlement_drm_widevine')),
    '3540042' => rtbfReply(rtbfFixture('entitlement_not_entitled_login'), status: 403),
    '3532118' => rtbfReply(rtbfFixture('entitlement_buy_premium'), status: 403),
    '3600001' => rtbfReply({'httpCode': 403, 'message': 'GEO_BLOCKED'}, status: 403),
    '3600002' => rtbfReply({
      'httpCode': 403,
      'message': 'NOT_ENTITLED',
      'actions': [
        {
          'type': 'LOGIN',
          'publication': {'availableAt': '2026-12-01T05:00:00Z', 'publicationId': '3600002_belgium_6BA97Bb'},
        },
      ],
    }, status: 403),
    '3600003' => rtbfReply('{}', status: 429, headers: {'retry-after': '30'}),
    _ => rtbfReply({'httpCode': 404, 'message': 'UNKNOWN_ASSET'}, status: 404),
  };
}

http.Response _assetRoute(String assetId) {
  final mediaId = assetId.split('_').first;
  if (mediaId == '9999999') return rtbfReply({'httpCode': 404, 'message': 'UNKNOWN_ASSET'}, status: 404);
  if (mediaId.startsWith('35079') || mediaId == '3540042') return rtbfReply(rtbfFixture('redbee_asset_login_required'));
  return rtbfReply(rtbfFixture('redbee_asset_anonymous'));
}
