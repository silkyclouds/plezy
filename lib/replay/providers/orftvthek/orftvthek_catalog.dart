import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'orftvthek_api.dart';
import 'orftvthek_episodes.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_images.dart';
import 'orftvthek_mapper.dart';
import 'orftvthek_numbering.dart';
import 'orftvthek_profiles.dart';
import 'orftvthek_seasons.dart';

/// Resolves the show -> season -> episode structure that ORF only implies.
///
/// A show is one profile, or the profiles named `<show> Staffel <n>` together. A numbered profile is one season; any
/// other profile is split by [orfPlanSeasons]. The episodes of a season are numbered by [orfNumberEpisodes].
class OrfCatalog {
  final OrfApi _api;
  final OrfProfileIndex _index;
  final OrfEpisodeLoader _episodes;
  final OrfMapper _mapper;

  OrfCatalog(this._api, this._index, this._episodes, this._mapper);

  Future<ReplayTitle?> show(ReplayRef ref) async {
    final group = await _group(parseOrfRef(ref));
    return group == null ? null : _mapper.groupShow(group);
  }

  Future<List<ReplayTitle>> seasons(ReplayRef showRef) async {
    final group = await _group(parseOrfRef(showRef));
    return group == null ? const [] : _seasonsOf(group);
  }

  Future<ReplayTitle?> season(ReplayRef ref) async {
    final target = parseOrfRef(ref);
    final group = target is OrfSeasonTarget ? await _group(target) : null;
    if (group == null) return null;
    return (await _seasonsOf(group)).where((s) => s.ref == ref).firstOrNull;
  }

  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final target = parseOrfRef(seasonRef);
    if (target is! OrfSeasonTarget) return const [];
    final group = await _group(target);
    final profile = group?.profileById(target.profileId);
    if (group == null || profile == null) return const [];

    final all = await _episodes.all(profile.id);
    final plan = orfPlanSeasons(all, profileSeason: profile.season).where((p) => p.key == target.key).firstOrNull;
    if (plan == null) return const [];
    return [
      for (final (:episode, :number) in orfNumberEpisodes(plan.episodes))
        ?_mapper.episode(
          episode,
          context: OrfEpisodeContext(
            showRef: group.ref,
            showTitle: group.title,
            seasonRef: seasonRef,
            seasonNumber: plan.number,
            episodeNumber: number,
            trimTitle: true,
          ),
        ),
    ];
  }

  /// A programme page, or null when ORF no longer has it.
  Future<ReplayTitle?> episode(int id) async {
    try {
      return _mapper.episode(await _api.episode(id));
    } on MediaServerHttpException catch (e) {
      if (orfIsNotFound(e)) return null;
      rethrow;
    }
  }

  Future<ReplayTitle?> clip(int id) async {
    try {
      return _mapper.clip(await _api.segment(id));
    } on MediaServerHttpException catch (e) {
      if (orfIsNotFound(e)) return null;
      rethrow;
    }
  }

  Future<OrfShowGroup?> _group(OrfTarget? target) async {
    final profileId = switch (target) {
      OrfProfileTarget(:final id) => id,
      OrfSeasonTarget(:final profileId) => profileId,
      _ => null,
    };
    if (target is OrfSeriesTarget) return _index.byRef(orfSeriesRef(target.key));
    if (profileId == null) return null;
    return await _index.byProfileId(profileId) ?? _loneProfile(profileId);
  }

  /// A profile the index does not list (hidden from the A-Z list) is still a show of its own.
  Future<OrfShowGroup?> _loneProfile(int id) async {
    try {
      final profile = await _api.profile(id);
      final title = _mapper.profileShow(profile);
      if (title == null) return null;
      return OrfShowGroup(title.ref, title.title, [OrfProfile.fromJson(profile, id: id)]);
    } on MediaServerHttpException catch (e) {
      if (orfIsNotFound(e)) return null;
      rethrow;
    }
  }

  Future<List<ReplayTitle>> _seasonsOf(OrfShowGroup group) async {
    final show = _mapper.groupShow(group);
    if (group.isSeries) return [for (final profile in group.profiles) _numberedSeason(show, profile)];

    final profile = group.profiles.single;
    final plans = orfPlanSeasons(await _episodes.all(profile.id));
    return [
      for (final plan in plans)
        ReplayTitle(
          ref: orfSeasonRef(profile.id, plan.key),
          kind: ReplayKind.season,
          title: plan.title,
          posterUrl: show.posterUrl,
          backdropUrl: show.backdropUrl,
          seasonNumber: plan.number,
          childCount: plan.episodes.length,
          showRef: show.ref,
          showTitle: show.title,
        ),
    ];
  }

  ReplayTitle _numberedSeason(ReplayTitle show, OrfProfile profile) {
    final number = profile.season!;
    final art = orfArtwork(profile.profile);
    return ReplayTitle(
      ref: orfSeasonRef(profile.id, orfNumberedSeasonKey(number)),
      kind: ReplayKind.season,
      title: 'Staffel $number',
      posterUrl: art.poster ?? show.posterUrl,
      backdropUrl: art.backdrop ?? show.backdropUrl,
      seasonNumber: number,
      childCount: profile.episodeCount,
      showRef: show.ref,
      showTitle: show.title,
    );
  }
}
