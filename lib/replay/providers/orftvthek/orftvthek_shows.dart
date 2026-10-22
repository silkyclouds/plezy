import '../../model/replay_ref.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_json.dart';
import 'orftvthek_numbering.dart';

/// Which show a profile belongs to, and which season of it the profile is when ORF names it so.
class OrfShowIdentity {
  final ReplayRef ref;
  final String title;

  /// The season number when the profile is one season of a show ("Kiwi Staffel 2"), else null.
  final int? season;

  const OrfShowIdentity(this.ref, this.title, this.season);

  /// A profile titled `<show> Staffel <n>` belongs to that show; any other profile is a show of its own.
  factory OrfShowIdentity.of(int profileId, String profileTitle) {
    final split = splitOrfSeasonTitle(profileTitle);
    if (split == null) return OrfShowIdentity(orfProfileRef(profileId), profileTitle.trim(), null);
    return OrfShowIdentity(orfSeriesRef(orfSeriesKey(split.show)), split.show, split.season);
  }

  bool get isSeries => season != null;
}

const _transliteration = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss', 'é': 'e', 'è': 'e', 'à': 'a', 'ç': 'c'};

/// A stable key for a show title, so the profiles of one show meet under one ref whatever their capitalisation.
String orfSeriesKey(String showTitle) {
  final lower = showTitle.toLowerCase();
  final plain = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    plain.write(_transliteration[char] ?? char);
  }
  final key = plain.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return key.isEmpty ? 'show' : key;
}

/// Whether a profile is worth listing: sign-language and audio-description versions duplicate another profile, and
/// a profile with no episode online has nothing to play.
bool orfIsListedProfile(Map<String, dynamic> profile) =>
    profile['oegs'] != true &&
    profile['audio_description'] != true &&
    profile['hide_in_letter_group'] != true &&
    (orfInt(profile['online_episode_count']) ?? 1) > 0;
