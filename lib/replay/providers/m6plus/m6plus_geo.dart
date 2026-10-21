/// A manifest host's refusal of the caller's country.
class M6plusGeoBlock {
  final String country;
  final List<String> allowed;

  const M6plusGeoBlock(this.country, this.allowed);

  String get message {
    final where = allowed.isEmpty ? '' : ' (réservé à ${allowed.join(', ')})';
    return 'Indisponible depuis votre pays ($country)$where.';
  }
}

final _blockedCountry = RegExp(r'Your country\s*:\s*([A-Z]{2})\s+is not allowed');
final _allowedCountries = RegExp(r'Allowed countries\s*:\s*([A-Z]{2}(?:\s*,\s*[A-Z]{2})*)');

/// Reads the plain-text 403 a manifest host sends to a country outside the rights zone.
/// The client address that follows in the body is never kept.
M6plusGeoBlock? m6plusParseGeoBlock(String body) {
  final country = _blockedCountry.firstMatch(body)?.group(1);
  if (country == null) return null;
  final allowed = _allowedCountries.firstMatch(body)?.group(1);
  return M6plusGeoBlock(country, allowed == null ? const [] : allowed.split(RegExp(r'\s*,\s*')));
}

/// The caller's country as far as it is known. The catalogue API never says; a refused manifest does.
class M6plusGeo {
  String? _country;

  String? get country => _country;

  void learn(String country) => _country = country;
}
