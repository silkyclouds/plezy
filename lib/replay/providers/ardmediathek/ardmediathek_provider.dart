import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ardmediathek_api.dart';
import 'ardmediathek_catalog.dart';
import 'ardmediathek_categories.dart';
import 'ardmediathek_forecast.dart';
import 'ardmediathek_images.dart';
import 'ardmediathek_item.dart';
import 'ardmediathek_json.dart';
import 'ardmediathek_mapper.dart';
import 'ardmediathek_playback.dart';
import 'ardmediathek_rails.dart';
import 'ardmediathek_refs.dart';

const _listingPageSize = 48;

// The gateway has no "everything" listing. A search for one letter returns nearly every show, which is how the
// catalogue is enumerated.
const _everyShowQuery = 'a';

/// ARD Mediathek: Das Erste, the regional broadcasters and the other ARD channels behind one open gateway.
///
/// Streams are clear HLS and MP4. Many videos are licensed for Germany or the DACH region only; the page of each
/// video says so, and the CDN's refusal is the final word on whether it plays for the viewer.
class ArdMediathekProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: ardMediathekSourceId,
    name: 'ARD Mediathek',
    language: 'de',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: _listingPageSize,
  );

  final ArdMediathekApi _api;
  final DateTime Function() _clock;
  late final ArdMediathekCatalog _catalog = ArdMediathekCatalog(_api, _clock);
  late final ArdMediathekForecast _forecast = ArdMediathekForecast(_api, _clock);

  ArdMediathekProvider(MediaServerHttpClient http) : this.withApi(ArdMediathekApi(http));

  /// Test seam: a provider over an API whose responses the caller controls, with its own clock.
  ArdMediathekProvider.withApi(ArdMediathekApi api, {DateTime Function() clock = DateTime.now}) : this._(api, clock);

  ArdMediathekProvider._(this._api, this._clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => ardCategories;

  @override
  Future<List<ReplayRail>> home() async => ardRailsFromPage(await _api.home());

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId.startsWith(ardChannelPrefix)) {
      return ardRailsFromPage(await _api.home(partner: categoryId.substring(ardChannelPrefix.length)));
    }
    final slug = categoryId.startsWith(ardRubrikPrefix) ? categoryId.substring(ardRubrikPrefix.length) : categoryId;
    return ardRailsFromPage(await _api.editorial(slug));
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final widget = browseId == replayAllBrowseId
        ? await _api.searchShows(_everyShowQuery, page: page, size: _listingPageSize)
        : await _api.widget(browseId, page: page, size: _listingPageSize);
    final total = _total(widget);
    return ReplayPage(titles: ardTitlesFromWidget(widget), totalCount: total);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final (shows, videos) = await (_api.searchShows(trimmed), _api.searchVideos(trimmed)).wait;
    final seen = <ReplayRef>{};
    return [
      for (final title in [...ardTitlesFromWidget(shows), ...ardTitlesFromWidget(videos)])
        if (seen.add(title.ref)) title,
    ];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    try {
      return switch (ardTarget(ref)) {
        ArdItemTarget(:final id) => await _itemTitle(id),
        ArdShowTarget(:final id) => await _catalog.show(id),
        ArdSeasonTarget() => await _catalog.season(ref),
        null => null,
      };
    } on MediaServerHttpException catch (e) {
      if (_isGone(e)) return null;
      rethrow;
    }
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    try {
      return switch (ardTarget(ref)) {
        ArdShowTarget(:final id) => await _catalog.seasons(id),
        ArdSeasonTarget() => await _catalog.episodes(ref),
        _ => const [],
      };
    } on MediaServerHttpException catch (e) {
      if (_isGone(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = ardTarget(ref);
    if (target is! ArdItemTarget) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final facts = ardReadItem(await _api.item(target.id), now: _clock());
      if (!facts.isPlayable) return ReplayPlayback.unavailable(facts.availability);
      // The flag can be wrong for a single video, so the CDN has the last word on a flagged one.
      if (facts.geoFlagged && ardStatusRefusesCountry(await _api.streamStatus(facts.main!))) {
        return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked);
      }
      return ardBuildPlayback(facts);
    } on ArdMediathekRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (_isGone(e)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _forecast.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => ardImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isArdImage(reference);

  @override
  void close() {}

  Future<ReplayTitle?> _itemTitle(String id) async {
    final page = await _api.item(id);
    return ardTitleFromItemPage(page, id, ardReadItem(page, now: _clock()), now: _clock());
  }

  int _total(Map<String, dynamic> widget) =>
      ardInt(ardMap(widget['pagination'])?['totalElements']) ?? ardTitlesFromWidget(widget).length;

  bool _isGone(MediaServerHttpException e) => e.statusCode == 404 || e.statusCode == 410;
}
