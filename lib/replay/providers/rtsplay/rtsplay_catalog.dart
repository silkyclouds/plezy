import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtsplay_api.dart';
import 'rtsplay_mapper.dart';

const _listingPageSize = 100;
const _rowSize = 30;
const _maxRows = 10;
const _maxShowPages = 10;

/// Rows of the landing page, in the order shown. Each is a video list the Integration Layer ranks itself.
const _homeRows = [
  (id: 'latest', title: 'Derniers épisodes', path: 'mediaList/video/latestEpisodes', size: 30),
  (id: 'trending', title: 'Tendances', path: 'mediaList/video/trending', size: 50),
  (id: 'mostClicked', title: 'Les plus vus', path: 'mediaList/video/mostClicked', size: 50),
  (id: 'soonExpiring', title: 'Bientôt retirés', path: 'mediaList/video/soonExpiring', size: 20),
];

/// Editorial rows of a topic page that hold content; the others are promotion banners and topic pickers.
const _rowKinds = {'Swimlane', 'Highlight', 'Grid'};
const _sectionTypes = {'ShowSection', 'MediaSection', 'MediaSectionWithShow'};

final _pictographs = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true);

/// Home rows, topic pages, flat listings and search over the Integration Layer.
class RtsPlayCatalog {
  final RtsPlayApi _api;

  RtsPlayCatalog(this._api);

  Future<List<ReplayCategory>> categories() async {
    final list = (await _api.unit('topicList/tv'))?['topicList'];
    if (list is! List) return const [];
    return [
      for (final topic in list.whereType<Map<String, dynamic>>())
        if (topic['id'] != null && topic['title'] is String)
          ReplayCategory(id: '${topic['id']}', title: topic['title'] as String),
    ];
  }

  Future<List<ReplayRail>> home() async {
    final rails = await Future.wait([
      for (final row in _homeRows) _videoRail(row.id, row.title, row.path, {'pageSize': '${row.size}'}),
    ]);
    return [for (final rail in rails) ?rail];
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    if (!RegExp(r'^\d+$').hasMatch(categoryId)) return const [];
    final page = await _api.unit('page/byTopicUrn/urn:rts:topic:tv:$categoryId');
    final sections = page?['sectionList'];
    if (sections is! List) return const [];
    final rows = [
      for (final s in sections.whereType<Map<String, dynamic>>())
        if (_isContentRow(s)) s,
    ].take(_maxRows);
    final rails = await Future.wait([for (final section in rows) _sectionRail(section)]);
    return [for (final rail in rails) ?rail];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == replayAllBrowseId) return _allShows(page);
    final cut = browseId.indexOf('/');
    final type = cut > 0 ? browseId.substring(0, cut) : '';
    if (!_sectionTypes.contains(type)) return const ReplayPage(titles: [], totalCount: 0);
    final body = await _section(type, browseId.substring(cut + 1), pageSize: _listingPageSize, page: page);
    final titles = _sectionTitles(type, body, playableOnly: false);
    final more = body?['next'] is String ? 1 : 0;
    return ReplayPage(titles: titles, totalCount: page * _listingPageSize + titles.length + more);
  }

  /// Shows first, then videos, so a programme name finds the programme before its episodes.
  Future<List<ReplayTitle>> search(String query) async {
    final results = await Future.wait([
      _api.unit('searchResultShowList', {'q': query, 'pageSize': '20'}),
      _api.unit('searchResultMediaList', {'q': query, 'pageSize': '20', 'includeAggregations': 'false'}),
    ]);
    final seen = <String>{};
    return [
      for (final show in _maps(results[0]?['searchResultShowList']))
        if (!rtsIsSignedShow(show['title'] as String? ?? ''))
          if (rtsTitleFromShow(show) case final title? when seen.add(title.ref.nativeId)) title,
      for (final media in _maps(results[1]?['searchResultMediaList']))
        if (rtsTitleFromMedia(media) case final title? when seen.add(title.ref.nativeId)) title,
    ];
  }

  Future<ReplayRail?> _videoRail(String id, String title, String path, Map<String, String> query) async {
    final titles = [
      for (final media in _maps((await _api.unit(path, query))?['mediaList']))
        if (rtsTitleFromMedia(media) case final t? when t.availability == ReplayAvailability.playable) t,
    ];
    return titles.isEmpty ? null : ReplayRail(id: id, title: title, titles: titles);
  }

  Future<ReplayRail?> _sectionRail(Map<String, dynamic> section) async {
    final type = section['sectionType'] as String;
    final id = section['id'] as String;
    final body = await _section(type, id, pageSize: _rowSize);
    final titles = _sectionTitles(type, body, playableOnly: true);
    if (titles.isEmpty) return null;
    final heading = (section['representation'] as Map?)?['properties']?['title'] as String? ?? '';
    return ReplayRail(
      id: id,
      title: heading.replaceAll(_pictographs, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
      titles: titles,
      moreBrowseId: body?['next'] is String ? '$type/$id' : null,
    );
  }

  Future<Map<String, dynamic>?> _section(String type, String id, {required int pageSize, int page = 0}) {
    final path = 'section/${type[0].toLowerCase()}${type.substring(1)}/$id';
    return _api.unit(path, {
      'vector': 'portalplay',
      'isPublished': 'true',
      'pageSize': '$pageSize',
      if (page > 0) 'next': '$page',
    });
  }

  List<ReplayTitle> _sectionTitles(String type, Map<String, dynamic>? body, {required bool playableOnly}) {
    if (type == 'ShowSection') return _shows(_maps(body?['showList']));
    return [
      for (final media in _maps(body?['mediaList']))
        if (rtsTitleFromMedia(media) case final t? when !playableOnly || t.availability == ReplayAvailability.playable)
          t,
    ];
  }

  Future<ReplayPage> _allShows(int page) async {
    final shows = <ReplayTitle>[];
    var body = await _api.unit('showList/tv/alphabetical', {'pageSize': '$_listingPageSize'});
    for (var pages = 0; body != null && pages < _maxShowPages; pages++) {
      shows.addAll(_shows(_maps(body['showList'])));
      final next = body['next'];
      body = next is String ? await _api.link(next) : null;
    }
    final from = (page * _listingPageSize).clamp(0, shows.length);
    final to = (from + _listingPageSize).clamp(from, shows.length);
    return ReplayPage(titles: shows.sublist(from, to), totalCount: shows.length);
  }

  List<ReplayTitle> _shows(List<Map<String, dynamic>> shows) {
    return [
      for (final show in shows)
        if (!rtsIsSignedShow(show['title'] as String? ?? '') && rtsEpisodeCount(show) != 0) ?rtsTitleFromShow(show),
    ];
  }

  bool _isContentRow(Map<String, dynamic> section) {
    final kind = (section['representation'] as Map?)?['name'];
    return _sectionTypes.contains(section['sectionType']) && _rowKinds.contains(kind) && section['id'] is String;
  }
}

List<Map<String, dynamic>> _maps(Object? list) =>
    list is List ? list.whereType<Map<String, dynamic>>().toList() : const [];
