import '../../../utils/media_server_http_client.dart';
import 'rtbf_bff.dart';
import 'rtbf_exposure.dart';
import 'rtbf_http.dart';

/// Both Auvio back ends: the website's catalogue API and the Red Bee playback platform.
class RtbfApi {
  final RtbfBff bff;
  final RtbfExposure exposure;

  /// The identifying transport shared by every host, also used for account sign-in.
  final RtbfHttp http;

  RtbfApi._(this.http, this.bff, this.exposure);

  /// [deviceId] names this install to the playback platform; a random one is made when omitted.
  factory RtbfApi(MediaServerHttpClient client, {String? deviceId, DateTime Function()? now}) {
    final clock = now ?? DateTime.now;
    final http = RtbfHttp(client);
    return RtbfApi._(http, RtbfBff(http, clock), RtbfExposure(http, clock, deviceId: deviceId));
  }
}
