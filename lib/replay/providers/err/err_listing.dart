import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'err_api.dart';
import 'err_rails.dart';

/// Flat, paged listings: the whole catalogue, the genre pages and the section pages.
class ErrListing {
  static const _catalogueTtl = Duration(hours: 12);

  final ErrApi _api;
  final DateTime Function() _now;
  ({DateTime at, List<ReplayTitle> titles})? _catalogue;
  Future<List<ReplayTitle>>? _loading;

  ErrListing(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// [browseId] is [replayAllBrowseId] for the whole catalogue, or the slug of a genre or section page.
  Future<ReplayPage> page(String browseId, {required int page, required int size}) async {
    final start = page * size;
    if (browseId == replayAllBrowseId) {
      final titles = await _wholeCatalogue();
      return ReplayPage(titles: titles.skip(start).take(size).toList(), totalCount: titles.length);
    }
    final category = await _api.categoryPage(browseId);
    final items = category == null ? const [] : errCategoryItems(category);
    return ReplayPage(titles: errTitles(items.skip(start).take(size)), totalCount: items.length);
  }

  /// Every title, A to Z. The raw catalogue is 20 MB, so only the mapped titles are kept, for half a day.
  Future<List<ReplayTitle>> _wholeCatalogue() {
    final cached = _catalogue;
    if (cached != null && _now().difference(cached.at) < _catalogueTtl) return Future.value(cached.titles);
    return _loading ??= _loadCatalogue().whenComplete(() => _loading = null);
  }

  Future<List<ReplayTitle>> _loadCatalogue() async {
    final titles = errTitles(await _api.catalogueItems())
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _catalogue = (at: _now(), titles: titles);
    return titles;
  }
}
