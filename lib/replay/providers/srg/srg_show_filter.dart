import 'srg_unit.dart';

/// Drops the accessibility copies of shows from a list of show objects.
///
/// Sign-language copies are always dropped. An audio-described copy is dropped when its original is in the same
/// list, so a show that exists only in the described edition stays reachable.
List<Map<String, dynamic>> srgVisibleShows(SrgUnit unit, List<Map<String, dynamic>> shows) {
  final signed = unit.signedShowTitle;
  final described = unit.describedShowTitle;
  if (signed == null && described == null) return shows;

  final originals = <String>{
    for (final show in shows)
      if (!_matches(signed, show) && !_matches(described, show)) _key(_title(show)),
  };
  return [
    for (final show in shows)
      if (!_matches(signed, show) &&
          !(_matches(described, show) && originals.contains(_key(_original(described!, show)))))
        show,
  ];
}

bool _matches(RegExp? pattern, Map<String, dynamic> show) => pattern != null && pattern.hasMatch(_title(show));

String _title(Map<String, dynamic> show) => (show['title'] as String? ?? '').trim();

String _original(RegExp described, Map<String, dynamic> show) => _title(show).replaceFirst(described, '');

String _key(String title) => title.trim().toLowerCase();
