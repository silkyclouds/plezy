import '../../model/replay_title.dart';
import 'stvplayer_access.dart';
import 'stvplayer_images.dart';
import 'stvplayer_numbering.dart';
import 'stvplayer_refs.dart';

/// Turns STV Player catalogue objects into neutral titles and notes each episode's UK allow list on the way.
class StvPlayerMapper {
  final StvPlayerRestrictions _restrictions;
  final DateTime Function() _now;

  StvPlayerMapper(this._restrictions, this._now);

  /// A programme as a show. A programme with no series still shows one season, made up by the catalogue module.
  ReplayTitle show(Map<String, dynamic> programme) {
    final guid = programme['guid'] as String;
    final series = programme['series'];
    final poster = stvPlayerImageReference(programme['images'], anyImage: true);
    return ReplayTitle(
      ref: stvShowRef(guid),
      kind: ReplayKind.show,
      title: _text(programme['name']) ?? guid,
      summary: _text(programme['longDescription']) ?? _text(programme['shortDescription']),
      posterUrl: poster,
      backdropUrl: poster,
      logoUrl: stvPlayerImageReference(programme['images'], type: 'titleImage'),
      genres: _genres(programme['genre']),
      availability: stvPlayerAvailability(programme, _now()),
      childCount: series is List && series.isNotEmpty ? series.length : 1,
    );
  }

  /// A series of [show] as a season. [episodes] is the number of episodes when it is known.
  ReplayTitle season(
    ReplayTitle show, {
    required String seriesGuid,
    required String name,
    required int number,
    int? episodes,
  }) => ReplayTitle(
    ref: stvSeasonRef(show.ref.nativeId, seriesGuid),
    kind: ReplayKind.season,
    title: name.trim().isEmpty ? show.title : name.trim(),
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: number,
    childCount: episodes,
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );

  /// The single season of a programme that lists no series.
  ReplayTitle allEpisodesSeason(ReplayTitle show, {int? episodes}) => ReplayTitle(
    ref: stvSeasonRef(show.ref.nativeId, stvPlayerAllEpisodes),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    childCount: episodes,
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );

  /// An episode. [seasonNumber] is the number the programme's series list gives its series; without it the number
  /// is read from the series name. An episode of a programme with no series belongs to season 1.
  ReplayTitle episode(Map<String, dynamic> episode, {int? seasonNumber}) {
    final ref = stvEpisodeRef(episode['id']);
    _restrictions.note(ref, (episode['_restrictions'] as Map?)?['locations']);

    final programme = episode['programme'] as Map<String, dynamic>?;
    final programmeGuid = programme?['guid'] as String?;
    final showTitle = _text(programme?['name']);
    final series = episode['playerSeries'] as Map<String, dynamic>?;
    final seriesGuid = series == null ? stvPlayerAllEpisodes : series['guid'] as String?;
    final title = _text(episode['title']) ?? showTitle ?? '${episode['id']}';
    final window = episode['availability'] as Map<String, dynamic>?;
    final image = stvPlayerImageReference(episode['images'], anyImage: true);

    return ReplayTitle(
      ref: ref,
      kind: ReplayKind.episode,
      title: title,
      summary: _summary(episode),
      posterUrl: image,
      backdropUrl: image,
      durationSeconds: _seconds((episode['video'] as Map?)?['length']),
      genres: _genres(episode['genre'], episode['_subGenre']),
      airDate: stvAirDateFromGuid(episode['guid'] as String?) ?? stvPlayerTime(window?['from']),
      availableUntil: stvPlayerTime(window?['until']),
      availability: stvPlayerAvailability(episode, _now()),
      seasonNumber: seasonNumber ?? (series == null ? 1 : stvSeasonNumberFromName(series['name'] as String?)),
      episodeNumber: _episodeNumber(episode, series),
      showRef: programmeGuid == null ? null : stvShowRef(programmeGuid),
      showTitle: showTitle,
      seasonRef: programmeGuid == null || seriesGuid == null ? null : stvSeasonRef(programmeGuid, seriesGuid),
    );
  }

  /// A news clip or other short-form item.
  ReplayTitle clip(Map<String, dynamic> clip) {
    final image = stvPlayerImageReference(clip['images'], anyImage: true);
    final window = clip['availability'] as Map<String, dynamic>?;
    return ReplayTitle(
      ref: stvClipRef(clip['id']),
      kind: ReplayKind.clip,
      title: _text(clip['title']) ?? '${clip['id']}',
      summary: _summary(clip),
      posterUrl: image,
      backdropUrl: image,
      durationSeconds: _seconds((clip['video'] as Map?)?['length']),
      availableUntil: stvPlayerTime(window?['until']),
      availability: stvPlayerAvailability(clip, _now()),
      showTitle: _text((clip['programme'] as Map?)?['name']),
    );
  }
}

int? _episodeNumber(Map<String, dynamic> episode, Map<String, dynamic>? series) {
  final index = series?['episodeIndex'];
  if (index is num && index > 0) return index.toInt();
  return stvEpisodeNumberFromTitle(episode['title'] as String?);
}

String? _summary(Map<String, dynamic> item) {
  final summary = _text(item['summary']);
  final guidance = _text(item['guidanceText']);
  if (summary == null) return guidance;
  return guidance == null ? summary : '$summary\n\n$guidance';
}

int? _seconds(Object? millis) => millis is num && millis > 0 ? (millis / 1000).round() : null;

List<String> _genres(Object? genre, [Object? subGenre]) {
  final names = <String>[];
  if (genre is Map) {
    for (final value in [genre['name'], (genre['subGenre'] as Map?)?['name']]) {
      if (_text(value) case final name?) names.add(name);
    }
  } else {
    for (final value in [genre, subGenre]) {
      if (_text(value) case final name?) names.add(name);
    }
  }
  return names;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
