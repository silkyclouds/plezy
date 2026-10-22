import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'lrt_api.dart';
import 'lrt_catalog.dart';
import 'lrt_categories.dart';
import 'lrt_forecast.dart';
import 'lrt_images.dart';
import 'lrt_mapper.dart';
import 'lrt_models.dart';
import 'lrt_playback.dart';
import 'lrt_refs.dart';
import 'lrt_search.dart';

/// LRT (Lithuania): clear HLS for nearly every recording, in Lithuanian only. A few recordings are licensed for
/// Lithuania and answer with a placeholder clip elsewhere, which this provider reports as geoblocked.
class LrtProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: lrtSourceId,
    name: 'LRT',
    language: 'lt',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 30,
  );

  static const _railLimit = 40;

  final LrtApi _api;
  final LrtCatalog _catalog;
  final LrtForecast _forecast;

  LrtProvider(MediaServerHttpClient http) : this._(LrtApi(http));

  LrtProvider._(this._api) : _catalog = LrtCatalog(_api), _forecast = LrtForecast(_api);

  /// Test seam: a provider over an API whose responses the caller controls.
  LrtProvider.withApi(LrtApi api) : this._(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => lrtCategories();

  @override
  Future<List<ReplayRail>> home() async {
    final rails = <ReplayRail>[];
    for (final section in [for (final id in lrtHomeSectionIds) lrtSectionById(id)!, lrtNewsRow]) {
      final rail = await _rail(section, optional: rails.isNotEmpty);
      if (rail != null) rails.add(rail);
    }
    return rails;
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final section = lrtSectionById(categoryId);
    if (section == null) return const [];
    final rail = await _rail(section, optional: false, limit: null);
    return rail == null ? const [] : [rail];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == replayAllBrowseId) return _catalog.programmes(page, _source.listingPageSize);
    final section = lrtSectionById(browseId);
    if (section == null) return const ReplayPage(titles: [], totalCount: 0);
    final titles = lrtRowTitles(await _api.feed(section.path), kind: section.kind);
    final size = _source.listingPageSize;
    return ReplayPage(titles: titles.skip(page * size).take(size).toList(), totalCount: titles.length);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final first = await _api.search(trimmed);
    final pages = [first];
    if (first.total > lrtSearchPageSize) pages.add(await _api.search(trimmed, page: 2));
    final seen = <ReplayRef>{};
    final titles = <ReplayTitle>[
      for (final p in first.programmes) lrtProgrammeTitle(p),
      for (final page in pages)
        for (final r in page.recordings) lrtRecordingTitle(r),
    ];
    return [
      for (final t in titles)
        if (seen.add(t.ref)) t,
    ];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) {
    final id = ref.nativeId;
    return switch (lrtRefKind(id)) {
      LrtRefKind.recording => _catalog.recording(lrtPostIdOfNative(id)!),
      LrtRefKind.season => _catalog.season(ref),
      LrtRefKind.show => _catalog.show(id),
    };
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) {
    final id = ref.nativeId;
    return switch (lrtRefKind(id)) {
      LrtRefKind.recording => Future.value(const []),
      LrtRefKind.season => _catalog.episodes(ref),
      LrtRefKind.show => _catalog.seasons(id),
    };
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final postId = lrtPostIdOfNative(ref.nativeId);
    if (postId == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final info = await _api.mediaInfo(postId);
      if (info == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      final target = parseLrtMediaInfo(info);
      final stream = target.stream;
      if (stream == null) return target.refusal!;
      return lrtPlaybackFromProbe(stream, lrtIsPlaylist(stream) ? await _api.probeManifest(stream) : null);
    } on LrtRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _forecast.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => lrtImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isLrtImage(reference);

  @override
  void close() {}

  /// A row of a section feed. Secondary rows are skipped when the site fails them, so one broken feed does not
  /// empty the landing page.
  Future<ReplayRail?> _rail(LrtSection section, {required bool optional, int? limit = _railLimit}) async {
    final List<LrtRecording> recordings;
    try {
      recordings = await _api.feed(section.path);
    } on MediaServerHttpException {
      if (optional) return null;
      rethrow;
    }
    final titles = lrtRowTitles(recordings, kind: section.kind, limit: limit);
    if (titles.isEmpty) return null;
    return ReplayRail(
      id: section.id,
      title: section.title,
      titles: titles,
      moreBrowseId: lrtSectionById(section.id) == null ? null : section.id,
    );
  }
}
