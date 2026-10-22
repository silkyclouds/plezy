import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'srg_api.dart';
import 'srg_catalog.dart';
import 'srg_geo.dart';
import 'srg_ids.dart';
import 'srg_mapper.dart';
import 'srg_playback.dart';
import 'srg_shows.dart';
import 'srg_unit.dart';

/// A Swiss public broadcaster on the SRG Integration Layer: clear HLS for the part of the catalogue that is
/// licensed outside Switzerland.
///
/// One business unit's worth of behaviour; the unit decides the wording, numbering labels and artwork host.
/// A subclass that also declares `ReplayAvailabilityPredictor` gets the forecast from [predictAvailability].
class SrgProvider implements ReplayProvider {
  final SrgUnit _unit;
  final SrgApi _api;
  final SrgGeoMemory _geo;
  final SrgMapper _mapper;
  final SrgCatalog _catalog;
  final SrgShows _shows;
  final ReplaySource _source;

  SrgProvider(SrgUnit unit, SrgApi api) : this._(unit, api, SrgGeoMemory());

  SrgProvider._(SrgUnit unit, SrgApi api, SrgGeoMemory geo) : this._wired(unit, api, geo, SrgMapper(unit, geo: geo));

  SrgProvider._wired(SrgUnit unit, SrgApi api, SrgGeoMemory geo, SrgMapper mapper)
    : _unit = unit,
      _api = api,
      _geo = geo,
      _mapper = mapper,
      _catalog = SrgCatalog(unit, api, mapper),
      _shows = SrgShows(unit, api, mapper),
      _source = ReplaySource(
        id: unit.sourceId,
        name: unit.name,
        language: unit.language,
        support: ReplayPlaybackSupport.clear,
        listingPageSize: 100,
      );

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() => _catalog.categories();

  @override
  Future<List<ReplayRail>> home() => _catalog.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _catalog.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _catalog.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _catalog.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    switch (SrgId.tryParse(ref.nativeId)) {
      case SrgShowId(:final showId):
        return _shows.show(showId);
      case final SrgSeasonId id:
        return (await _shows.seasons(id.showId)).where((s) => s.ref == ref).firstOrNull;
      case SrgVideoId(:final videoId):
        final composition = await _api.mediaComposition(videoId);
        return composition == null ? null : _mapper.fromComposition(composition);
      case null:
        return null;
    }
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    return switch (SrgId.tryParse(ref.nativeId)) {
      SrgShowId(:final showId) => _shows.seasons(showId),
      final SrgSeasonId id => _shows.episodes(id),
      _ => const [],
    };
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = SrgId.tryParse(ref.nativeId);
    if (id is! SrgVideoId) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final composition = await _api.mediaComposition(id.videoId);
      if (composition == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      return srgParsePlayback(_unit, composition);
    } on SrgRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  /// Titles the catalogue flagged as Swiss-only, for a viewer outside Switzerland. Titles never seen are left out.
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async => {
    for (final title in titles) title.ref: ?_geo.verdict(title.ref, country),
  };

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      _unit.images.url(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => _unit.images.owns(reference);

  @override
  void close() {}
}
