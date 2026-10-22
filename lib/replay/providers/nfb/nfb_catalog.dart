import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nfb_api.dart';
import 'nfb_ids.dart';
import 'nfb_mapper.dart';
import 'nfb_series_page.dart';

/// Resolves the show, season and episode levels of the NFB's series.
///
/// A season ref is `s/{series}/{number}`. Episodes are ordinary films with their own page and player, so an
/// episode ref is its film slug. Series pages are kept for ten minutes because every level reads the same page.
class NfbCatalog {
  static const _ttl = Duration(minutes: 10);

  final NfbApi _api;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, NfbSeries? series})> _pages = {};

  NfbCatalog(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Every English series, for the home page, the Series category and search.
  Future<List<ReplayTitle>> shows() async => nfbShowsFromSeries(await _api.series());

  Future<ReplayTitle?> show(String slug) async => (await _series(slug))?.show;

  Future<List<ReplayTitle>> seasons(String slug) async => [
    for (final entry in (await _series(slug))?.seasons ?? const <NfbSeason>[]) entry.season,
  ];

  Future<ReplayTitle?> season(ReplayRef ref) async {
    final target = parseNfbSeriesId(ref.nativeId);
    if (target == null || target.season == null) return null;
    return (await seasons(target.slug)).where((s) => s.ref == ref).firstOrNull;
  }

  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final target = parseNfbSeriesId(season.nativeId);
    final number = target?.season;
    if (target == null || number == null) return const [];
    final entries = (await _series(target.slug))?.seasons ?? const <NfbSeason>[];
    return entries.where((s) => s.season.seasonNumber == number).firstOrNull?.episodes ?? const [];
  }

  Future<NfbSeries?> _series(String slug) async {
    final hit = _pages[slug];
    if (hit != null && _now().difference(hit.at) < _ttl) return hit.series;
    final html = await _api.seriesPage(slug);
    final series = html == null ? null : nfbParseSeriesPage(html, slug: slug);
    _pages[slug] = (at: _now(), series: series);
    return series;
  }
}
