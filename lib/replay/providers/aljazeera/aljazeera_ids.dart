import '../../model/replay_ref.dart';

const aljazeeraSourceId = 'aljazeera';

/// What a native id points at.
///
/// Native ids are `programme` (a show), `programme/year` (a season), `programme/e/video` (an episode, where
/// `video` is the Brightcove video id) and `v/video` (a news clip that belongs to no programme). The
/// `v/` prefix cannot clash with a programme slug.
class AljazeeraId {
  final String? programme;
  final int? year;
  final String? video;
  final bool isClip;

  const AljazeeraId._({this.programme, this.year, this.video, this.isClip = false});

  const AljazeeraId.show(String programme) : this._(programme: programme);

  const AljazeeraId.season(String programme, int year) : this._(programme: programme, year: year);

  const AljazeeraId.episode(String programme, String video) : this._(programme: programme, video: video);

  const AljazeeraId.clip(String video) : this._(video: video, isClip: true);

  static AljazeeraId? tryParse(String native) {
    final parts = native.split('/');
    if (parts.any((p) => p.isEmpty)) return null;
    return switch (parts) {
      ['v', final video] => AljazeeraId.clip(video),
      [final programme] when programme != 'v' => AljazeeraId.show(programme),
      [final programme, final year] when RegExp(r'^\d{4}$').hasMatch(year) => AljazeeraId.season(
        programme,
        int.parse(year),
      ),
      [final programme, 'e', final video] => AljazeeraId.episode(programme, video),
      _ => null,
    };
  }

  bool get isShow => programme != null && year == null && video == null;
  bool get isSeason => year != null;
  bool get isEpisode => programme != null && video != null;

  ReplayRef get ref => ReplayRef(aljazeeraSourceId, toString());

  ReplayRef get showRef => ReplayRef(aljazeeraSourceId, programme!);

  @override
  String toString() {
    if (isClip) return 'v/$video';
    if (video != null) return '$programme/e/$video';
    if (year != null) return '$programme/$year';
    return programme!;
  }
}
