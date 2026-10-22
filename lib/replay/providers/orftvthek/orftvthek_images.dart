import 'orftvthek_json.dart';

const _assetHost = 'https://api-tvthek.orf.at/assets/';

// ORF serves four fixed widths under fixed names; there is no resize parameter.
const _variants = [(130, 'small'), (330, 'list'), (660, 'player')];
const _largest = 'highlight_teaser';
const _defaultVariant = 'player';
final _variantSuffix = RegExp(r'_(?:small|list|player|legacy|highlight_teaser)\.jpg$');

/// Whether [reference] is an artwork address this provider produced.
bool isOrfImage(String reference) => reference.startsWith(_assetHost);

/// The variant of [reference] whose width covers [width]. A reference without a variant name is returned as is.
String orfImageUrl(String reference, {int? width, int? height}) {
  if (!_variantSuffix.hasMatch(reference)) return reference;
  final wanted = width ?? 480;
  final variant = _variants.where((v) => v.$1 >= wanted).map((v) => v.$2).firstOrNull ?? _largest;
  return reference.replaceFirst(_variantSuffix, '_$variant.jpg');
}

/// Portrait and landscape artwork of one item, read from the image objects ORF embeds in its lists.
///
/// ORF fills missing portraits with one generic picture per show and flags it `is_fallback`; that picture is not
/// returned as a poster so the landscape image is used instead.
({String? poster, String? backdrop}) orfArtwork(Map<String, dynamic> item) {
  final embedded = orfMap(item['_embedded']);
  return (
    poster: _reference(embedded, const ['image2x3', 'image2x3_with_logo'], allowFallback: false),
    backdrop: _reference(embedded, const ['image', 'image16x9_with_logo', 'image12x5'], allowFallback: true),
  );
}

String? _reference(Map<String, dynamic>? embedded, List<String> names, {required bool allowFallback}) {
  if (embedded == null) return null;
  for (final pass in [false, true]) {
    if (pass && !allowFallback) break;
    for (final name in names) {
      final image = orfMap(embedded[name]);
      if (image == null || (image['is_fallback'] == true) != pass) continue;
      final url = _anyUrl(orfMap(image['public_urls']));
      if (url != null) return url;
    }
  }
  return null;
}

String? _anyUrl(Map<String, dynamic>? urls) {
  if (urls == null) return null;
  for (final variant in [_defaultVariant, 'list', 'small', _largest]) {
    final url = orfString(orfMap(urls[variant])?['url']);
    if (url != null && isOrfImage(url)) return url;
  }
  return null;
}
