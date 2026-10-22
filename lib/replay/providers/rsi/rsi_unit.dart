import '../srg/srg_numbering.dart';
import '../srg/srg_unit.dart';
import 'rsi_images.dart';

const rsiSourceId = 'rsi';

/// RSI Play: Swiss Italian programmes. Rights that end in 2099 stand for "no end".
final rsiUnit = SrgUnit(
  businessUnit: 'rsi',
  sourceId: rsiSourceId,
  name: 'RSI Play',
  language: 'it',
  originalLabel: 'IT',
  texts: const SrgTexts(
    latest: 'Ultimi episodi',
    trending: 'In tendenza',
    mostClicked: 'I più visti',
    soonExpiring: 'In scadenza',
    season: 'Stagione',
    extras: 'Extra',
  ),
  numbering: SrgNumbering(episode: 'episodio|ep\\.?|puntata', season: 'stagione', leadingLabel: true),
  images: const RsiImages(),
  noEndYear: 2099,
  filmUmbrellaShows: const {'702738'},
  signedShowTitle: RegExp(r'[\s-]+LIS$'),
  describedShowTitle: RegExp(r'\s*\(con audiodescrizione\)$', caseSensitive: false),
  hiddenTopics: const {'80', '90'},
);
