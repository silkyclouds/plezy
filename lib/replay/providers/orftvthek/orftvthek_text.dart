import 'orftvthek_json.dart';

final _afterShowName = RegExp(r'^\s*(?:\(\s*\d+\s*/\s*\d+\s*\))?\s*[:–-]\s*(\S.*)$');

/// An episode title without the show name and counter ORF puts in front of it.
///
/// "Die Rosenheim-Cops (24/27): Ein tödliches Geschenk" becomes "Ein tödliches Geschenk" inside the show. Titles that
/// only continue the show name ("ZIB 1 vom 21.10.2026") are kept whole.
String orfTrimEpisodeTitle(String title, String showTitle) {
  if (!title.toLowerCase().startsWith(showTitle.toLowerCase())) return title;
  final rest = _afterShowName.firstMatch(title.substring(showTitle.length))?.group(1)?.trim();
  return rest == null || rest.isEmpty ? title : rest;
}

/// The synopsis of an item. ORF's news synopses are the headline list joined with " | ", which reads better as lines.
String? orfSummary(Map<String, dynamic> item) {
  final text = orfString(item['description']) ?? orfString(item['teaser_text']);
  return text?.replaceAll(' | ', '\n');
}
