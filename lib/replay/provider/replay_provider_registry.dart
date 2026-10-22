import '../../utils/media_server_http_client.dart';
import '../providers/aljazeera/aljazeera_provider.dart';
import '../providers/arte/arte_provider.dart';
import '../providers/drtv/drtv_provider.dart';
import '../providers/dw/dw_provider.dart';
import '../providers/francetv/francetv_provider.dart';
import '../providers/lrt/lrt_provider.dart';
import '../providers/m6plus/m6plus_provider.dart';
import '../providers/nhkworld/nhkworld_provider.dart';
import '../providers/nrktv/nrktv_provider.dart';
import '../providers/pbs/pbs_provider.dart';
import '../providers/publicsenat/publicsenat_provider.dart';
import '../providers/rtbf/rtbf_provider.dart';
import '../providers/rtlplay/rtlplay_provider.dart';
import '../providers/rtsplay/rtsplay_provider.dart';
import '../providers/ruv/ruv_provider.dart';
import '../providers/svtplay/svtplay_provider.dart';
import '../providers/ted/ted_provider.dart';
import '../providers/tf1plus/tf1plus_provider.dart';
import '../providers/tvlocales/antennecentre_provider.dart';
import '../providers/tvlocales/canalzoom_provider.dart';
import '../providers/tvlocales/telemb_provider.dart';
import '../providers/tvlocales/telesambre_provider.dart';
import '../providers/tvlocales/tvcom_provider.dart';
import '../providers/tvlocales/tvlux_provider.dart';
import '../providers/urplay/urplay_provider.dart';
import '../providers/zdfmediathek/zdfmediathek_provider.dart';
import 'replay_provider.dart';
import 'replay_source_info.dart';

/// Every broadcaster the app can show, in the order offered to the user.
const replaySourceInfos = [
  ReplaySourceInfo(
    id: 'arte',
    name: 'ARTE',
    support: ReplayPlaybackSupport.clear,
    country: 'FR',
    languages: ['fr', 'de', 'en', 'es', 'it', 'pl'],
  ),
  ReplaySourceInfo(
    id: 'rtsplay',
    name: 'RTS Play',
    support: ReplayPlaybackSupport.clear,
    country: 'CH',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'auvio',
    name: 'Auvio',
    support: ReplayPlaybackSupport.partial,
    supportsAccount: true,
    country: 'BE',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'francetv',
    name: 'France.tv',
    support: ReplayPlaybackSupport.partial,
    country: 'FR',
    languages: ['fr'],
    // Rights are France and its overseas territories; a few titles carry a worldwide licence.
    availableIn: {'FR', 'GP', 'MQ', 'GF', 'RE', 'YT', 'PM', 'BL', 'MF', 'NC', 'PF', 'WF'},
  ),
  ReplaySourceInfo(
    id: 'publicsenat',
    name: 'Public Sénat',
    support: ReplayPlaybackSupport.browseOnly,
    country: 'FR',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'rtlplay',
    name: 'RTL Play',
    support: ReplayPlaybackSupport.partial,
    supportsAccount: true,
    country: 'BE',
    languages: ['fr'],
    availableIn: {'BE', 'LU'},
  ),
  ReplaySourceInfo(
    id: 'tf1plus',
    name: 'TF1+',
    support: ReplayPlaybackSupport.browseOnly,
    supportsAccount: true,
    country: 'FR',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'm6plus',
    name: 'M6+',
    support: ReplayPlaybackSupport.browseOnly,
    supportsAccount: true,
    country: 'FR',
    languages: ['fr'],
  ),
  ReplaySourceInfo(id: 'tvlux', name: 'TV Lux', support: ReplayPlaybackSupport.clear, country: 'BE', languages: ['fr']),
  ReplaySourceInfo(
    id: 'telemb',
    name: 'Télé MB',
    support: ReplayPlaybackSupport.clear,
    country: 'BE',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'telesambre',
    name: 'Télésambre',
    support: ReplayPlaybackSupport.clear,
    country: 'BE',
    languages: ['fr'],
  ),
  ReplaySourceInfo(id: 'tvcom', name: 'TVCOM', support: ReplayPlaybackSupport.clear, country: 'BE', languages: ['fr']),
  ReplaySourceInfo(
    id: 'antennecentre',
    name: 'Antenne Centre',
    support: ReplayPlaybackSupport.clear,
    country: 'BE',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'canalzoom',
    name: 'Canal Zoom',
    support: ReplayPlaybackSupport.clear,
    country: 'BE',
    languages: ['fr'],
  ),
  ReplaySourceInfo(
    id: 'aljazeera',
    name: 'Al Jazeera English',
    support: ReplayPlaybackSupport.clear,
    country: 'QA',
    languages: ['en'],
  ),
  ReplaySourceInfo(
    id: 'svtplay',
    name: 'SVT Play',
    support: ReplayPlaybackSupport.partial,
    country: 'SE',
    languages: ['sv'],
  ),
  ReplaySourceInfo(
    id: 'pbs',
    name: 'PBS',
    support: ReplayPlaybackSupport.partial,
    country: 'US',
    languages: ['en'],
  ),
  ReplaySourceInfo(
    id: 'ted',
    name: 'TED',
    support: ReplayPlaybackSupport.clear,
    country: replayInternational,
    languages: ['en'],
  ),
  ReplaySourceInfo(
    id: 'drtv',
    name: 'DR TV',
    support: ReplayPlaybackSupport.partial,
    country: 'DK',
    languages: ['da'],
  ),
  ReplaySourceInfo(
    id: 'dw',
    name: 'Deutsche Welle',
    support: ReplayPlaybackSupport.clear,
    country: 'DE',
    languages: ['en'],
  ),
  ReplaySourceInfo(
    id: 'nhkworld',
    name: 'NHK WORLD-JAPAN',
    support: ReplayPlaybackSupport.clear,
    country: 'JP',
    languages: ['en'],
  ),
  ReplaySourceInfo(
    id: 'zdfmediathek',
    name: 'ZDFmediathek',
    support: ReplayPlaybackSupport.partial,
    country: 'DE',
    languages: ['de'],
  ),
  ReplaySourceInfo(
    id: 'ruv',
    name: 'RÚV',
    support: ReplayPlaybackSupport.partial,
    country: 'IS',
    languages: ['is'],
  ),
  ReplaySourceInfo(
    id: 'urplay',
    name: 'UR Play',
    support: ReplayPlaybackSupport.clear,
    country: 'SE',
    languages: ['sv'],
  ),
  ReplaySourceInfo(
    id: 'nrktv',
    name: 'NRK TV',
    support: ReplayPlaybackSupport.partial,
    country: 'NO',
    languages: ['no'],
  ),
  ReplaySourceInfo(
    id: 'lrt',
    name: 'LRT',
    support: ReplayPlaybackSupport.clear,
    country: 'LT',
    languages: ['lt'],
  ),
];

ReplaySourceInfo? replaySourceInfo(String id) {
  for (final info in replaySourceInfos) {
    if (info.id == id) return info;
  }
  return null;
}

List<String> get replaySourceIds => [for (final info in replaySourceInfos) info.id];

String replaySourceName(String id) {
  for (final info in replaySourceInfos) {
    if (info.id == id) return info.name;
  }
  return id;
}

/// Builds the providers for the sources a connection enables. Unknown ids are skipped.
///
/// [deviceId] is stable for this installation: broadcasters that count devices per account would
/// otherwise see a new one at every launch.
Map<String, ReplayProvider> buildReplayProviders(
  Iterable<String> enabledSources,
  MediaServerHttpClient http, {
  String? deviceId,
}) {
  final providers = <String, ReplayProvider>{};
  for (final id in enabledSources) {
    final provider = switch (id) {
      'arte' => ArteProvider(http),
      'rtsplay' => RtsPlayProvider(http),
      'auvio' => RtbfProvider(http, deviceId: deviceId),
      'francetv' => FranceTvProvider(http),
      'publicsenat' => PublicSenatProvider(http),
      'rtlplay' => RtlPlayProvider(http),
      'tf1plus' => Tf1PlusProvider(http),
      'm6plus' => M6plusProvider(http),
      'tvlux' => TvLuxProvider(http),
      'telemb' => TeleMbProvider(http),
      'telesambre' => TelesambreProvider(http),
      'tvcom' => TvcomProvider(http),
      'antennecentre' => AntenneCentreProvider(http),
      'canalzoom' => CanalZoomProvider(http),
      'aljazeera' => AljazeeraProvider(http),
      'svtplay' => SvtPlayProvider(http),
      'pbs' => PbsProvider(http),
      'ted' => TedProvider(http),
      'drtv' => DrtvProvider(http),
      'dw' => DwProvider(http),
      'nhkworld' => NhkWorldProvider(http),
      'zdfmediathek' => ZdfMediathekProvider(http),
      'ruv' => RuvProvider(http),
      'urplay' => UrPlayProvider(http),
      'nrktv' => NrkTvProvider(http),
      'lrt' => LrtProvider(http),
      _ => null,
    };
    if (provider != null) providers[id] = provider;
  }
  return providers;
}
