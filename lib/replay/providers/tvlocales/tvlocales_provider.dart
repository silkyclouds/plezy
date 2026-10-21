import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'drupal/drupal_site.dart';
import 'freecaster_player.dart';
import 'tvlocales_api.dart';
import 'tvlocales_catalog.dart';
import 'tvlocales_ids.dart';
import 'tvlocales_images.dart';
import 'tvlocales_site.dart';
import 'tvlocales_station.dart';
import 'tvlux/tvlux_site.dart';

const _showsBrowseId = 'emissions';

/// A Belgian local television on the Freecaster platform. The channel classes only name their station.
class TvLocalesProvider implements ReplayProvider {
  final TvLocalesStation station;
  final TvLocalesCatalog _catalog;
  final FreecasterResolver _freecaster;
  final ReplaySource _source;

  TvLocalesProvider(TvLocalesStation station, TvLocalesApi api) : this._(station, api, FreecasterResolver(api));

  TvLocalesProvider._(this.station, TvLocalesApi api, this._freecaster)
    : _catalog = TvLocalesCatalog(station, _siteFor(station, api), _freecaster),
      _source = ReplaySource(id: station.id, name: station.name, language: 'fr', support: ReplayPlaybackSupport.clear);

  static TvLocalesSite _siteFor(TvLocalesStation station, TvLocalesApi api) => switch (station.kind) {
    TvLocalesSiteKind.drupal => DrupalSite(api, station.base),
    TvLocalesSiteKind.tvlux => TvLuxSite(api, station.base),
  };

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => const [ReplayCategory(id: _showsBrowseId, title: 'Émissions')];

  @override
  Future<List<ReplayRail>> home() async {
    final latest = await _catalog.latest();
    return [?latest, ...await _showsRail()];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) =>
      categoryId == _showsBrowseId ? _showsRail() : Future.value(const []);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId != replayAllBrowseId && browseId != _showsBrowseId) return const ReplayPage(titles: [], totalCount: 0);
    final shows = await _catalog.shows();
    final size = _source.listingPageSize;
    return ReplayPage(titles: shows.skip(page * size).take(size).toList(), totalCount: shows.length);
  }

  @override
  Future<List<ReplayTitle>> search(String query) => _catalog.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = TvLocalesId.tryParse(ref.nativeId);
    if (id == null) return null;
    if (id.isEpisode) return _catalog.episode(id);
    return id.isSeason ? _catalog.season(id) : _catalog.show(id.showSlug);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = TvLocalesId.tryParse(ref.nativeId);
    if (id == null || id.isEpisode) return const [];
    return id.isSeason ? _catalog.episodes(id) : _catalog.seasons(id.showSlug);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = TvLocalesId.tryParse(ref.nativeId);
    if (id == null || !id.isEpisode) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final page = await _catalog.episodePage(id);
      if (page == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      final videoId = page.videoId;
      if (videoId == null) {
        return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'Cet article n’a pas de vidéo.');
      }
      return await _freecaster.playback(videoId);
    } on TvLocalesRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => tvLocalesImageUrl(reference, width: width);

  @override
  bool ownsImage(String reference) => ownsTvLocalesImage(station, reference);

  @override
  void close() {}

  Future<List<ReplayRail>> _showsRail() async {
    final shows = await _catalog.shows();
    return shows.isEmpty ? const [] : [ReplayRail(id: _showsBrowseId, title: 'Émissions', titles: shows)];
  }
}
