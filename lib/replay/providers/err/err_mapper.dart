import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'err_images.dart';
import 'err_numbering.dart';
import 'err_refs.dart';

/// Where an item was found, so episodes know their show and season.
class ErrContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const ErrContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = ErrContext();
}

/// Maps a card of a row, a search hit, a season list or the catalogue to a [ReplayTitle].
///
/// Null when there is nothing to open: no video behind it, or a kind this app does not show. Cards and search hits
/// already call a single recording a movie and a multi-episode programme a series; the catalogue and genre lists carry
/// the raw `show` type, and there a programme with no media of its own is the container.
ReplayTitle? errTitleFromItem(Map<String, dynamic> item, {ErrContext context = ErrContext.none}) {
  final id = (item['id'] as num?)?.toInt();
  if (id == null || item['hasActiveMedia'] == false) return null;
  final kind = _kindOf(item);
  if (kind == null) return null;

  final heading = errText(item['heading']) ?? '$id';
  final subHeading = errText(item['subHeading']);
  final isEpisode = kind == ReplayKind.episode;
  final backdrop = errBackdropReference(item);
  return ReplayTitle(
    ref: errRef(id),
    kind: kind,
    title: isEpisode ? subHeading ?? heading : heading,
    subtitle: isEpisode ? null : subHeading,
    summary: _nonEmpty(htmlToText(item['lead'] as String?)),
    posterUrl: errPosterReference(item) ?? backdrop,
    backdropUrl: backdrop,
    durationSeconds: errDuration(errFirstMedia(item)),
    airDate: errDate(item['publicStart']),
    seasonNumber: isEpisode ? context.seasonNumber ?? _seasonOf(item, heading, subHeading) : null,
    episodeNumber: isEpisode ? _episodeOf(item, heading, subHeading) : null,
    showRef: context.show ?? _rootRef(item, kind),
    showTitle: context.showTitle ?? (isEpisode ? heading : null),
    seasonRef: context.season,
  );
}

ReplayKind? _kindOf(Map<String, dynamic> item) {
  final type = item['type'];
  final medias = item['medias'];
  return switch (type) {
    'series' => ReplayKind.show,
    'movie' || 'show' => (medias is List ? medias.isNotEmpty : type == 'movie') ? ReplayKind.movie : ReplayKind.show,
    'episode' => ReplayKind.episode,
    'clip' => ReplayKind.clip,
    _ => null,
  };
}

ReplayRef? _rootRef(Map<String, dynamic> item, ReplayKind kind) {
  if (kind != ReplayKind.episode && kind != ReplayKind.clip) return null;
  final root = (item['rootContentId'] as num?)?.toInt() ?? 0;
  return root > 0 ? errRef(root) : null;
}

int? _seasonOf(Map<String, dynamic> item, String heading, String? subHeading) {
  final number = (item['season'] as num?)?.toInt() ?? 0;
  return number > 0 ? number : errSeasonFromTitle(heading, subHeading);
}

int? _episodeOf(Map<String, dynamic> item, String heading, String? subHeading) {
  final number = (item['episode'] as num?)?.toInt() ?? 0;
  return number > 0 ? number : errEpisodeFromTitle(heading, subHeading);
}

/// The first media of an item, which is the one ERR plays.
Map<String, dynamic>? errFirstMedia(Map<String, dynamic> item) {
  final medias = item['medias'];
  return medias is List && medias.isNotEmpty && medias.first is Map<String, dynamic>
      ? medias.first as Map<String, dynamic>
      : null;
}

int? errDuration(Map<String, dynamic>? media) {
  final raw = (media?['mediaInfo'] as Map?)?['duration'];
  final seconds = raw is num ? raw.toInt() : int.tryParse('$raw');
  return seconds == null || seconds <= 0 ? null : seconds;
}

/// ERR dates are Unix seconds; 0 means "not set".
DateTime? errDate(Object? seconds) {
  if (seconds is! num || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000, isUtc: true);
}

/// A text field without the `&nbsp;` and markup ERR leaves in headings, or null when empty.
String? errText(Object? value) {
  if (value is! String) return null;
  return _nonEmpty(htmlToText(value).replaceAll(' ', ' ').trim());
}

String? _nonEmpty(String value) => value.isEmpty ? null : value;
