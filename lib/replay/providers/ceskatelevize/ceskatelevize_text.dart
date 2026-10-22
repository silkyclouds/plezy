/// Text of a title or a label: non-breaking spaces become plain ones and runs of whitespace collapse.
String? ceskatelevizeLabel(Object? raw) {
  if (raw is! String) return null;
  final text = raw.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? null : text;
}

/// A synopsis: non-breaking spaces become plain ones and line breaks stay.
String? ceskatelevizeBody(Object? raw) {
  if (raw is! String) return null;
  final text = raw.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  return text.isEmpty ? null : text;
}

typedef CeskaTelevizeCredits = ({List<String> directors, List<String> cast});

final _labelStart = RegExp(r'\.\s+(?=\p{Lu}\p{L}*(?:\s\p{L}+)?:)', unicode: true);
final _nameSeparator = RegExp(r',\s*|\s+a\s+');

/// Reads the single credits line ("Režie: A. Scénář: B. Hrají: C, D a E.") into directors and cast.
CeskaTelevizeCredits ceskatelevizeCredits(String? line) {
  final directors = <String>[];
  final cast = <String>[];
  final text = ceskatelevizeBody(line);
  if (text == null) return (directors: directors, cast: cast);
  for (final part in text.split(_labelStart)) {
    final cut = part.indexOf(':');
    if (cut <= 0) continue;
    final label = part.substring(0, cut).trim().toLowerCase();
    final names = [
      for (final name in part.substring(cut + 1).split(_nameSeparator))
        if (name.replaceAll(RegExp(r'\.+$'), '').trim() case final clean when clean.isNotEmpty) clean,
    ];
    if (label == 'režie') directors.addAll(names);
    if (label.startsWith('hraj')) cast.addAll(names);
  }
  return (directors: directors, cast: cast);
}
