import '../../model/replay_ref.dart';

/// Source id of Deutsche Welle's English edition.
const dwSourceId = 'dw';

ReplayRef dwRef(String nativeId) => ReplayRef(dwSourceId, nativeId);

/// Native id of a programme (a show): `p294010`.
String dwShowId(int programme) => 'p$programme';

/// Native id of one calendar year of a programme (a season): `p294010/2026`.
String dwSeasonId(int programme, int year) => 'p$programme/$year';

final _programmeId = RegExp(r'^p(\d+)(?:/(\d{4}))?$');
final _videoId = RegExp(r'^\d+$');

/// What a native id of this source points at. A video is its bare numeric id.
class DwId {
  final int? programme;
  final int? year;
  final int? video;

  const DwId._({this.programme, this.year, this.video});

  static DwId? tryParse(String raw) {
    final programme = _programmeId.firstMatch(raw);
    if (programme != null) {
      final year = programme.group(2);
      return DwId._(programme: int.parse(programme.group(1)!), year: year == null ? null : int.parse(year));
    }
    return _videoId.hasMatch(raw) ? DwId._(video: int.parse(raw)) : null;
  }

  bool get isShow => programme != null && year == null;
  bool get isSeason => programme != null && year != null;
  bool get isVideo => video != null;
}
