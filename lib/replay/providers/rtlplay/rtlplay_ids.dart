import '../../model/replay_ref.dart';

const rtlPlaySourceId = 'rtlplay';

/// What a native id points at: a programme, one season of it, or one episode.
///
/// Native ids are `programme`, `programme/season` and `programme/season/episode`. Only the programme
/// and episode ids exist at the broadcaster; the season index is the value its detail endpoint takes.
class RtlPlayId {
  final String programme;
  final int? season;
  final String? episode;

  const RtlPlayId(this.programme, {this.season, this.episode});

  static RtlPlayId? tryParse(String native) {
    final parts = native.split('/');
    if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.isEmpty)) return null;
    if (parts.length == 1) return RtlPlayId(parts[0]);
    final season = int.tryParse(parts[1]);
    if (season == null) return null;
    return RtlPlayId(parts[0], season: season, episode: parts.length == 3 ? parts[2] : null);
  }

  bool get isProgramme => season == null;
  bool get isSeason => season != null && episode == null;
  bool get isEpisode => episode != null;

  ReplayRef get programmeRef => rtlPlayRef(programme);
  ReplayRef get seasonRef => rtlPlayRef('$programme/$season');

  @override
  String toString() => [programme, ?season, ?episode].join('/');
}

ReplayRef rtlPlayRef(String native) => ReplayRef(rtlPlaySourceId, native);

ReplayRef rtlPlayEpisodeRef(String programme, int season, String episode) =>
    rtlPlayRef('$programme/$season/$episode');
