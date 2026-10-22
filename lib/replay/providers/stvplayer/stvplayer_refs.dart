import '../../model/replay_ref.dart';

const stvPlayerSourceId = 'stvplayer';

/// Season id of a programme that lists no series: every episode of the show.
const stvPlayerAllEpisodes = '_all';

const _episodePrefix = 'episode:';
const _clipPrefix = 'clip:';

/// What a native id points at.
enum StvTargetKind { show, season, episode, clip }

/// A parsed native id. [programme] is set for shows and seasons, [series] for seasons, [id] for episodes and clips.
class StvTarget {
  final StvTargetKind kind;
  final String? programme;
  final String? series;
  final String? id;

  const StvTarget._(this.kind, {this.programme, this.series, this.id});

  /// Reads a native id: `guid` for a show, `guid/seriesGuid` for a season, `episode:12345` and `clip:12345`.
  factory StvTarget.parse(String nativeId) {
    if (nativeId.startsWith(_episodePrefix)) {
      return StvTarget._(StvTargetKind.episode, id: nativeId.substring(_episodePrefix.length));
    }
    if (nativeId.startsWith(_clipPrefix)) {
      return StvTarget._(StvTargetKind.clip, id: nativeId.substring(_clipPrefix.length));
    }
    final cut = nativeId.indexOf('/');
    if (cut < 0) return StvTarget._(StvTargetKind.show, programme: nativeId);
    return StvTarget._(
      StvTargetKind.season,
      programme: nativeId.substring(0, cut),
      series: nativeId.substring(cut + 1),
    );
  }

  bool get isAllEpisodes => series == stvPlayerAllEpisodes;
}

ReplayRef stvShowRef(String programmeGuid) => ReplayRef(stvPlayerSourceId, programmeGuid);

ReplayRef stvSeasonRef(String programmeGuid, String seriesGuid) =>
    ReplayRef(stvPlayerSourceId, '$programmeGuid/$seriesGuid');

ReplayRef stvEpisodeRef(Object id) => ReplayRef(stvPlayerSourceId, '$_episodePrefix$id');

ReplayRef stvClipRef(Object id) => ReplayRef(stvPlayerSourceId, '$_clipPrefix$id');
