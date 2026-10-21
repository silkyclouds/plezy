/// Artwork lives on one host and is addressed by the `external_key` of a programme image.
const m6plusImageHost = 'https://images-fio.6play.fr/v2/images/';

const _posterRoles = ['portrait', 'cover', 'backdropTall'];
const _backdropRoles = ['vignette', 'jumbotron', 'backdropWide', 'mea', 'box'];
const _logoRoles = ['logo', 'fullColorLogo'];

bool isM6plusImage(String reference) => reference.startsWith(m6plusImageHost);

/// The resizer only accepts signed requests, so the original file is the only size an open client can ask for.
String m6plusImageUrl(String reference) => reference;

String? m6plusPoster(Object? images) => _pick(images, _posterRoles);

String? m6plusBackdrop(Object? images) => _pick(images, _backdropRoles);

String? m6plusLogo(Object? images) => _pick(images, _logoRoles);

/// The first image whose role comes earliest in [roles], as a ready-to-fetch reference.
String? _pick(Object? images, List<String> roles) {
  if (images is! List) return null;
  for (final role in roles) {
    for (final image in images.whereType<Map<String, dynamic>>()) {
      final key = image['external_key'];
      if (image['role'] == role && key != null && '$key'.isNotEmpty) return '$m6plusImageHost$key/raw';
    }
  }
  return null;
}
