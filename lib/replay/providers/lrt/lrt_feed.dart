import 'package:xml/xml.dart';

import 'lrt_dates.dart';
import 'lrt_images.dart';
import 'lrt_models.dart';
import 'lrt_refs.dart';

/// Most recordings a programme, season or section feed carries; a feed this long may have more behind it.
const lrtFeedLimit = 100;

final _imageSource = RegExp('<img[^>]+src="([^"]+)"');
final _blanks = RegExp(r'\s+');

/// Recordings of an RSS feed, newest first as the site sends them. Items without a recording link or a title are
/// dropped, and a body that is not well-formed XML gives an empty list.
List<LrtRecording> parseLrtFeed(Object? body) {
  if (body is! String) return const [];
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException {
    return const [];
  }
  final seen = <String>{};
  final recordings = <LrtRecording>[];
  for (final item in document.findAllElements('item')) {
    final recording = _item(item);
    if (recording != null && seen.add(recording.postId)) recordings.add(recording);
  }
  return recordings;
}

LrtRecording? _item(XmlElement item) {
  final postId = lrtPostIdOf(_text(item, 'link') ?? _text(item, 'guid'));
  final title = _text(item, 'title');
  if (postId == null || title == null) return null;
  final picture = _imageSource.firstMatch(_text(item, 'description', collapse: false) ?? '')?.group(1);
  return LrtRecording(
    postId: postId,
    title: title,
    imageTemplate: lrtImageTemplate(picture),
    published: lrtParseRfc822(_text(item, 'pubDate')),
    showTitle: _text(item, 'category'),
  );
}

String? _text(XmlElement item, String name, {bool collapse = true}) {
  final raw = item.getElement(name)?.innerText;
  if (raw == null) return null;
  final text = collapse ? raw.replaceAll(_blanks, ' ').trim() : raw;
  return text.trim().isEmpty ? null : text;
}
