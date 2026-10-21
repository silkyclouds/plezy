/// Auvio serves each picture in five fixed sizes only; any other size is a 404.
const _steps = [(180, 100), (370, 208), (770, 433), (1248, 702), (1920, 1080)];

const _imageHosts = {'static-content.rtbf.be', 'ds1.static.rtbf.be'};

/// Which `illustration` size is stored as the artwork reference: posters are tall, stills wide.
const rtbfPosterSize = 'l';
const rtbfStillSize = 'm';

final _sizeFolder = RegExp('/(?:${_steps.map((s) => '${s.$1}x(?:${s.$2}|auto)').join('|')})/');

bool isRtbfImage(String reference) {
  final host = Uri.tryParse(reference)?.host;
  return host != null && _imageHosts.contains(host);
}

/// One size out of an `illustration` object (`xs`, `s`, `m`, `l`, `xl`), or null when there is none.
String? rtbfIllustration(Object? illustration, String size) {
  if (illustration is! Map) return null;
  final url = illustration[size];
  return url is String && url.isNotEmpty ? url : null;
}

/// Swaps the size folder of [reference] for the smallest fixed step that is at least [width] wide.
/// Pictures without a size folder, such as programme backgrounds, come back unchanged.
String rtbfImageUrl(String reference, {int? width, int? height}) {
  final wanted = width ?? (height == null ? null : (height * 16 / 9).round());
  if (wanted == null) return reference;
  final match = _sizeFolder.firstMatch(reference);
  if (match == null) return reference;
  final step = _steps.firstWhere((s) => s.$1 >= wanted, orElse: () => _steps.last);
  final isAuto = match.group(0)!.endsWith('xauto/');
  final folder = isAuto ? '/${step.$1}xauto/' : '/${step.$1}x${step.$2}/';
  return reference.replaceRange(match.start, match.end, folder);
}
