import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/providers/3cat/threecat_api.dart';
import 'package:plezy/replay/providers/3cat/threecat_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/3cat';

/// The recorded answer `name` (without extension).
Map<String, dynamic> threeCatFixture(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// The items of a recorded list answer.
List<Map<String, dynamic>> threeCatFixtureItems(String name) =>
    ((threeCatFixture(name)['resposta'] as Map)['items'] as Map)['item'].cast<Map<String, dynamic>>();

/// A copy of a recorded video with the fields a test cares about replaced.
Map<String, dynamic> threeCatVideoItem({
  required int id,
  required String title,
  required String programmeId,
  String programmeName = 'Programa',
  String? season,
  int? number,
  String? geo,
  String? duration,
}) {
  final item = jsonDecode(jsonEncode(threeCatFixtureItems('videos_multi_season_all').first)) as Map<String, dynamic>;
  item['id'] = id;
  item['titol'] = title;
  item['permatitle'] = title;
  item['capitol_temporada'] = number ?? -1;
  item['durada'] = duration ?? '00:30:00:00';
  season == null
      ? item.remove('temporades')
      : item['temporades'] = [
          {'id': season, 'desc': 'Temporada ${season.split('_').last}', 'main': true},
        ];
  geo == null
      ? item.remove('geolocalitzacions')
      : item['geolocalitzacions'] = [
          {'id': geo},
        ];
  final programme = (item['programes_tv'] as List).first as Map<String, dynamic>;
  programme['id'] = programmeId;
  programme['titol'] = programmeName;
  return item;
}

/// Serves the recorded 3Cat answers, and a few made-up programmes, over a mock transport.
class ThreeCatFakeSite {
  /// Episodes by programme id, on top of the two recorded programmes.
  final Map<String, List<Map<String, dynamic>>> programmes;

  /// First say, for answers a test needs to invent.
  final http.Response? Function(http.Request request)? custom;

  /// Whether the Spain-only stream hosts accept this viewer.
  final bool spainReachable;

  final List<Uri> requests = [];
  final List<String?> userAgents = [];

  ThreeCatFakeSite({this.programmes = const {}, this.custom, this.spainReachable = false});

  ThreeCatApi api() => ThreeCatApi(MediaServerHttpClient(client: MockClient((r) async => _handle(r))));

  ThreeCatProvider provider({DateTime? now}) =>
      ThreeCatProvider.withApi(api(), now: () => now ?? DateTime.utc(2026, 10, 22, 12));

  Iterable<Uri> requestsTo(String host) => requests.where((u) => u.host == host);

  http.Response _handle(http.Request request) {
    requests.add(request.url);
    userAgents.add(request.headers['User-Agent']);
    final custom = this.custom?.call(request);
    if (custom != null) return custom;
    final url = request.url;
    return switch (url.host) {
      'api.3cat.cat' => _catalogue(url),
      'api-media.3cat.cat' => _media(url),
      'www.3cat.cat' => http.Response(
        File('$_fixtures/az_page.html').readAsStringSync(),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
      final host when host.endsWith('.3catvideos.cat') => _stream(host),
      _ => http.Response('{}', 404),
    };
  }

  http.Response _catalogue(Uri url) {
    final query = url.queryParameters;
    final path = url.path;
    if (path == '/tiracontinguts') return json(threeCatFixture('home_tires'));
    if (path == '/tot') return json(threeCatFixture('tot_novetats'));
    if (path == '/videos') return _videos(query);
    if (path == '/cercador/tot') return _search(query);
    final programme = RegExp(r'^/programestv/(\d+)/$').firstMatch(path)?.group(1);
    if (programme != null) return _programme(programme);
    return http.Response('{}', 404);
  }

  http.Response _programme(String id) {
    if (id == '76976') return json(threeCatFixture('programestv_item'));
    if (id == '54076') return json(threeCatFixture('programestv_item_multi_season'));
    if (!programmes.containsKey(id)) return http.Response('{}', 404);
    final body = threeCatFixture('programestv_item');
    final item = (body['resposta'] as Map)['item'] as Map;
    item['id'] = int.parse(id);
    item['titol'] = 'Programa $id';
    return json(body);
  }

  http.Response _videos(Map<String, String> query) {
    final programme = query['programatv_id'];
    if (programme == null) return json(threeCatFixture('videos_programme'));
    var items = switch (programme) {
      '76976' => threeCatFixtureItems('videos_programme'),
      '54076' => [
        ...threeCatFixtureItems('videos_multi_season_all'),
        ...threeCatFixtureItems('videos_season_filter_temporada'),
      ],
      _ => programmes[programme] ?? const <Map<String, dynamic>>[],
    };
    final season = query['temporada'];
    if (season != null) {
      items = [
        for (final item in items)
          if ((item['temporades'] as List?)?.first['id'] == season) item,
      ];
    }
    return json(listAnswer(items, size: int.parse(query['items_pagina']!), page: int.parse(query['pagina']!)));
  }

  http.Response _search(Map<String, String> query) {
    if (query['text'] == 'cap resultat') return json(listAnswer(const []));
    if (query['tipologia'] == 'PTVC_PROGRAMA') {
      final shows = threeCatFixtureItems('tot_novetats').where((i) => i['tipologia'] == 'PTVC_PROGRAMA');
      return json(listAnswer([...threeCatFixtureItems('search_tot'), ...shows]));
    }
    return json(listAnswer(threeCatFixtureItems('search_videos')));
  }

  http.Response _media(Uri url) {
    return switch (url.queryParameters['idint']) {
      '6431752' => json(threeCatFixture('media_tots')),
      '6431644' => json(threeCatFixture('media_espanya')),
      _ => http.Response('{}', 404),
    };
  }

  http.Response _stream(String host) {
    final restricted = host.contains('-es.');
    if (restricted && !spainReachable) return http.Response('', 403, headers: {'content-type': 'text/plain'});
    return http.Response('x', 206, headers: {'content-type': 'video/mp4'});
  }
}

http.Response json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// A list answer holding one page of [items], shaped like the catalogue's.
Map<String, dynamic> listAnswer(List<Map<String, dynamic>> items, {int size = 100, int page = 1, int? total}) {
  final count = total ?? items.length;
  final from = (page - 1) * size;
  final slice = from >= items.length ? const <Map<String, dynamic>>[] : items.skip(from).take(size).toList();
  return {
    'resposta': {
      'status': 'OK',
      'items': {'num': slice.length, 'item': slice},
      'paginacio': {
        'total_items': count,
        'items_pagina': size,
        'pagina_actual': page,
        'total_pagines': count == 0 ? 0 : (count + size - 1) ~/ size,
      },
    },
  };
}
