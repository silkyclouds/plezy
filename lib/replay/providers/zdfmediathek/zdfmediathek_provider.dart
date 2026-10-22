import 'dart:math';

import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'zdfmediathek_api.dart';
import 'zdfmediathek_catalog.dart';
import 'zdfmediathek_geo.dart';
import 'zdfmediathek_images.dart';
import 'zdfmediathek_mapper.dart';
import 'zdfmediathek_playback.dart';
import 'zdfmediathek_rails.dart';

/// ZDFmediathek: clear HLS for the open part of the catalogue, with each video flagged for the countries it is cleared in.
class ZdfMediathekProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: zdfmediathekSourceId,
    name: 'ZDFmediathek',
    language: 'de',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 30,
  );
  static const _searchPages = 2;
  static const _maxFlagLookups = 12;

  final ZdfApi _api;
  final ZdfGeoLedger _geo;
  final ZdfMapper _mapper;
  final ZdfCatalog _catalog;
  final DateTime Function() _now;

  ZdfMediathekProvider(MediaServerHttpClient http) : this.withApi(ZdfApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  ZdfMediathekProvider.withApi(ZdfApi api, {DateTime Function()? clock})
    : this._(api, ZdfGeoLedger(), clock ?? DateTime.now);

  ZdfMediathekProvider._(ZdfApi api, ZdfGeoLedger geo, DateTime Function() now)
    : this._assembled(api, geo, ZdfMapper(geo, clock: now), now);

  ZdfMediathekProvider._assembled(this._api, this._geo, this._mapper, this._now) : _catalog = ZdfCatalog(_api, _mapper);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => zdfCategories(await _api.categoriesOverview());

  @override
  Future<List<ReplayRail>> home() async => zdfRails(_mapper, await _api.startPage());

  @override
  Future<List<ReplayRail>> category(String categoryId) async => zdfRails(_mapper, await _api.document(categoryId));

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final titles = browseId == replayAllBrowseId
        ? zdfAlphabeticalShows(_mapper, await _api.brandsAlphabetical())
        : await _categoryTitles(browseId);
    final size = _source.listingPageSize;
    final from = min(page * size, titles.length);
    return ReplayPage(titles: titles.sublist(from, min(from + size, titles.length)), totalCount: titles.length);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final raw = <Object?>[];
    Map<String, dynamic>? page = await _api.search(trimmed);
    for (var fetched = 1; page != null; fetched++) {
      raw.addAll(page['results'] as List? ?? const []);
      final next = page['nextPage'] == true ? page['nextPageUrl'] : null;
      page = next is String && fetched < _searchPages ? await _api.nextSearchPage(next) : null;
    }
    final titles = zdfTitles(_mapper, raw);
    return [
      for (final title in titles)
        if (title.kind == ReplayKind.show) title,
      for (final title in titles)
        if (title.kind != ReplayKind.show) title,
    ];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (id.contains('/')) return _seasonTitle(ref);
    final page = await _documentOrNull(id);
    final document = page?['document'];
    if (page == null || document is! Map<String, dynamic>) return null;
    return switch (document['type']) {
      'brand' || 'topic' => _mapper.showFromPage(page),
      'video' => _videoTitle(document),
      _ => null,
    };
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = ref.nativeId;
    final cut = id.indexOf('/');
    final tree = await _treeOrNull(cut < 0 ? id : id.substring(0, cut));
    if (tree == null) return const [];
    return cut < 0 ? tree.seasons : tree.episodes[ref] ?? const [];
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    if (ref.nativeId.contains('/')) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final page = await _api.freshDocument(ref.nativeId);
      return await _checkCountry(page, zdfParsePlayback(page, now: _now()));
    } on ZdfRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (_isGone(e.statusCode)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async {
    final videos = [
      for (final title in titles)
        if (title.isPlayable && title.ref.source == zdfmediathekSourceId) title.ref,
    ];
    await _learnFlags(
      [
        for (final ref in videos)
          if (_geo.flagOf(ref) == null) ref,
      ].take(_maxFlagLookups),
    );
    return {
      for (final ref in videos)
        if (zdfBlockedIn(_geo.flagOf(ref), country)) ref: ReplayAvailability.geoBlocked,
    };
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => zdfImageUrl(reference, width: width);

  @override
  bool ownsImage(String reference) => isZdfImage(reference);

  @override
  void close() {}

  Future<List<ReplayTitle>> _categoryTitles(String categoryId) async {
    final rails = zdfRails(_mapper, await _api.document(categoryId));
    final seen = <ReplayRef>{};
    return [
      for (final rail in rails)
        for (final title in rail.titles)
          if (seen.add(title.ref)) title,
    ];
  }

  Future<ReplayTitle?> _seasonTitle(ReplayRef ref) async {
    final tree = await _treeOrNull(ref.nativeId.substring(0, ref.nativeId.indexOf('/')));
    return tree?.seasons.where((s) => s.ref == ref).firstOrNull;
  }

  /// A video page lacks what the show's listing knows (the season it sits in, derived numbers), so the listing fills
  /// the gaps when the show can be read.
  Future<ReplayTitle?> _videoTitle(Map<String, dynamic> document) async {
    final video = _mapper.title(document);
    final showId = video?.showRef?.nativeId;
    if (video == null || showId == null) return video;
    final listed = (await _treeOrNull(showId))?.episode(video.ref);
    return listed == null ? video : video.filledFrom(listed);
  }

  Future<Map<String, dynamic>?> _documentOrNull(String id) async {
    try {
      return await _api.document(id);
    } on MediaServerHttpException catch (e) {
      if (_isGone(e.statusCode)) return null;
      rethrow;
    }
  }

  Future<ZdfShowTree?> _treeOrNull(String showId) async {
    try {
      return await _catalog.tree(showId);
    } on MediaServerHttpException catch (e) {
      if (_isGone(e.statusCode)) return null;
      rethrow;
    }
  }

  /// A video outside its country flag has full metadata but a stream the CDN refuses, so the stream is asked for its
  /// first bytes. Videos cleared worldwide skip the check.
  Future<ReplayPlayback> _checkCountry(Map<String, dynamic> page, ReplayPlayback playback) async {
    final flag = zdfGeoFlag(page);
    if (!playback.isPlayable || flag == null || flag == 'none') return playback;
    final status = await _api.streamStatus(playback.streams.first.url);
    if (status == 403) {
      return ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: zdfAvailabilityNote(page));
    }
    if (_isGone(status)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    return playback;
  }

  Future<void> _learnFlags(Iterable<ReplayRef> refs) => Future.wait([for (final ref in refs) _learnFlag(ref)]);

  Future<void> _learnFlag(ReplayRef ref) async {
    try {
      final page = await _api.document(ref.nativeId);
      _geo.record(ref, (page['document'] as Map?)?['geoLocation']);
    } on MediaServerHttpException {
      return; // A title ZDF cannot be asked about stays unjudged: nothing is greyed out on a guess.
    } on ZdfRateLimitedException {
      return;
    }
  }

  bool _isGone(int? status) => status == 404 || status == 410;
}
