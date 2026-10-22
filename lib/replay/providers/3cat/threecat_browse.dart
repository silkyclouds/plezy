import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'threecat_api.dart';
import 'threecat_envelope.dart';
import 'threecat_index.dart';
import 'threecat_mapper.dart';

/// Sections of the website that have a catalogue row of their own. The ids are the page names of the catalogue API.
const threeCatCategories = [
  ReplayCategory(id: 'novetats', title: 'Novetats'),
  ReplayCategory(id: 'series', title: 'Sèries'),
  ReplayCategory(id: 'entreteniment', title: 'Entreteniment'),
  ReplayCategory(id: 'infantil', title: 'Infantil'),
  ReplayCategory(id: 'arts', title: 'Arts i cultura'),
];

const _categoryFrontals = {
  'novetats': 'trescat-tresplay-novtotweb',
  'series': 'trescat-tresplseri-prodesweb',
  'entreteniment': 'trescat-entretenim-prodesweb',
  'infantil': 'trescat-tresinfant-sx3webapp',
  'arts': 'trescat-arts-nov_webapp',
};

/// Home rows that hold programmes or videos. Live channels, genre tiles, ads and account rows are left out.
const _rowTypes = {'PROGRAMES', 'VIDEOS', 'RANQUING', 'DESTACAT'};

/// Endpoints a row or a "see all" link may point at.
const _pagedEndpoints = {'tot', 'videos', 'programestv'};

/// Arguments the API client adds itself or that only make sense for one page of a row.
const _pagingArguments = {
  'pagina',
  'items_pagina',
  'limit_items',
  '_format',
  'sdom',
  'version',
  'cache',
  'https',
  'master',
  'debug',
};

const threeCatBrowsePrefix = 'q:';

/// Home rows, category pages and flat listings.
class ThreeCatBrowse {
  static const pageSize = 30;
  static const _railSize = 25;

  final ThreeCatApi _api;
  final ThreeCatMapper _mapper;
  final ThreeCatIndex _index;

  ThreeCatBrowse(this._api, this._mapper, this._index);

  Future<List<ReplayRail>> home() async {
    final answer = await _api.catalogue('tiracontinguts', {
      'origen': 'frontal',
      'frontal': 'trescat-tresplwapp-home',
      'items_pagina': '30',
      'pagina': '1',
    });
    final rows = threeCatItems(answer).where((row) => _rowTypes.contains(row['tipus'])).toList();
    final rails = await Future.wait([for (final row in rows) _rail(row)]);
    return rails.nonNulls.toList();
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    final frontal = _categoryFrontals[categoryId];
    if (frontal == null) return const [];
    final category = threeCatCategories.firstWhere((c) => c.id == categoryId);
    final browseId = '$threeCatBrowsePrefix${Uri(path: 'tot', queryParameters: {'frontal': frontal})}';
    final answer = await _api.catalogue('tot', {'frontal': frontal, 'items_pagina': '$_railSize', 'pagina': '1'});
    final titles = _mapper.titles(threeCatItems(answer));
    if (titles.isEmpty) return const [];
    return [ReplayRail(id: categoryId, title: category.title, titles: titles, moreBrowseId: browseId)];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == replayAllBrowseId) {
      final all = await _index.titles();
      final from = page * pageSize;
      final slice = from >= all.length ? const <ReplayTitle>[] : all.skip(from).take(pageSize).toList();
      return ReplayPage(titles: slice, totalCount: all.length);
    }
    final request = _parseBrowseId(browseId);
    if (request == null) return const ReplayPage(titles: [], totalCount: 0);
    final answer = await _api.catalogue(request.endpoint, {
      ...request.query,
      'items_pagina': '$pageSize',
      'pagina': '${page + 1}',
    });
    return ReplayPage(titles: _mapper.titles(threeCatItems(answer)), totalCount: threeCatPaging(answer).totalItems);
  }

  Future<ReplayRail?> _rail(Map<String, dynamic> row) async {
    final name = (row['nom'] as String?)?.trim();
    final address = Uri.tryParse('${row['url_dades_mobil'] ?? row['url_dades'] ?? ''}');
    if (name == null || name.isEmpty || address == null || !_isCatalogueRow(address)) return null;
    try {
      final answer = await _api.catalogueUri(address);
      final titles = _mapper.titles(threeCatItems(answer));
      if (titles.isEmpty) return null;
      final more = threeCatPaging(answer).totalPages > 1 ? _browseId(address) : null;
      return ReplayRail(id: 'row-${row['id']}', title: name, titles: titles, moreBrowseId: more);
    } on MediaServerHttpException {
      return null;
    } on ThreeCatRateLimitedException {
      return null;
    }
  }

  bool _isCatalogueRow(Uri address) =>
      address.scheme == 'https' &&
      address.host == ThreeCatApi.catalogueHost &&
      _pagedEndpoints.contains(address.path.replaceAll('/', '')) &&
      !address.query.contains('{{');

  /// `q:endpoint?arguments`, enough to ask the same question again for any page.
  String? _browseId(Uri address) {
    final endpoint = address.path.replaceAll('/', '');
    if (!_pagedEndpoints.contains(endpoint)) return null;
    final query = {
      for (final entry in address.queryParameters.entries)
        if (!_pagingArguments.contains(entry.key)) entry.key: entry.value,
    };
    return '$threeCatBrowsePrefix${Uri(path: endpoint, queryParameters: query.isEmpty ? null : query)}';
  }

  ({String endpoint, Map<String, String> query})? _parseBrowseId(String browseId) {
    if (!browseId.startsWith(threeCatBrowsePrefix)) return null;
    final parsed = Uri.tryParse(browseId.substring(threeCatBrowsePrefix.length));
    if (parsed == null || !_pagedEndpoints.contains(parsed.path)) return null;
    return (endpoint: parsed.path, query: parsed.queryParameters);
  }
}
