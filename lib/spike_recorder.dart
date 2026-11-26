import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_frame_app/rx/audio.dart';

/// SPIKE ONLY (branch spike/colour-pass): records the raw 8 kHz Frame audio to a WAV file so the
/// colour-pass experiments can run on real glasses audio. Not merged unless the spike says "build".
///
/// It listens to the same broadcast audio stream as the live recogniser, so it cannot slow the
/// captions down. The file is written when the audio stream ends (double-tap to pause).
class SpikeRecorder {
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subs;
  File? lastFile;

  bool get hasRecording => lastFile != null;

  void start(Stream<Uint8List> audio, {required void Function() onSaved}) {
    _pcm.clear();
    _subs?.cancel();
    _subs = audio.listen(_pcm.add, onDone: () async {
      await _save();
      onSaved();
    });
  }

  Future<void> _save() async {
    _subs = null;
    if (_pcm.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().split('.').first.replaceAll(':', '-');
    final file = File('${dir.path}/frame_$stamp.wav');
    await file.writeAsBytes(RxAudio.toWavBytes(pcmData: _pcm.takeBytes()));
    lastFile = file;
  }

  Future<void> shareLast() async {
    if (lastFile != null) {
      await Share.shareXFiles([XFile(lastFile!.path)]);
    }
  }
}
