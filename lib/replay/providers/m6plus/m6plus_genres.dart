/// French labels for the genre slugs the catalogue uses. Slugs lose their accents, so common ones are spelled out.
const _labels = {
  'documentaire': 'Documentaire',
  'telefilm-drame': 'Téléfilm dramatique',
  'telefilm-romance': 'Téléfilm romantique',
  'telefilm-frissons': 'Téléfilm à suspense',
  'telefilm_noel': 'Téléfilm de Noël',
  'telefilm': 'Téléfilm',
  'divertissement': 'Divertissement',
  'divertissements': 'Divertissement',
  'spectacle': 'Spectacle',
  'series-dramatiques': 'Série dramatique',
  'serie-dramatique': 'Série dramatique',
  'serie-policiere': 'Série policière',
  'serie-fantastique': 'Série fantastique',
  'serie-realite': 'Télé-réalité',
  'series-realite': 'Télé-réalité',
  'serie-humour': 'Série humoristique',
  'serie-romantique': 'Série romantique',
  'series-fictions': 'Série',
  'film': 'Film',
  'long-metrage': 'Film',
  'cinema': 'Cinéma',
  'kids': 'Jeunesse',
  'teens': 'Adolescents',
  'tous-petits': 'Tout-petits',
  'action': 'Action',
  'aventure': 'Aventure',
  'comedie': 'Comédie',
  'drame': 'Drame',
  'cuisine': 'Cuisine',
  'sport': 'Sport',
  'musique': 'Musique',
  'magazine': 'Magazine',
  'magazine-dinformation': "Magazine d'information",
  'magazine-d-information': "Magazine d'information",
  'info': 'Info',
  'infos': 'Info',
  'info-et-societe': 'Info et société',
  'talkshow': 'Talk-show',
  'telenovela': 'Telenovela',
  'competition': 'Compétition',
  'debat': 'Débat',
  'humour': 'Humour',
  'maison': 'Maison',
  'immobilier': 'Immobilier',
  'mode-et-beaute': 'Mode et beauté',
  'docu-realite': 'Docu-réalité',
};

/// A readable genre for a catalogue slug; unknown slugs are spaced out rather than dropped.
List<String> m6plusGenres(String? slug) {
  if (slug == null || slug.isEmpty) return const [];
  final known = _labels[slug];
  if (known != null) return [known];
  final spaced = slug.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  return spaced.isEmpty ? const [] : [spaced[0].toUpperCase() + spaced.substring(1)];
}
