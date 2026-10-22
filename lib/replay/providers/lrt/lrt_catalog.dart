import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'lrt_api.dart';
import 'lrt_feed.dart';
import 'lrt_mapper.dart';
import 'lrt_models.dart';
import 'lrt_numbering.dart';
import 'lrt_refs.dart';

/// Resolves the programme -> season -> recording structure.
///
/// A programme is its slug, a season is `slug/year`, and a programme without seasons has the single season
/// `slug/_all`. Recordings of a season come from its RSS feed, which holds the newest [lrtFeedLimit].
class LrtCatalog {
  final LrtApi _api;

  LrtCatalog(this._api);

  Future<ReplayTitle?> show(String slug) async {
    final page = await _api.showPage(slug);
    return page == null ? null : lrtShowTitle(page);
  }

  Future<List<ReplayTitle>> seasons(String slug) async {
    final page = await _api.showPage(slug);
    return page == null ? const [] : lrtSeasonTitles(page);
  }

  Future<ReplayTitle?> season(ReplayRef ref) async {
    final parts = lrtSplitSeasonId(ref.nativeId);
    if (parts == null) return null;
    final seasons = await this.seasons(parts.show);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }

  /// A recording with its programme and season, from its metadata record.
  Future<ReplayTitle?> recording(String postId) async {
    final recording = await _api.article(postId);
    return recording == null ? null : lrtRecordingTitle(recording);
  }

  /// The recordings of a season, oldest first, each numbered where the title or the dates allow.
  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final parts = lrtSplitSeasonId(seasonRef.nativeId);
    if (parts == null) return const [];
    final page = await _api.showPage(parts.show);
    final all = parts.season == lrtAllVideosSeason;
    final feed = await _api.feed(all ? '/video/${parts.show}' : '/video/${parts.show}/${parts.season}');
    if (feed.isEmpty) return const [];

    final seasonTitles = page == null ? const <ReplayTitle>[] : lrtSeasonTitles(page);
    final seasonNumber = seasonTitles.where((s) => s.ref == seasonRef).firstOrNull?.seasonNumber ?? (all ? 1 : null);
    final context = LrtContext(
      show: lrtShowRef(parts.show),
      showTitle: page?.title ?? feed.first.showTitle,
      season: seasonRef,
      seasonNumber: seasonNumber,
    );
    final durations = {for (final r in page?.episodes ?? const <LrtRecording>[]) r.postId: r.durationSeconds};
    final complete = feed.length < lrtFeedLimit || (page?.episodeTotal ?? lrtFeedLimit + 1) <= feed.length;
    return [
      for (final (:recording, :number) in lrtNumberRecordings(feed, complete: complete))
        lrtRecordingTitle(recording.withDuration(durations[recording.postId]), context: context, episodeNumber: number),
    ];
  }

  /// A page of the A to Z programme index.
  Future<ReplayPage> programmes(int page, int size) async {
    final all = await _api.programmeIndex();
    final from = page * size;
    if (from >= all.length) return ReplayPage(titles: const [], totalCount: all.length);
    return ReplayPage(
      titles: [for (final p in all.skip(from).take(size)) lrtProgrammeTitle(p)],
      totalCount: all.length,
    );
  }
}
