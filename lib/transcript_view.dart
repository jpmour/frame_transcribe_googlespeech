import 'package:flutter/material.dart';

import 'utterance.dart';

/// Scrolling list of finished utterances with the current interim text underneath.
class TranscriptView extends StatelessWidget {
  const TranscriptView({
    super.key,
    required this.transcript,
    required this.partialResult,
    required this.transcriptController,
    required this.partialController,
  });

  static const _textStyle = TextStyle(fontSize: 24);

  final List<Utterance> transcript;
  final String partialResult;
  final ScrollController transcriptController;
  final ScrollController partialController;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: ListView.builder(
            controller: transcriptController,
            itemCount: transcript.length,
            itemBuilder: (context, index) => Text(transcript[index].text, style: _textStyle),
          ),
        ),
        const Divider(),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _textStyle.fontSize! * 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              controller: partialController,
              child: Text(partialResult, style: _textStyle),
            ),
          ),
        ),
      ],
    );
  }
}
