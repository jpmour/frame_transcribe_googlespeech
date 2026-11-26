import 'package:flutter/material.dart';

/// SPIKE ONLY: switch to record raw Frame audio, and a button to share the last recording.
class SpikeControls extends StatelessWidget {
  const SpikeControls({
    super.key,
    required this.recordRaw,
    required this.onRecordRawChanged,
    required this.hasRecording,
    required this.onShare,
  });

  final bool recordRaw;
  final ValueChanged<bool> onRecordRawChanged;
  final bool hasRecording;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(value: recordRaw, onChanged: onRecordRawChanged),
        const Expanded(child: Text('Record raw audio (spike)', style: TextStyle(fontSize: 13))),
        if (hasRecording) TextButton(onPressed: onShare, child: const Text('Share last recording')),
      ],
    );
  }
}
