import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'microphone_recorder.dart';

/// Records through PulseAudio or PipeWire command line tools, which every Linux desktop and handheld
/// image ships. `parecord` is tried first, then `pw-record`.
class PulseMicrophoneRecorder implements MicrophoneRecorder {
  static const _tools = {
    'parecord': ['--rate=16000', '--channels=1', '--format=s16le', '--file-format=wav'],
    'pw-record': ['--rate', '16000', '--channels', '1', '--format', 's16'],
  };

  Process? _process;
  File? _file;

  @override
  Future<bool> isAvailable() async => await _firstTool() != null;

  Future<String?> _firstTool() async {
    for (final tool in _tools.keys) {
      final found = await Process.run('which', [tool]);
      if (found.exitCode == 0) return tool;
    }
    return null;
  }

  @override
  Future<void> start() async {
    final tool = await _firstTool();
    if (tool == null) throw const MicrophoneException('No recorder (parecord or pw-record) is installed');
    final dir = await Directory.systemTemp.createTemp('plezy_voice_');
    final file = File('${dir.path}/speech.wav');
    final process = await Process.start(tool, [..._tools[tool]!, file.path]);
    _file = file;
    _process = process;
    // A recorder that dies at once has no microphone to use.
    final early = await process.exitCode.timeout(const Duration(milliseconds: 400), onTimeout: () => -1);
    if (early != -1) {
      await _discard();
      throw const MicrophoneException('The microphone could not be opened');
    }
  }

  @override
  Future<Uint8List> stop() async {
    final process = _process;
    final file = _file;
    if (process == null || file == null) throw const MicrophoneException('Not recording');
    process.kill(ProcessSignal.sigint);
    await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        process.kill(ProcessSignal.sigterm);
        return -1;
      },
    );
    final bytes = await file.readAsBytes();
    await _discard();
    return bytes;
  }

  @override
  Future<void> cancel() async {
    _process?.kill(ProcessSignal.sigterm);
    await _discard();
  }

  Future<void> _discard() async {
    final file = _file;
    _process = null;
    _file = null;
    if (file != null && await file.parent.exists()) await file.parent.delete(recursive: true);
  }
}
