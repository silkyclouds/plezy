import 'dart:convert';

/// The structured data nfb.ca embeds in its pages. Every reader returns an empty result for markup it does not
/// recognise, so a redesign of the site shows up as missing titles rather than as a crash.

final _jsonLdScript = RegExp(
  r'<script[^>]*type\s*=\s*"application/ld\+json"[^>]*>(.*?)</script>',
  caseSensitive: false,
  dotAll: true,
);

/// Every JSON-LD object of a page. Blocks that are not valid JSON are skipped.
List<Map<String, dynamic>> nfbJsonLd(String html) {
  final blocks = <Map<String, dynamic>>[];
  for (final match in _jsonLdScript.allMatches(html)) {
    final Object? decoded;
    try {
      decoded = jsonDecode(match.group(1)!);
    } on FormatException {
      continue;
    }
    if (decoded is Map<String, dynamic>) blocks.add(decoded);
    if (decoded is List) blocks.addAll(decoded.whereType<Map<String, dynamic>>());
  }
  return blocks;
}

/// Whether a JSON-LD `@type`, a string or a list of strings, names [type].
bool nfbHasType(Map<String, dynamic> block, String type) {
  final declared = block['@type'];
  return declared == type || (declared is List && declared.contains(type));
}

/// The tracking data layer of a film or series page: plain fields, and the English categories of the work.
class NfbDataLayer {
  final Map<String, String> fields;
  final List<String> categories;

  const NfbDataLayer(this.fields, this.categories);

  static const empty = NfbDataLayer({}, []);

  int? get year => int.tryParse(fields['nfb_version_year'] ?? '');

  /// Exact running time; the structured data only has it rounded to minutes.
  int? get durationSeconds {
    final seconds = int.tryParse(fields['nfb_version_duration'] ?? '');
    return seconds == null || seconds <= 0 ? null : seconds;
  }
}

final _dataLayerPush = RegExp(r'dataLayer\.push\(\{(.*?)\}\);', dotAll: true);
final _stringField = RegExp(r"'([a-z_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'");
final _englishCategories = RegExp(r"'nfb_version_category'\s*:\s*\{\s*'en'\s*:\s*\[(.*?)\]", dotAll: true);
final _quoted = RegExp(r'''\x27((?:[^\x27\\]|\\.)*)\x27|"((?:[^"\\]|\\.)*)"''');

NfbDataLayer nfbDataLayer(String html) {
  for (final push in _dataLayerPush.allMatches(html)) {
    final body = push.group(1)!;
    if (!body.contains('nfb_version')) continue;
    final fields = {for (final m in _stringField.allMatches(body)) m.group(1)!: _unescape(m.group(2)!)};
    final list = _englishCategories.firstMatch(body)?.group(1) ?? '';
    final categories = [
      for (final m in _quoted.allMatches(list))
        if (_unescape(m.group(1) ?? m.group(2)!).trim().isNotEmpty) _unescape(m.group(1) ?? m.group(2)!).trim(),
    ];
    return NfbDataLayer(fields, categories);
  }
  return NfbDataLayer.empty;
}

String _unescape(String raw) => raw.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);

final _playerOptions = RegExp(r'IFRAME_OPTIONS\s*=\s*(\{.*\})');

/// The player configuration the embed page hands to its script, or null when the page has none.
Map<String, dynamic>? nfbPlayerOptions(String html) {
  final raw = _playerOptions.firstMatch(html)?.group(1);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// What the embed page says instead of a player: the id of its message element and the text, plus the purchase
/// options it offers.
typedef NfbOverlayNotice = ({String? messageId, String? message, Set<String> offers});

final _overlayMessage = RegExp(r'id="(MESSAGE_[A-Z_]+)"[^>]*>\s*([^<]*?)\s*<');
final _overlayOffers = RegExp(r'data-keys="([^"]*)"');

NfbOverlayNotice nfbOverlayNotice(String html) {
  final message = _overlayMessage.firstMatch(html);
  final offers = _overlayOffers.firstMatch(html)?.group(1) ?? '';
  return (
    messageId: message?.group(1),
    message: message == null || message.group(2)!.isEmpty ? null : message.group(2),
    offers: {
      for (final key in offers.split(','))
        if (key.trim().isNotEmpty) key.trim(),
    },
  );
}
