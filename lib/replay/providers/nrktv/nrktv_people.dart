const _castRoles = {'skuespiller', 'skuespillere', 'programleder', 'gjest', 'gjester', 'deltaker', 'deltakere'};
const _directorRoles = {'regissør', 'regi'};

/// Cast and directors from NRK's contributor list. Episodes give one `{name, role}` per person, programme pages one
/// `{role, name: [..]}` per role.
({List<String> cast, List<String> directors}) nrkPeople(Object? contributors) {
  final cast = <String>[];
  final directors = <String>[];
  if (contributors is List) {
    for (final entry in contributors.whereType<Map>()) {
      final role = (entry['role'] as String? ?? '').trim().toLowerCase();
      final names = switch (entry['name']) {
        final String single => [single],
        final List many => many.whereType<String>().toList(),
        _ => const <String>[],
      };
      if (_castRoles.contains(role)) cast.addAll(names);
      if (_directorRoles.contains(role)) directors.addAll(names);
    }
  }
  return (cast: cast, directors: directors);
}
