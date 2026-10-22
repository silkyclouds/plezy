import '../../../replay/provider/replay_source_groups.dart';

/// Shortest search text that narrows the list.
const replayMinSearchLength = 2;

/// Whether [query] is long enough to filter the channel list.
bool isReplaySearch(String query) => query.trim().length >= replayMinSearchLength;

const _accented = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ';
const _plain = 'aaaaaaceeeeiiiinooooouuuuyy';

String _fold(String text) {
  final out = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final at = _accented.indexOf(char);
    out.write(at < 0 ? char : _plain[at]);
  }
  return out.toString();
}

/// The countries of [groups] reduced to the channels whose name contains [query] (case and accents ignored).
/// Languages and countries left without a channel are dropped.
List<ReplayCountryGroup> filterReplayGroups(List<ReplayCountryGroup> groups, String query) {
  final needle = _fold(query.trim());
  final result = <ReplayCountryGroup>[];
  for (final group in groups) {
    final languages = <ReplayLanguageGroup>[];
    for (final language in group.languages) {
      final found = [
        for (final source in language.sources)
          if (_fold(source.name).contains(needle)) source,
      ];
      if (found.isNotEmpty) languages.add(ReplayLanguageGroup(language.language, found));
    }
    if (languages.isNotEmpty) result.add(ReplayCountryGroup(group.country, languages));
  }
  return result;
}
