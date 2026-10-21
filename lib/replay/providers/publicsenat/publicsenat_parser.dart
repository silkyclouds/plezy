import 'dart:convert';

import '../dailymotion/dailymotion_ids.dart';
import 'publicsenat_models.dart';

const publicSenatOrigin = 'https://www.publicsenat.fr';

// The site is rendered by a CSS framework, so none of these patterns rely on class names. They anchor on
// attributes the templates need for their own scripts: the grid marker, the cover size, the thumbnail
// URL and the datetime of the broadcast.
final _article = RegExp(r'<article\b[^>]*>.*?</article>', dotAll: true);
final _anchor = RegExp(r'<a\b([^>]*)>(.*?)</a>', dotAll: true);
final _paragraph = RegExp(r'<p\b[^>]*>(.*?)</p>', dotAll: true);
final _picture = RegExp(r'<picture\b.*?</picture>', dotAll: true);
final _tag = RegExp(r'<[^>]+>');
final _programmePath = RegExp(r'^(?:https://www\.publicsenat\.fr)?/emission/([^/?#]+)/?$');
final _episodePath = RegExp(r'^(?:https://www\.publicsenat\.fr)?/emission/([^/?#]+)/([^/?#]+)/?$');
final _date = RegExp(r'<time\b[^>]*datetime="(\d{4})-(\d{2})-(\d{2})');
final _duration = RegExp(r'(?:(\d+)\s*h)?\s*(\d+)\s*mn\b');
final _siteNumber = RegExp(r'-e(\d+)$');
final _largeImage = RegExp(r'(https://[^\s",]*dmcdn\.net/[^\s",]+)\s+2x');

/// Programme covers of the index page, in page order.
List<PsProgramme> parseProgrammes(String html) {
  final programmes = <PsProgramme>[];
  final seen = <String>{};
  for (final match in _article.allMatches(html)) {
    final article = match.group(0)!;
    if (_attr(article.substring(0, article.indexOf('>') + 1), 'size') != 'program_cover') continue;
    for (final anchor in _anchor.allMatches(article)) {
      final slug = _programmePath.firstMatch(_attr(anchor.group(1)!, 'href') ?? '')?.group(1);
      if (slug == null || !seen.add(slug)) continue;
      final title = _attr(anchor.group(1)!, 'title') ?? _text(anchor.group(2)!);
      programmes.add(PsProgramme(slug: slug, title: title, posterUrl: _firstSrcset(article)));
      break;
    }
  }
  return programmes;
}

/// Video cards found in [html], in page order. Cards without a Dailymotion id or an episode link are skipped.
List<PsCard> parseCards(String html) {
  return [for (final match in _article.allMatches(html)) ?_card(match.group(0)!)];
}

/// Header facts and the first batch of episodes of a programme page.
///
/// Episodes sit in the element marked `data-program-grid`; the rest of the page lists suggestions from other
/// programmes. When the marker is missing only cards of [slug] itself are trusted.
PsShowPage parseShowPage(String html, String slug) {
  final marker = html.indexOf('data-program-grid');
  final List<PsCard> cards;
  if (marker >= 0) {
    final end = html.indexOf('</section>', marker);
    cards = parseCards(html.substring(marker, end < 0 ? html.length : end));
  } else {
    cards = [
      for (final card in parseCards(html))
        if (card.showSlug == slug) card,
    ];
  }
  return PsShowPage(
    title: _meta(html, 'property', 'og:title') ?? _documentTitle(html),
    summary: _meta(html, 'name', 'description'),
    backdropUrl: _meta(html, 'property', 'og:image'),
    cards: cards,
    paging: _paging(html),
  );
}

/// The HTML fragment inside the answer to a "load more" call, or null when the answer is not the expected one.
String? parseMoreTemplate(Object? body) {
  Object? data = body;
  if (body is String) {
    try {
      data = jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
  final template = (data is Map ? data['data'] : null);
  final html = template is Map ? template['template'] : null;
  return html is String ? html : null;
}

String decodeEntities(String text) {
  return text.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
    final entity = m.group(1)!;
    final code = entity.startsWith('#x')
        ? int.tryParse(entity.substring(2), radix: 16)
        : entity.startsWith('#')
        ? int.tryParse(entity.substring(1))
        : null;
    if (code != null) return code <= 0x10FFFF ? String.fromCharCode(code) : m.group(0)!;
    return _named[entity] ?? m.group(0)!;
  });
}

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'laquo': '«',
  'raquo': '»',
  'hellip': '…',
  'ndash': '–',
};

PsCard? _card(String article) {
  final videoId = dailymotionIdFromUrl(article);
  if (videoId == null) return null;
  for (final anchor in _anchor.allMatches(article)) {
    final path = _episodePath.firstMatch(_attr(anchor.group(1)!, 'href') ?? '');
    if (path == null) continue;
    final episodeSlug = path.group(2)!;
    final title = _attr(anchor.group(1)!, 'title') ?? _text(anchor.group(2)!);
    if (title.isEmpty) return null;
    return PsCard(
      videoId: videoId,
      title: title,
      showSlug: path.group(1)!,
      showTitle: _showTitle(article),
      airDate: _airDate(article),
      durationSeconds: _durationSeconds(article),
      theme: _theme(article),
      imageUrl: _largeImage.firstMatch(article)?.group(1) ?? 'https://www.dailymotion.com/thumbnail/video/$videoId',
      siteNumber: int.tryParse(_siteNumber.firstMatch(episodeSlug)?.group(1) ?? ''),
    );
  }
  return null;
}

/// The label above the title reads "Theme | Le" followed by the date; the line under it names the programme.
String? _theme(String article) {
  for (final p in _paragraph.allMatches(article)) {
    if (!p.group(1)!.contains('<time')) continue;
    final text = _text(p.group(1)!);
    final cut = text.indexOf('|');
    final theme = cut < 0 ? '' : text.substring(0, cut).trim();
    return theme.isEmpty ? null : theme;
  }
  return null;
}

String? _showTitle(String article) {
  String? last;
  for (final p in _paragraph.allMatches(article)) {
    final inner = p.group(1)!;
    if (inner.contains('<time') || inner.contains('<a')) continue;
    final text = _text(inner);
    if (text.isNotEmpty) last = text;
  }
  return last;
}

DateTime? _airDate(String article) {
  final m = _date.firstMatch(article);
  if (m == null) return null;
  return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// The caption on the thumbnail reads "1h12mn" or "52mn".
int? _durationSeconds(String article) {
  final picture = _picture.firstMatch(article)?.group(0);
  final m = picture == null ? null : _duration.firstMatch(_text(picture));
  if (m == null) return null;
  return (int.tryParse(m.group(1) ?? '') ?? 0) * 3600 + int.parse(m.group(2)!) * 60;
}

PsPaging? _paging(String html) {
  final section = RegExp(r'<[a-z]+\b[^>]*data-module="Program"[^>]*>').firstMatch(html)?.group(0);
  final script = RegExp(r'ajaxObject\s*=\s*(\{[^}]*\})').firstMatch(html)?.group(1);
  if (section == null || script == null) return null;
  final Object? ajax;
  try {
    ajax = jsonDecode(script);
  } on FormatException {
    return null;
  }
  if (ajax is! Map) return null;
  final termId = _attr(section, 'data-term-id');
  final limit = int.tryParse(_attr(section, 'data-limit') ?? '');
  final nonce = ajax['nonce'];
  final action = ajax['action'];
  if (termId == null || limit == null || limit < 1 || nonce is! String || action is! String) return null;
  return PsPaging(
    termId: termId,
    limit: limit,
    nonce: nonce,
    action: action,
    total: int.tryParse(_attr(section, 'data-total') ?? '') ?? 0,
  );
}

String? _meta(String html, String key, String value) {
  for (final tag in RegExp(r'<meta\b[^>]*>').allMatches(html)) {
    if (_attr(tag.group(0)!, key) == value) return _attr(tag.group(0)!, 'content');
  }
  return null;
}

String? _documentTitle(String html) {
  final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html)?.group(1);
  return title == null ? null : _text(title);
}

String? _firstSrcset(String article) {
  final srcset = RegExp(r'srcset="([^"]+)"').firstMatch(article)?.group(1);
  if (srcset == null) return null;
  final url = srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
  return url.startsWith('/') ? '$publicSenatOrigin$url' : url;
}

String? _attr(String tag, String name) {
  final m = RegExp('(?:^|\\s)$name\\s*=\\s*"([^"]*)"').firstMatch(tag);
  return m == null ? null : decodeEntities(m.group(1)!);
}

String _text(String html) => decodeEntities(html.replaceAll(_tag, ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();
