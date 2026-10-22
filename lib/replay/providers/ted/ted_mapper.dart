import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'ted_ids.dart';
import 'ted_images.dart';
import 'ted_topics.dart';

/// Where a talk sits in a playlist, so it can be shown as an episode of that playlist's only season.
class TedPlacement {
  final ReplayRef show;
  final String showTitle;
  final int number;

  const TedPlacement({required this.show, required this.showTitle, required this.number});
}

const _talkPosterRatios = ['4x3', '16x9', '2x1'];
const _talkBackdropRatios = ['16x9', '2x1', '4x3'];
const _playlistPosterRatios = ['1x1', '400x209'];
const _playlistBackdropRatios = ['400x209', '1x1'];

/// Maps one `Video` node to a movie, or to an episode when [placement] says which playlist it was listed in.
/// Returns null for a node without a slug, which cannot be opened later.
ReplayTitle? tedTalkFromNode(Map<String, dynamic> node, {TedPlacement? placement}) {
  final slug = node['slug'] as String?;
  if (slug == null || slug.isEmpty) return null;
  final presenter = _nonEmpty(node['presenterDisplayName'] as String?);
  final published = _date(node['publishedAt']);
  final images = node['primaryImageSet'];

  return ReplayTitle(
    ref: tedTalkRef(slug),
    kind: placement == null ? ReplayKind.movie : ReplayKind.episode,
    title: _title(node['title'], slug),
    subtitle: presenter,
    summary: _summary(node['description'] as String?),
    posterUrl: tedPickImage(images, _talkPosterRatios),
    backdropUrl: tedPickImage(images, _talkBackdropRatios),
    durationSeconds: (node['duration'] as num?)?.toInt(),
    year: _year(node['recordedOn']) ?? published?.year,
    genres: _topics(node['topics']),
    cast: presenter == null ? const [] : [presenter],
    airDate: published,
    availability: _hasStream(node) ? ReplayAvailability.playable : ReplayAvailability.unknown,
    seasonNumber: placement == null ? null : 1,
    episodeNumber: placement?.number,
    showRef: placement?.show,
    showTitle: placement?.showTitle,
    seasonRef: placement == null ? null : tedSeasonRef(_slugOf(placement.show)),
  );
}

/// Maps one `Playlist` node to a show with a single season.
ReplayTitle? tedPlaylistFromNode(Map<String, dynamic> node) {
  final slug = node['slug'] as String?;
  if (slug == null || slug.isEmpty) return null;
  final images = node['primaryImageSet'];
  return ReplayTitle(
    ref: tedPlaylistRef(slug),
    kind: ReplayKind.show,
    title: _title(node['title'], slug),
    summary: _summary(node['description'] as String?),
    posterUrl: tedPickImage(images, _playlistPosterRatios),
    backdropUrl: tedPickImage(images, _playlistBackdropRatios),
    childCount: 1,
  );
}

/// The single season that stands for a whole playlist; [talkCount] is the number of talks it holds.
ReplayTitle tedSeasonOfPlaylist(ReplayTitle show, {int? talkCount}) => ReplayTitle(
  ref: tedSeasonRef(_slugOf(show.ref)),
  kind: ReplayKind.season,
  title: show.title,
  summary: show.summary,
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: 1,
  childCount: talkCount,
  showRef: show.ref,
  showTitle: show.title,
);

/// Talks of a connection (`{ nodes: [...] }`), without repeats and without nodes that cannot be opened.
List<ReplayTitle> tedTalksFromConnection(Object? connection, {TedPlacement? Function(int index)? placementOf}) {
  final nodes = connection is Map<String, dynamic> ? connection['nodes'] : null;
  if (nodes is! List) return const [];
  final seen = <ReplayRef>{};
  final talks = <ReplayTitle>[];
  for (final (index, node) in nodes.indexed) {
    if (node is! Map<String, dynamic>) continue;
    final talk = tedTalkFromNode(node, placement: placementOf?.call(index));
    if (talk != null && seen.add(talk.ref)) talks.add(talk);
  }
  return talks;
}

List<ReplayTitle> tedPlaylistsFromConnection(Object? connection) {
  final nodes = connection is Map<String, dynamic> ? connection['nodes'] : null;
  if (nodes is! List) return const [];
  return [for (final node in nodes.whereType<Map<String, dynamic>>()) ?tedPlaylistFromNode(node)];
}

int tedTotalCount(Object? connection) =>
    connection is Map<String, dynamic> ? (connection['totalCount'] as num?)?.toInt() ?? 0 : 0;

/// A talk with no stream address cannot be played, and the list can say so before the user presses it.
bool _hasStream(Map<String, dynamic> node) => (node['hlsUrl'] as String?)?.isNotEmpty ?? false;

String _slugOf(ReplayRef ref) => ref.nativeId.split('/')[1];

List<String> _topics(Object? topics) {
  final nodes = topics is Map<String, dynamic> ? topics['nodes'] : null;
  if (nodes is! List) return const [];
  return [
    for (final node in nodes.whereType<Map<String, dynamic>>())
      if (node['slug'] is String) tedTopicLabel(node['slug'] as String),
  ];
}

/// Titles come with stray tabs and trailing spaces; whitespace runs become one space.
String _title(Object? raw, String fallback) {
  final text = raw is String ? raw.replaceAll(RegExp(r'\s+'), ' ').trim() : '';
  return text.isEmpty ? fallback : text;
}

String? _summary(String? description) {
  final text = htmlToText(description);
  return text.isEmpty ? null : text;
}

String? _nonEmpty(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

int? _year(Object? day) => day is String && day.length >= 4 ? int.tryParse(day.substring(0, 4)) : null;
