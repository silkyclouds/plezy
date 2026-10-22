import 'lrt_refs.dart';

const lrtImageHost = '$lrtOrigin/img/';

const _placeholder = '{WxH}';

/// The picture server answers only these sizes; any other size is a 404 page.
const _sizes = [(282, 158), (393, 221), (615, 345), (756, 425), (1287, 836)];

final _sizedSuffix = RegExp(r'-\d+x\d+(\.[A-Za-z0-9]+)$');

bool isLrtImage(String reference) => reference.startsWith(lrtImageHost);

/// An absolute picture URL with a `{WxH}` placeholder, from a sized URL, a placeholder URL or a bare path.
/// Pictures outside the site's `/img/` tree are not ours to resize, so they give null.
String? lrtImageTemplate(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  final absolute = trimmed.startsWith('/') ? '$lrtOrigin$trimmed' : trimmed;
  if (!isLrtImage(absolute)) return null;
  if (absolute.contains(_placeholder)) return absolute;
  return absolute.replaceFirstMapped(_sizedSuffix, (m) => '-$_placeholder${m.group(1)}');
}

/// The template of a page payload picture, which is given as a path prefix and an extension.
String? lrtImageTemplateFromParts(Object? prefix, Object? postfix) {
  if (prefix is! String || postfix is! String || prefix.isEmpty) return null;
  return lrtImageTemplate('$prefix$_placeholder$postfix');
}

/// Fills the placeholder with the smallest allowed size that is at least [width] wide, or [height] high at the
/// pictures' 1.5 ratio. A reference that carries no placeholder is returned unchanged.
String lrtImageUrl(String template, {int? width, int? height}) {
  if (!template.contains(_placeholder)) return template;
  final wanted = [width ?? 0, ((height ?? 0) * 1.5).round()].reduce((a, b) => a > b ? a : b);
  final size = _sizes.firstWhere((s) => s.$1 >= (wanted == 0 ? 615 : wanted), orElse: () => _sizes.last);
  return template.replaceAll(_placeholder, '${size.$1}x${size.$2}');
}
