import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'urplay_api.dart';
import 'urplay_availability.dart';
import 'urplay_browse.dart';
import 'urplay_catalog.dart';
import 'urplay_categories.dart';
import 'urplay_images.dart';
import 'urplay_mapper.dart';
import 'urplay_playback.dart';
import 'urplay_refs.dart';

/// UR Play: Sweden's educational broadcaster, clear HLS for the programmes it may show outside Sweden.
class UrPlayProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: urplaySourceId,
    name: 'UR Play',
    language: 'sv',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: urPageSize,
  );

  final UrPlayApi _api;
  final UrCatalog _catalog;
  final UrBrowse _browse;
  final UrAvailabilityProbe _probe;

  UrPlayProvider(MediaServerHttpClient http) : this.withApi(UrPlayApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  UrPlayProvider.withApi(UrPlayApi api, {UrAvailabilityProbe? probe}) : this._(api, UrCatalog(api), probe);

  UrPlayProvider._(this._api, this._catalog, UrAvailabilityProbe? probe)
    : _browse = UrBrowse(_api),
      _probe = probe ?? UrAvailabilityProbe(_api, _catalog);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => urCategories;

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) => _browse.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async => switch (UrTarget.parse(ref)) {
    UrShow(:final seriesId) => _catalog.show(seriesId),
    UrSeason(:final showId, :final seriesId) => _catalog.season(showId, seriesId),
    UrProgram(:final programId) => _programTitle(programId),
    null => null,
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async => switch (UrTarget.parse(ref)) {
    UrShow(:final seriesId) => _catalog.seasons(seriesId),
    UrSeason(:final showId, :final seriesId) => _catalog.episodes(showId, seriesId),
    _ => const [],
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = UrTarget.parse(ref);
    if (target is! UrProgram) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final reply = await _api.sources(target.programId);
      return await urParsePlayback(reply, _readMaster);
    } on UrPlayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _probe.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => urImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isUrImage(reference);

  @override
  void close() {}

  /// A playlist that cannot be read does not make a title unplayable: the stream URL is still handed to the player.
  Future<String?> _readMaster(Uri master) async {
    try {
      return await _api.playlist(master);
    } on MediaServerHttpException {
      return null;
    }
  }

  Future<ReplayTitle?> _programTitle(String programId) async {
    final info = await _api.episodeInfo(programId);
    if (info == null) return null;
    final seriesId = (info['about'] as Map?)?['seriesId']?.toString();
    final showTitle = urSeriesTitleOfInfo(info);
    if (seriesId == null || showTitle == null) return urTitleFromEpisodeInfo(info);

    final lineage = await _lineage(seriesId, showTitle);
    return urTitleFromEpisodeInfo(
      info,
      context: UrContext(
        show: lineage.show,
        showTitle: showTitle,
        season: lineage.season,
        seasonNumber: lineage.seasonNumber,
      ),
    );
  }

  /// Without the search that finds sibling seasons, a programme still points at its own series.
  Future<UrLineage> _lineage(String seriesId, String showTitle) async {
    try {
      return await _catalog.lineage(seriesId, showTitle);
    } on MediaServerHttpException {
      return UrLineage(urplayShowRef(seriesId), urplaySeasonRef(seriesId, seriesId), null);
    }
  }
}
