import '../../media/media_backend.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_role.dart';
import '../model/replay_ref.dart';
import '../model/replay_title.dart';
import 'replay_title_memory.dart';
import '../provider/replay_provider.dart';

/// Key under which [ReplayAvailability] travels in `MediaItem.raw`.
const replayAvailabilityKey = 'replayAvailability';

/// True when there is one landscape image and no separate portrait poster. Providers repeat the same reference for both
/// fields in that case, so equal fields mean there is no poster to show.
bool replayHasLandscapeOnlyArtwork(String? poster, String? backdrop) =>
    backdrop != null && (poster == null || poster == backdrop);

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

/// An episode named only after its show ("Journal") cannot be told apart from its neighbours in a list, so the air date
/// is appended when the title carries no number of its own.
String _displayTitle(ReplayTitle t) {
  final date = t.airDate;
  if (t.kind != ReplayKind.episode || date == null || t.episodeNumber != null || t.title.contains(RegExp(r'\d'))) {
    return t.title;
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.title} · ${two(date.day)}/${two(date.month)}/${date.year}';
}

/// Maps broadcaster titles to the neutral items the rest of the app renders.
class ReplayMapper {
  final String serverId;
  final String? serverName;
  final ReplaySource source;
  final ReplayTitleMemory? memory;

  /// The viewer is outside a restriction that covers the broadcaster's whole catalogue, so playable titles are
  /// stamped geo-blocked (a guess that a VPN or a licence exception can disprove at play time).
  final bool blanketGeoBlock;

  /// Per-title verdicts the broadcaster gave for the viewer's country (see `ReplayForecast`).
  final Map<ReplayRef, ReplayAvailability> predicted;

  const ReplayMapper({
    required this.serverId,
    required this.source,
    this.serverName,
    this.memory,
    this.blanketGeoBlock = false,
    this.predicted = const {},
  });

  MediaItem item(ReplayTitle listed) {
    final t = memory?.fill(listed) ?? listed;
    final kind = replayKindToMediaKind(t.kind);
    final poster = t.posterUrl ?? t.backdropUrl;
    return MediaItem.replay(
      id: t.ref.toString(),
      kind: kind,
      title: _displayTitle(t),
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
      // A season-less episode of a show is filed under season 1 rather than season 0.
      parentIndex: t.seasonNumber ?? (kind == MediaKind.episode && t.showRef != null ? 1 : null),
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
      raw: {
        replayAvailabilityKey: _stampedAvailability(t).name,
        if (replayHasLandscapeOnlyArtwork(t.posterUrl, t.backdropUrl)) landscapeOnlyArtworkRawKey: true,
      },
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

  ReplayAvailability _stampedAvailability(ReplayTitle t) {
    if (t.availability != ReplayAvailability.playable) return t.availability;
    final forecast = predicted[t.ref];
    if (forecast != null) return forecast;
    return blanketGeoBlock && t.isPlayable ? ReplayAvailability.geoBlocked : t.availability;
  }

  static String? _isoDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
