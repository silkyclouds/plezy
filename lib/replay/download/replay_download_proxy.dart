import 'dart:async';
import 'dart:io';

import '../../utils/app_logger.dart';

/// Turns a broadcaster's HLS stream into one progressive MP4 that the app's ordinary download manager can fetch.
///
/// The manager downloads a single file from a URL, while catch-up streams are playlists of segments. This serves each
/// registered stream on the loopback interface and fills the response from `ffmpeg`, which copies the segments into a
/// fragmented MP4 without re-encoding. Nothing is stored here: the bytes go straight to the download.
class ReplayDownloadProxy {
  final String? _ffmpegPath;
  HttpServer? _server;
  final Map<String, _Source> _sources = {};
  int _counter = 0;

  /// [ffmpegPath] overrides the lookup on `PATH`, which tests and unusual installs need.
  ReplayDownloadProxy({String? ffmpegPath}) : _ffmpegPath = ffmpegPath ?? _findOnPath('ffmpeg');

  /// A converter on a machine without `ffmpeg`: it never serves anything.
  ReplayDownloadProxy.unavailable() : _ffmpegPath = null;

  /// Whether a download can be produced on this machine.
  bool get isAvailable => _ffmpegPath != null;

  /// A loopback URL that streams [source] as an MP4, or null when `ffmpeg` is missing.
  Future<Uri?> serve(Uri source, {Map<String, String> headers = const {}}) async {
    if (_ffmpegPath == null) return null;
    final server = _server ??= await _bind();
    final id = '${_counter++}';
    _sources[id] = _Source(source, headers);
    return Uri(scheme: 'http', host: server.address.address, port: server.port, path: '/dl/$id.mp4');
  }

  Future<HttpServer> _bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final match = RegExp(r'^/dl/(\d+)\.mp4$').firstMatch(request.uri.path);
    final source = match == null ? null : _sources[match.group(1)];
    if (source == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final process = await Process.start(
      _ffmpegPath!,
      _arguments(source),
      environment: _cleanEnvironment(),
      includeParentEnvironment: false,
    );
    // ffmpeg's error log is only worth keeping when the copy fails.
    final errors = StringBuffer();
    unawaited(process.stderr.transform(const SystemEncoding().decoder).forEach(errors.write));
    response.headers.contentType = ContentType('video', 'mp4');
    response.bufferOutput = false;
    unawaited(response.done.catchError((Object _) {}).whenComplete(process.kill));
    try {
      await response.addStream(process.stdout);
    } on SocketException {
      process.kill();
      return;
    }
    if (await process.exitCode == 0) {
      await response.close();
    } else {
      appLogger.w('Catch-up download failed: $errors');
      // Closing normally would hand the downloader a truncated file as if it were complete; an error aborts the transfer.
      response.addError(const HttpException('conversion failed'));
      await response.close().catchError((Object _) {});
    }
  }

  /// The app runs with its own bundled libraries first on the loader path; the system's ffmpeg must not see them or it
  /// fails on symbols they do not provide.
  static Map<String, String> _cleanEnvironment() => {
    for (final entry in Platform.environment.entries)
      if (!_loaderVariables.contains(entry.key)) entry.key: entry.value,
  };

  static const _loaderVariables = {'LD_LIBRARY_PATH', 'LD_PRELOAD', 'DYLD_LIBRARY_PATH'};

  List<String> _arguments(_Source source) => [
    '-nostdin',
    '-hide_banner',
    '-loglevel',
    'error',
    if (source.headers.isNotEmpty) ...[
      '-headers',
      source.headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join(),
    ],
    '-i',
    source.url.toString(),
    '-c',
    'copy',
    '-bsf:a',
    'aac_adtstoasc',
    '-movflags',
    'frag_keyframe+empty_moov+default_base_moof',
    '-f',
    'mp4',
    'pipe:1',
  ];

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _sources.clear();
  }

  static String? _findOnPath(String name) {
    for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
      final candidate = File('$dir${Platform.pathSeparator}$name${Platform.isWindows ? '.exe' : ''}');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }
}

class _Source {
  final Uri url;
  final Map<String, String> headers;

  const _Source(this.url, this.headers);
}
