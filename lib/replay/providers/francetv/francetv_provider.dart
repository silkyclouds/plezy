import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'francetv_api.dart';
import 'francetv_availability.dart';
import 'francetv_catalog.dart';
import 'francetv_categories.dart';
import 'francetv_content.dart';
import 'francetv_images.dart';
import 'francetv_listing.dart';
import 'francetv_mapper.dart';
import 'francetv_playback.dart';
import 'francetv_refs.dart';
import 'francetv_search.dart';

const _titleMemory = 400;

/// France.tv: open catalogue, clear HLS streams, and a rights check that depends on the viewer's country.
///
/// The broadcaster refuses most replays outside France. The country is sent as declared, the refusal is
/// reported as [ReplayAvailability.geoBlocked] with the broadcaster's own message, and nothing is done to
/// avoid the check.
class FranceTvProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: franceTvSourceId,
    name: 'France.tv',
    language: 'fr',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: franceTvListingPageSize,
  );

  final FranceTvApi _api;
  final FranceTvAvailability _availability;
  final DateTime Function() _clock;
  final Map<ReplayRef, ReplayTitle> _seen = {};
  late final FranceTvMapper _mapper = FranceTvMapper(clock: _clock, verdictFor: _availability.known);
  late final FranceTvCatalog _catalog = FranceTvCatalog(_api, _availability, _mapper);
  late final FranceTvListing _listing = FranceTvListing(_api, _mapper);

  /// [countryCode] is the viewer's ISO 3166 alpha-2 country, for example `BE`. It defaults to Belgium until
  /// the app passes the one from the device settings.
  FranceTvProvider(MediaServerHttpClient http, {String countryCode = 'BE'})
    : this.withApi(FranceTvApi(http, countryCode: countryCode));

  /// Test seam: a provider over an API whose responses the caller controls.
  FranceTvProvider.withApi(
    FranceTvApi api, {
    this._clock = DateTime.now,
    Duration batchDelay = const Duration(milliseconds: 250),
  }) : _api = api,
       _availability = FranceTvAvailability(api, batchDelay: batchDelay);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => franceTvCategories;

  @override
  Future<List<ReplayRail>> home() async =>
      _remember(_mapper.rails(await _api.mobile('generic/homepage', platform: 'web')));

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    if (!isFranceTvCategory(categoryId)) return const [];
    final page = await _api.mobile('apps/categories/$categoryId');
    return _remember(_mapper.rails(page, programsBrowseId: categoryId));
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final ids = browseId == replayAllBrowseId ? [for (final c in franceTvCategories) c.id] : [browseId];
    final result = await _listing.page(ids, page);
    _rememberTitles(result.titles);
    return result;
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final page = await _api.mobile('apps/search', query: {'term': trimmed, 'size': '20'});
    return _rememberTitles(franceTvSearchResults(page, trimmed, _mapper));
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    return switch (franceTvTarget(ref)) {
      FranceTvShowTarget(:final programPath) => _catalog.show(programPath),
      FranceTvSeasonTarget(:final showPath) => _season(ref, showPath),
      FranceTvVideoTarget() && final video => _video(video),
      null => null,
    };
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final titles = switch (franceTvTarget(ref)) {
      FranceTvShowTarget(:final programPath) => await _catalog.seasons(programPath),
      final FranceTvSeasonTarget season => await _catalog.episodes(season),
      _ => const <ReplayTitle>[],
    };
    return _rememberTitles(titles);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = franceTvTarget(ref);
    if (target is! FranceTvVideoTarget) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return await _resolve(target.streamId);
    } on FranceTvRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      franceTvImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isFranceTvImage(reference);

  @override
  void close() {}

  /// Asks the broadcaster, records its verdict, then signs the manifest address.
  Future<ReplayPlayback> _resolve(String streamId) async {
    final response = await _api.stream(streamId);
    final info = franceTvParseStream(response.statusCode, response.body);
    if (info.refusal != null) {
      if (info.availability != ReplayAvailability.unknown) _availability.record(streamId, info.availability);
      return info.refusal!;
    }
    _availability.record(streamId, ReplayAvailability.playable);

    final service = info.tokenService;
    final signed = service == null
        ? info.manifest
        : Uri.tryParse(await _api.signedManifest(service, info.manifest!) ?? '');
    if (signed == null || !signed.hasScheme) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    return franceTvPlayable(info, signed);
  }

  Future<ReplayTitle?> _season(ReplayRef ref, String showPath) async {
    final seasons = await _catalog.seasons(showPath);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }

  Future<ReplayTitle?> _video(FranceTvVideoTarget video) async {
    final cached = _seen[franceTvVideoRef(video.streamId, video.contentId)];
    if (cached != null) return cached;
    final contentId = video.contentId;
    if (contentId == null) return null;
    try {
      return franceTvTitleFromContent(await _api.content(contentId), video.streamId, now: _clock());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  List<ReplayRail> _remember(List<ReplayRail> rails) {
    for (final rail in rails) {
      _rememberTitles(rail.titles);
    }
    return rails;
  }

  List<ReplayTitle> _rememberTitles(List<ReplayTitle> titles) {
    for (final title in titles) {
      if (title.kind != ReplayKind.movie && title.kind != ReplayKind.episode) continue;
      if (_seen.length >= _titleMemory) _seen.remove(_seen.keys.first);
      _seen[title.ref] = title;
    }
    return titles;
  }
}
