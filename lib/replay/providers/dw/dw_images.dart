const dwImageHost = 'https://static.dw.com/image/';

/// DW's own marker for the size, left in every image address its API returns.
const _sizeMarker = r'${formatId}';

/// Width of each 16:9 format the image host serves; other format numbers answer 404.
const _landscape = [(600, 78), (601, 201), (602, 379), (603, 545), (604, 767), (605, 1199), (606, 1568), (607, 1920)];

/// The only portrait crops: 3:4, not the 2:3 of a poster.
const _portrait = [(701, 300), (702, 440)];

const _defaultLandscape = 604;

bool isDwImage(String reference) => reference.startsWith(dwImageHost);

/// The sized address template of an API image, or null when [staticUrl] is not one of DW's image addresses.
String? dwImageReference(Object? staticUrl) =>
    staticUrl is String && isDwImage(staticUrl) && staticUrl.contains(_sizeMarker) ? staticUrl : null;

/// Fills the size marker with the smallest format that covers [width], cropped to portrait for a tall box.
String dwImageUrl(String reference, {int? width, int? height}) {
  if (!reference.contains(_sizeMarker)) return reference;
  final portrait = width != null && height != null && height > width;
  final formats = portrait ? _portrait : _landscape;
  final format = width == null
      ? (portrait ? _portrait.first.$1 : _defaultLandscape)
      : formats.firstWhere((f) => f.$2 >= width, orElse: () => formats.last).$1;
  return reference.replaceAll(_sizeMarker, '$format');
}
