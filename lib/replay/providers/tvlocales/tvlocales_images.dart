import 'tvlocales_station.dart';
import 'tvlocales_text.dart';

const freecasterPosterHost = 'tvlocales-posters.freecaster.com';
const _sizePlaceholder = '%{SIZE}';

/// Sizes Freecaster renders posters in, smallest first.
const _posterSizes = [(320, 180), (426, 240), (640, 360), (854, 480), (1280, 720), (1920, 1080)];

final _imageTag = RegExp(r'<img\s[^>]*?\bsrc="([^"]+)"');
final _hostAndPath = RegExp(r'^https?://([^/?#]+)(/[^?#]*)?');

/// An image address from a page as an absolute URL, or null when the page gave none.
String? absoluteUrl(Uri base, String? reference) {
  if (reference == null || reference.trim().isEmpty) return null;
  return base.resolve(decodeEntities(reference.trim())).toString();
}

/// The first `<img>` of a piece of markup as an absolute URL, or null when it has none.
String? firstImageUrl(Uri base, String html) => absoluteUrl(base, _imageTag.firstMatch(html)?.group(1));

/// Whether [reference] is an image of [station]: a file on its site, or a poster in its Freecaster folder.
bool ownsTvLocalesImage(TvLocalesStation station, String reference) {
  final match = _hostAndPath.firstMatch(reference);
  if (match == null) return false;
  final host = match.group(1)!;
  if (host == station.host) return true;
  return host == freecasterPosterHost && (match.group(2) ?? '').startsWith('/videos/${station.customer}/');
}

/// Fills the size placeholder of a Freecaster poster template with the smallest size that covers [width].
/// Addresses without a placeholder are returned unchanged.
String tvLocalesImageUrl(String reference, {int? width}) {
  if (!reference.contains(_sizePlaceholder)) return reference;
  final wanted = width ?? 640;
  final size = _posterSizes.firstWhere((s) => s.$1 >= wanted, orElse: () => _posterSizes.last);
  return reference.replaceAll(_sizePlaceholder, '${size.$1}x${size.$2}');
}
