import '../../model/replay_title.dart';

/// An episode number and the title left once the number is taken out of it.
typedef TvpEpisodeLabel = ({int? number, String title});

final _numbered = RegExp(
  r'^(?:odc\.?|odcinek|cz\.|część)\s*(\d+)\s*(?:[–—:.\-]+\s*(.*))?$',
  caseSensitive: false,
  unicode: true,
);

/// Reads the broadcaster's own episode number from a title such as "odc. 7 – Spadek".
///
/// The number in the title is the one printed on the site. The `number` field is only a running index that drifts
/// from it on shows with specials, and is -1 on single programmes, so it is the fallback.
TvpEpisodeLabel tvpEpisodeLabel(String title, Object? apiNumber) {
  final match = _numbered.firstMatch(title.trim());
  if (match != null) {
    final rest = match.group(2)?.trim() ?? '';
    return (number: int.parse(match.group(1)!), title: rest.isEmpty ? title.trim() : rest);
  }
  final fallback = apiNumber is num && apiNumber > 0 ? apiNumber.toInt() : null;
  return (number: fallback, title: title.trim());
}

/// Episodes oldest first when every one is numbered; otherwise in the order the site gave, flipped when the show is
/// listed newest first.
List<ReplayTitle> tvpOrderEpisodes(List<ReplayTitle> episodes, {required bool newestFirst}) {
  if (episodes.every((e) => e.episodeNumber != null)) {
    final sorted = [...episodes]..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
    return sorted;
  }
  return newestFirst ? episodes.reversed.toList() : episodes;
}

/// Seasons by number, keeping the site's order between equal numbers.
List<ReplayTitle> tvpOrderSeasons(List<ReplayTitle> seasons) {
  final indexed = [for (var i = 0; i < seasons.length; i++) (i, seasons[i])];
  indexed.sort((a, b) {
    final byNumber = (a.$2.seasonNumber ?? 0).compareTo(b.$2.seasonNumber ?? 0);
    return byNumber != 0 ? byNumber : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
