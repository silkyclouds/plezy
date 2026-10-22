import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'stvr_images.dart';
import 'stvr_numbering.dart';
import 'stvr_refs.dart';

/// One page of a section: its show cards and the number of shows in the whole section.
class StvrCardPage {
  final List<ReplayTitle> shows;
  final int total;

  const StvrCardPage(this.shows, this.total);
}

final _card = RegExp(
  r'data-series-id="(\d+)"[^>]*>\s*<a href="/televizia/archiv/\d+/\d+" data-item-name="([^"]*)">'
  r'\s*<picture>(?:(?!</picture>)[\s\S])*?<img src="([^"]+)"',
);
final _rows = RegExp(r'data-rows-all="(\d+)"');

/// Reads the show cards out of a section page. The site serves HTML only for these lists.
StvrCardPage stvrParseCards(String html) {
  final seen = <String>{};
  final shows = <ReplayTitle>[];
  for (final match in _card.allMatches(html)) {
    final seriesId = match.group(1)!;
    final name = stvrParseShowName(htmlToText(match.group(2)));
    if (name.base.isEmpty || !seen.add(seriesId)) continue;
    final image = stvrAbsoluteImage(match.group(3));
    shows.add(
      ReplayTitle(
        ref: stvrShowRef(seriesId),
        kind: ReplayKind.show,
        title: name.base,
        posterUrl: image,
        backdropUrl: image,
      ),
    );
  }
  final total = int.tryParse(_rows.firstMatch(html)?.group(1) ?? '');
  return StvrCardPage(shows, total ?? shows.length);
}
