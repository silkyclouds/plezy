import '../../media/media_backend.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_role.dart';
import '../model/replay_title.dart';
import '../provider/replay_provider.dart';

/// Key under which [ReplayAvailability] travels in `MediaItem.raw`.
const replayAvailabilityKey = 'replayAvailability';

MediaKind replayKindToMediaKind(ReplayKind kind) => switch (kind) {
  ReplayKind.movie => MediaKind.movie,
  ReplayKind.show => MediaKind.show,
  ReplayKind.season => MediaKind.season,
  ReplayKind.episode => MediaKind.episode,
  ReplayKind.clip => MediaKind.clip,
};

/// Reads the availability a mapped item was stamped with; items without one are assumed playable.
ReplayAvailability replayAvailabilityOf(MediaItem item) {
  final name = item.raw?[replayAvailabilityKey];
  return ReplayAvailability.values.asNameMap()[name] ?? ReplayAvailability.playable;
}

/// Maps broadcaster titles to the neutral items the rest of the app renders.
class ReplayMapper {
  final String serverId;
  final String? serverName;
  final ReplaySource source;

  const ReplayMapper({required this.serverId, required this.source, this.serverName});

  MediaItem item(ReplayTitle t) {
    final kind = replayKindToMediaKind(t.kind);
    final poster = t.posterUrl ?? t.backdropUrl;
    return MediaItem.replay(
      id: t.ref.toString(),
      kind: kind,
      title: t.title,
      titleSort: t.title,
      tagline: t.subtitle,
      summary: t.summary,
      year: t.year,
      originallyAvailableAt: _isoDate(t.airDate),
      contentRating: t.contentRating,
      studio: source.name,
      thumbPath: poster,
      artPath: t.backdropUrl,
      backdropPaths: t.backdropUrl == null ? null : [t.backdropUrl!],
      clearLogoPath: t.logoUrl,
      durationMs: t.durationSeconds == null ? null : t.durationSeconds! * 1000,
      index: kind == MediaKind.episode ? t.episodeNumber : t.seasonNumber,
      parentId: t.seasonRef?.toString() ?? t.showRef?.toString(),
      parentTitle: t.showTitle,
      parentIndex: t.seasonNumber,
      grandparentId: t.showRef?.toString(),
      grandparentTitle: t.showTitle,
      childCount: t.childCount,
      leafCount: kind == MediaKind.season ? t.childCount : null,
      genres: t.genres,
      directors: t.directors,
      roles: [for (final name in t.cast) MediaRole(tag: name)],
      libraryId: source.id,
      libraryTitle: source.name,
      serverId: serverId,
      serverName: serverName,
      raw: {replayAvailabilityKey: t.availability.name},
    );
  }

  List<MediaItem> items(Iterable<ReplayTitle> titles) => [for (final t in titles) item(t)];

  MediaHub hub(ReplayRail rail) => MediaHub(
    id: '${source.id}:${rail.id}',
    identifier: 'replay.${source.id}.${rail.id}',
    title: rail.title,
    type: 'mixed',
    items: items(rail.titles),
    size: rail.titles.length,
    more: rail.moreBrowseId != null,
    libraryId: source.id,
    serverId: serverId,
    serverName: serverName,
  );

  MediaLibrary library() => MediaLibrary(
    id: source.id,
    backend: MediaBackend.replay,
    title: source.name,
    kind: MediaKind.unknown,
    defaultBrowseKinds: const [MediaKind.show, MediaKind.movie],
    language: source.language,
    serverId: serverId,
    serverName: serverName,
  );

  static String? _isoDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
