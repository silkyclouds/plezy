import '../../model/replay_ref.dart';

const france24SourceId = 'france24';

/// What a native id points at.
///
/// Native ids are `programme` (a show), `programme/year` (a season), `programme/e/edition` (an episode)
/// and `v/video` (a clip with no programme). A programme and a clip share the same id syntax at the
/// broadcaster, so the `v/` prefix is what tells them apart.
class France24Id {
  final String? programme;
  final int? year;
  final String? edition;
  final String? clip;

  const France24Id._({this.programme, this.year, this.edition, this.clip});

  const France24Id.show(String programme) : this._(programme: programme);

  const France24Id.season(String programme, int year) : this._(programme: programme, year: year);

  const France24Id.episode(String programme, String edition) : this._(programme: programme, edition: edition);

  const France24Id.clip(String video) : this._(clip: video);

  static France24Id? tryParse(String native) {
    final parts = native.split('/');
    if (parts.any((p) => p.isEmpty)) return null;
    return switch (parts) {
      ['v', final video] => France24Id.clip(video),
      [final programme] => France24Id.show(programme),
      [final programme, final year] when _isYear(year) => France24Id.season(programme, int.parse(year)),
      [final programme, 'e', final edition] => France24Id.episode(programme, edition),
      _ => null,
    };
  }

  bool get isClip => clip != null;
  bool get isShow => programme != null && year == null && edition == null;
  bool get isSeason => year != null;
  bool get isEpisode => edition != null;

  ReplayRef get ref => ReplayRef(france24SourceId, toString());

  ReplayRef get showRef => ReplayRef(france24SourceId, programme!);

  @override
  String toString() {
    if (clip != null) return 'v/$clip';
    if (edition != null) return '$programme/e/$edition';
    if (year != null) return '$programme/$year';
    return programme!;
  }

  static bool _isYear(String text) => RegExp(r'^\d{4}$').hasMatch(text);
}
