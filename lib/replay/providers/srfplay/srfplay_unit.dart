import '../srg/srg_numbering.dart';
import '../srg/srg_unit.dart';
import 'srfplay_images.dart';

const srfPlaySourceId = 'srfplay';

/// SRF Play: Swiss German programmes with Standard German metadata. Rights that end in 2099 stand for "no end".
final srfPlayUnit = SrgUnit(
  businessUnit: 'srf',
  sourceId: srfPlaySourceId,
  name: 'SRF Play',
  language: 'de',
  originalLabel: 'DE',
  texts: const SrgTexts(
    latest: 'Neueste Folgen',
    trending: 'Im Trend',
    mostClicked: 'Meistgesehen',
    soonExpiring: 'Bald nicht mehr verfügbar',
    season: 'Staffel',
    extras: 'Bonus',
  ),
  numbering: SrgNumbering(episode: 'folge', season: 'staffel', leadingLabel: true),
  images: const SrfPlayImages(),
  noEndYear: 2099,
  filmUmbrellaShows: const {'c5f011e6-e1d0-0001-94b7-cb557740172f', 'a5430171-dbcd-4880-925e-ffcc621cac29'},
  signedShowTitle: RegExp(r'\s+in Gebärdensprache$', caseSensitive: false),
  describedShowTitle: RegExp(r'\s+mit Audiodeskription$', caseSensitive: false),
  hiddenTopics: const {'593eb926-d892-41ba-8b1f-eccbcfd7f15f', '4acf86dd-7ff7-45d3-baf8-33375340d976'},
);
