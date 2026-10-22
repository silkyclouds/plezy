import '../srg/srg_numbering.dart';
import '../srg/srg_unit.dart';
import 'rtsplay_images.dart';

const rtsPlaySourceId = 'rtsplay';

/// RTS Play: Swiss French. Rights that end in 2100 stand for "no end".
final rtsPlayUnit = SrgUnit(
  businessUnit: 'rts',
  sourceId: rtsPlaySourceId,
  name: 'RTS Play',
  language: 'fr',
  originalLabel: 'VF',
  texts: const SrgTexts(
    latest: 'Derniers épisodes',
    trending: 'Tendances',
    mostClicked: 'Les plus vus',
    soonExpiring: 'Bientôt retirés',
    season: 'Saison',
    extras: 'Bonus',
  ),
  numbering: SrgNumbering(episode: '[ée]pisode', season: 'saison'),
  images: const RtsPlayImages(),
  noEndYear: 2100,
  filmUmbrellaShows: const {'1800017', '1772596'},
  signedShowTitle: RegExp(r'\s-\s*Sign[ée]$', caseSensitive: false),
);
