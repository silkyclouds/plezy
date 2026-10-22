const _host = 'img.rtve.es';
const _largest = 1900;
const _defaultWidth = 640;

/// Artwork fields of a programme that the resizer knows. Each is a different crop of the programme's pictures.
const rtvePosterFields = ['imgPoster', 'imgPoster2'];
const rtveBackdropFields = ['imgPortada', 'imgPortada2', 'imgCol3'];

bool isRtveImage(String reference) => Uri.tryParse(reference)?.host == _host;

/// Reference to one crop of a programme's artwork, or null when RTVE has no picture in any of [fields].
///
/// The resizer addresses a picture by programme and field name, so the reference holds both and no size.
String? rtveProgramImage(Map<String, dynamic> program, List<String> fields) {
  for (final field in fields) {
    final value = program[field];
    if (value is String && value.trim().isNotEmpty) return 'https://$_host/p/${program['id']}?imgProgApi=$field';
  }
  return null;
}

/// Reference to a video's frame. The resizer finds it from the video id alone.
String rtveVideoImage(String videoId) => 'https://$_host/v/$videoId';

/// Reference to a programme logo (a PNG with transparency), or null.
String? rtveLogo(Map<String, dynamic> program) => rtveProgramImage(program, const ['logo']);

/// Gives [reference] the size the caller asked for. Resizable references get a `w` parameter, anything else (a
/// picture RTVE only serves at full size) is returned untouched.
String rtveImageUrl(String reference, {int? width, int? height}) {
  final uri = Uri.tryParse(reference);
  if (uri == null || uri.host != _host) return reference;
  if (!uri.path.startsWith('/p/') && !uri.path.startsWith('/v/')) return reference;
  final wanted = (width ?? _defaultWidth).clamp(64, _largest);
  return uri.replace(queryParameters: {...uri.queryParameters, 'w': '$wanted'}).toString();
}
