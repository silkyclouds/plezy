import '../../model/replay_ref.dart';

const franceTvSourceId = 'francetv';

/// Season key of the single season that holds every episode of a show without real seasons.
const franceTvAllEpisodesKey = '_all';

/// Season key prefix of a season derived from the episodes' own season numbers: `_s3`.
const franceTvDerivedSeasonPrefix = '_s';

final _safeSegment = RegExp(r'^[\w.-]+$');

ReplayRef franceTvShowRef(String programPath) => ReplayRef(franceTvSourceId, 'show/$programPath');

/// A season ref is `season/<show path>/<key>`, where the key is a season programme path (their names are
/// irregular, so they are read from the show page and never guessed), [franceTvAllEpisodesKey] or `_s<N>`.
ReplayRef franceTvSeasonRef(String showPath, String key) => ReplayRef(franceTvSourceId, 'season/$showPath/$key');

/// A video ref is `video/<stream id>[/<content id>]`. The stream id plays the video; the content id
/// is only needed to look the video up again when it was not seen in a list.
ReplayRef franceTvVideoRef(String streamId, int? contentId) =>
    ReplayRef(franceTvSourceId, contentId == null ? 'video/$streamId' : 'video/$streamId/$contentId');

sealed class FranceTvTarget {
  const FranceTvTarget();
}

class FranceTvShowTarget extends FranceTvTarget {
  final String programPath;

  const FranceTvShowTarget(this.programPath);
}

class FranceTvSeasonTarget extends FranceTvTarget {
  final String showPath;
  final String key;

  const FranceTvSeasonTarget(this.showPath, this.key);

  /// The programme page that lists this season's episodes.
  String get episodesPath =>
      key == franceTvAllEpisodesKey || key.startsWith(franceTvDerivedSeasonPrefix) ? showPath : key;

  /// The season number a derived season stands for, or null for the other kinds.
  int? get derivedNumber => key.startsWith(franceTvDerivedSeasonPrefix)
      ? int.tryParse(key.substring(franceTvDerivedSeasonPrefix.length))
      : null;
}

class FranceTvVideoTarget extends FranceTvTarget {
  final String streamId;
  final int? contentId;

  const FranceTvVideoTarget(this.streamId, this.contentId);
}

/// Reads a ref of this source, or null when it is not one this provider produced.
FranceTvTarget? franceTvTarget(ReplayRef ref) {
  if (ref.source != franceTvSourceId) return null;
  final parts = ref.nativeId.split('/');
  if (parts.length < 2 || !parts.every(_safeSegment.hasMatch)) return null;
  return switch (parts) {
    ['show', final path] => FranceTvShowTarget(path),
    ['season', final show, final key] => FranceTvSeasonTarget(show, key),
    ['video', final id] => FranceTvVideoTarget(id, null),
    ['video', final id, final content] => FranceTvVideoTarget(id, int.tryParse(content)),
    _ => null,
  };
}
