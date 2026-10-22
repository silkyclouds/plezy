import '../../model/replay_title.dart';

/// Category id prefix of the thematic pages (`rubrik/filme`).
const ardRubrikPrefix = 'rubrik/';

/// Category id prefix of a channel's own landing page (`kanal/br`).
const ardChannelPrefix = 'kanal/';

/// The thematic pages of "Alle Rubriken", then the channels. ARTE is left out: it has its own provider.
const ardCategories = [
  ReplayCategory(id: '${ardRubrikPrefix}filme', title: 'Filme'),
  ReplayCategory(id: '${ardRubrikPrefix}serien', title: 'Serien'),
  ReplayCategory(id: '${ardRubrikPrefix}dokus', title: 'Dokus'),
  ReplayCategory(id: '${ardRubrikPrefix}tagesschau', title: 'tagesschau & Information'),
  ReplayCategory(id: '${ardRubrikPrefix}sport', title: 'Sportschau'),
  ReplayCategory(id: '${ardRubrikPrefix}kinderfamilie', title: 'Kinder & Familie'),
  ReplayCategory(id: '${ardRubrikPrefix}shows_comedy', title: 'Shows & Comedy'),
  ReplayCategory(id: '${ardRubrikPrefix}kultur', title: 'Kultur'),
  ReplayCategory(id: '${ardRubrikPrefix}barrierefrei', title: 'Barrierefrei'),
  ReplayCategory(id: '${ardRubrikPrefix}reisen', title: 'Reisen'),
  ReplayCategory(id: '${ardRubrikPrefix}food', title: 'Food'),
  ReplayCategory(id: '${ardRubrikPrefix}gesundheit', title: 'Gesundheit'),
  ReplayCategory(id: '${ardRubrikPrefix}geschichte', title: 'Geschichte'),
  ReplayCategory(id: '${ardRubrikPrefix}retro', title: 'Retro'),
  ReplayCategory(id: '${ardRubrikPrefix}natur', title: 'Natur'),
  ReplayCategory(id: '${ardRubrikPrefix}wissen', title: 'Wissen'),
  ReplayCategory(id: '${ardRubrikPrefix}klassik', title: 'Klassik'),
  ReplayCategory(id: '${ardRubrikPrefix}investigativ', title: 'Investigativ'),
  ReplayCategory(id: '${ardRubrikPrefix}lernen', title: 'Lernen'),
  ReplayCategory(id: '${ardChannelPrefix}daserste', title: 'Das Erste'),
  ReplayCategory(id: '${ardChannelPrefix}br', title: 'BR'),
  ReplayCategory(id: '${ardChannelPrefix}hr', title: 'hr'),
  ReplayCategory(id: '${ardChannelPrefix}mdr', title: 'MDR'),
  ReplayCategory(id: '${ardChannelPrefix}ndr', title: 'NDR'),
  ReplayCategory(id: '${ardChannelPrefix}radiobremen', title: 'Radio Bremen'),
  ReplayCategory(id: '${ardChannelPrefix}rbb', title: 'rbb'),
  ReplayCategory(id: '${ardChannelPrefix}sr', title: 'SR'),
  ReplayCategory(id: '${ardChannelPrefix}swr', title: 'SWR'),
  ReplayCategory(id: '${ardChannelPrefix}wdr', title: 'WDR'),
  ReplayCategory(id: '${ardChannelPrefix}one', title: 'ONE'),
  ReplayCategory(id: '${ardChannelPrefix}tagesschau24', title: 'tagesschau24'),
  ReplayCategory(id: '${ardChannelPrefix}alpha', title: 'ARD alpha'),
  ReplayCategory(id: '${ardChannelPrefix}phoenix', title: 'phoenix'),
  ReplayCategory(id: '${ardChannelPrefix}kika', title: 'KiKA'),
  ReplayCategory(id: '${ardChannelPrefix}3sat', title: '3sat'),
];
