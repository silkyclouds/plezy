import 'publicsenat_parser.dart';

const _uploads = '$publicSenatOrigin/app/uploads/';
const _dailymotionThumbnail = 'https://www.dailymotion.com/thumbnail/video/';

/// Covers are published at 301x450 with the full-size file next to them under the same name.
final _coverSize = RegExp(r'-301x450(\.\w+)$');

/// Whether a reference is a site upload or a Dailymotion thumbnail.
///
/// Thumbnail hosts hand out one token per size, so a larger file cannot be derived from a smaller URL and
/// the references stored on titles are already the large variant.
bool isPublicSenatImage(String reference) =>
    reference.startsWith(_uploads) ||
    reference.startsWith(_dailymotionThumbnail) ||
    RegExp(r'^https://s\d+\.dmcdn\.net/').hasMatch(reference);

String publicSenatImageUrl(String reference, {int? width}) {
  if (reference.startsWith(_uploads) && width != null && width > 301) {
    return reference.replaceFirstMapped(_coverSize, (m) => m.group(1)!);
  }
  return reference;
}
