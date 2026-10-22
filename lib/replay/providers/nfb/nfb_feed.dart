import 'package:xml/xml.dart';

import '../../model/replay_title.dart';
import 'nfb_ids.dart';
import 'nfb_images.dart';
import 'nfb_values.dart';

/// The cards of the "recently added" feed. Items without a film address are skipped and a feed that is not valid XML
/// yields no cards.
List<ReplayTitle> nfbTitlesFromFeed(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return const [];
  }
  final seen = <String>{};
  final titles = <ReplayTitle>[];
  for (final item in document.findAllElements('item')) {
    final slug = nfbSlugFromUrl(_text(item, 'link'));
    final name = _text(item, 'title');
    if (slug == null || name == null || !seen.add(slug)) continue;
    final picture = nfbImageFromUrl(item.getElement('enclosure')?.getAttribute('url'));
    titles.add(
      ReplayTitle(
        ref: nfbRef(slug),
        kind: ReplayKind.movie,
        title: name,
        posterUrl: picture,
        backdropUrl: picture,
        airDate: _rfc822(_text(item, 'pubDate')),
      ),
    );
  }
  return titles;
}

String? _text(XmlElement item, String name) => nfbNonEmpty(item.getElement(name)?.innerText);

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// `Thu, 23 Oct 2025 15:30:22 -0400` as a UTC time, or null for anything else.
DateTime? _rfc822(String? raw) {
  final match = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4}|GMT|UTC|Z)?',
  ).firstMatch(raw ?? '');
  final month = match == null ? -1 : _months.indexOf(match.group(2)!.toLowerCase());
  if (match == null || month < 0) return null;
  final local = DateTime.utc(
    int.parse(match.group(3)!),
    month + 1,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  final zone = match.group(7);
  if (zone == null || zone.length != 5) return local;
  final minutes = int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3));
  return zone.startsWith('-') ? local.add(Duration(minutes: minutes)) : local.subtract(Duration(minutes: minutes));
}
