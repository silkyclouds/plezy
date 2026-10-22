import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'orftvthek_geo.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_images.dart';
import 'orftvthek_json.dart';
import 'orftvthek_numbering.dart';
import 'orftvthek_profiles.dart';
import 'orftvthek_shows.dart';
import 'orftvthek_text.dart';

const _filmGenreId = 2703833;
final _seasonText = RegExp(r'\b(?:Staffel|Periode|Season)\s+\d+\b', caseSensitive: false);

/// Where an episode sits in its show, when the caller knows.
class OrfEpisodeContext {
  final ReplayRef? showRef;
  final String? showTitle;
  final ReplayRef? seasonRef;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Drop the show name from the title, as a season page does.
  final bool trimTitle;

  const OrfEpisodeContext({
    this.showRef,
    this.showTitle,
    this.seasonRef,
    this.seasonNumber,
    this.episodeNumber,
    this.trimTitle = false,
  });

  /// The show an item names for itself (`profile_title` and its profile link), if it does.
  factory OrfEpisodeContext.fromItem(Map<String, dynamic> item) {
    final profileId = orfIdFromLink(orfMap(item['_links'])?['profile']);
    final profileTitle = orfString(item['profile_title']);
    if (profileId == null || profileTitle == null) return const OrfEpisodeContext();
    final identity = OrfShowIdentity.of(profileId, profileTitle);
    final season = identity.season;
    return OrfEpisodeContext(
      showRef: identity.ref,
      showTitle: identity.title,
      seasonRef: season == null ? null : orfSeasonRef(profileId, orfNumberedSeasonKey(season)),
      seasonNumber: season,
    );
  }
}

/// Turns ORF list and detail objects into neutral titles, and notes which of them are Austria-only.
class OrfMapper {
  final DateTime Function() _now;
  final OrfGeoMemory _geo;

  const OrfMapper(this._now, this._geo);

  /// A programme from an episode list or an episode page, or null when it has no id or title.
  ReplayTitle? episode(Map<String, dynamic> item, {OrfEpisodeContext? context}) {
    final id = orfInt(item['id']);
    if (id == null) return null;
    final known = context ?? OrfEpisodeContext.fromItem(item);
    final stated = orfTitleMarkers(orfString(item['title']) ?? '').episode;
    final film = orfInt(item['genre_id']) == _filmGenreId && known.seasonNumber == null && stated == null;
    return _title(
      item,
      ref: orfEpisodeRef(id),
      kind: film ? ReplayKind.movie : ReplayKind.episode,
      context: known,
      statedEpisode: stated,
    );
  }

  /// An item of a lane or of search results. These carry either a whole programme or a chapter cut from one: a
  /// chapter that has its programme's title is the programme itself.
  ReplayTitle? listed(Map<String, dynamic> item) {
    final programmeId = orfInt(item['episode_id']);
    if (item['video_type'] != 'segment' || programmeId == null) return episode(item);
    final title = orfString(item['title']);
    final programmeTitle = orfString(item['episode_title']);
    if (title == null) return null;
    if (programmeTitle == null || title == programmeTitle) {
      return episode({...item, 'id': programmeId, 'date': item['episode_date']});
    }
    return clip(item);
  }

  /// A chapter cut from a programme.
  ReplayTitle? clip(Map<String, dynamic> item) {
    final id = orfInt(item['id']);
    if (id == null) return null;
    final dated = {...item, 'date': item['episode_date'] ?? item['date']};
    return _title(dated, ref: orfSegmentRef(id), kind: ReplayKind.clip, context: const OrfEpisodeContext());
  }

  /// A show from a profile object, or null for sign-language, audio-description and empty profiles.
  ReplayTitle? profileShow(Map<String, dynamic> profile) {
    final id = orfInt(profile['id']);
    final title = orfString(profile['title']) ?? orfString(profile['headline']);
    if (id == null || title == null || !orfIsListedProfile(profile)) return null;
    final identity = OrfShowIdentity.of(id, title);
    return _show(identity.ref, identity.title, profile, childCount: null);
  }

  /// A show from the index, which knows how many seasons a series has.
  ReplayTitle groupShow(OrfShowGroup group) {
    final newest = group.newest;
    return _show(group.ref, group.title, newest.profile, childCount: group.isSeries ? group.profiles.length : null);
  }

  ReplayTitle _show(ReplayRef ref, String title, Map<String, dynamic> profile, {required int? childCount}) {
    final art = orfArtwork(profile);
    return ReplayTitle(
      ref: ref,
      kind: ReplayKind.show,
      title: title,
      summary: orfString(profile['description']),
      posterUrl: art.poster,
      backdropUrl: art.backdrop,
      childCount: childCount,
    );
  }

  ReplayTitle? _title(
    Map<String, dynamic> item, {
    required ReplayRef ref,
    required ReplayKind kind,
    required OrfEpisodeContext context,
    int? statedEpisode,
  }) {
    final raw = orfString(item['title']) ?? orfString(item['headline']);
    if (raw == null) return null;
    final right = orfString(item['right']);
    if (right != null) _geo.remember(ref, austriaOnly: right != 'worldwide');
    final art = orfArtwork(item);
    final showTitle = context.showTitle;
    final genre = orfString(item['genre_title']);
    return ReplayTitle(
      ref: ref,
      kind: kind,
      title: context.trimTitle && showTitle != null ? orfTrimEpisodeTitle(raw, showTitle) : raw,
      subtitle: _subtitle(item, raw, showTitle),
      summary: orfSummary(item),
      posterUrl: art.poster,
      backdropUrl: art.backdrop,
      durationSeconds: orfInt(item['duration_seconds']),
      year: orfInt(item['production_year']),
      genres: genre == null ? const [] : [genre],
      contentRating: orfString(item['age_classification']),
      airDate: orfDate(item['date']),
      availableUntil: orfDate(item['killdate']),
      availability: _availability(item),
      seasonNumber: context.seasonNumber,
      episodeNumber: context.episodeNumber ?? statedEpisode,
      showRef: context.showRef,
      showTitle: showTitle,
      seasonRef: context.seasonRef,
    );
  }

  /// The editorial blurb, unless it only repeats the show name, a season label or the title.
  String? _subtitle(Map<String, dynamic> item, String title, String? showTitle) {
    final blurb = orfString(item['sub_headline']);
    if (blurb == null || _seasonText.hasMatch(blurb)) return null;
    final repeated = {title, showTitle, orfString(item['profile_title'])}.whereType<String>();
    return repeated.any((s) => s.toLowerCase() == blurb.toLowerCase()) ? null : blurb;
  }

  ReplayAvailability _availability(Map<String, dynamic> item) {
    if (item['is_drm_protected'] == true) return ReplayAvailability.drmProtected;
    final now = _now();
    final until = orfDate(item['killdate']);
    if (until != null && !until.isAfter(now)) return ReplayAvailability.expired;
    final from = orfDate(item['livedate']);
    if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
    return ReplayAvailability.playable;
  }
}
