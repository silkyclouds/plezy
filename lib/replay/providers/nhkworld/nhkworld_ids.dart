import '../../model/replay_ref.dart';

const nhkWorldSourceId = 'nhkworld';

enum NhkTargetKind { show, season, episode, clip }

/// What a native id of this provider points at.
///
/// Shows are `p/<programme>`, seasons `p/<programme>/<year>`, episodes `e/<id>` and clips `c/<id>`. The prefix keeps
/// a programme whose slug looks like an episode id from being mistaken for one.
class NhkTarget {
  final NhkTargetKind kind;

  /// Programme slug, episode id or clip id.
  final String id;

  /// Calendar year of a season; null for every other kind.
  final int? year;

  const NhkTarget(this.kind, this.id, {this.year});
}

ReplayRef nhkShowRef(String programId) => ReplayRef(nhkWorldSourceId, 'p/$programId');

ReplayRef nhkSeasonRef(String programId, int year) => ReplayRef(nhkWorldSourceId, 'p/$programId/$year');

ReplayRef nhkEpisodeRef(String episodeId) => ReplayRef(nhkWorldSourceId, 'e/$episodeId');

ReplayRef nhkClipRef(String clipId) => ReplayRef(nhkWorldSourceId, 'c/$clipId');

/// Reads a native id, or null when it is not one this provider produced.
NhkTarget? parseNhkNativeId(String nativeId) {
  final parts = nativeId.split('/');
  if (parts.any((part) => part.isEmpty)) return null;
  return switch ((parts.first, parts.length)) {
    ('p', 2) => NhkTarget(NhkTargetKind.show, parts[1]),
    ('p', 3) => _season(parts[1], parts[2]),
    ('e', 2) => NhkTarget(NhkTargetKind.episode, parts[1]),
    ('c', 2) => NhkTarget(NhkTargetKind.clip, parts[1]),
    _ => null,
  };
}

NhkTarget? _season(String programId, String year) {
  final parsed = int.tryParse(year);
  return parsed == null ? null : NhkTarget(NhkTargetKind.season, programId, year: parsed);
}
