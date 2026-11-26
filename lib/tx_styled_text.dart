import 'dart:convert';
import 'dart:typed_data';

import 'package:simple_frame_app/tx_msg.dart';

/// Message code for the coloured-lines text message (0x0b stays plain text).
const styledTextMsgCode = 0x0c;

/// One display line and the speaker whose colour it uses.
/// Speaker 0 is white: "no speaker information" (always used for Norwegian).
/// Speakers 1..5 map to colours set up in frame_app.lua.
class StyledLine {
  const StyledLine(this.text, {this.speaker = 0});

  final String text;
  final int speaker;
}

/// Sends the whole display as ONE message: text and colours always update together,
/// so the glasses never show half-updated lines.
///
/// Payload: [line count] then for each line [speaker byte][length byte][utf8 text].
/// The Lua parser is `parse_styled_text` in frame_app.lua.
class TxStyledText extends TxMsg {
  TxStyledText({required this.lines, super.msgCode = styledTextMsgCode});

  final List<StyledLine> lines;

  @override
  Uint8List pack() {
    final builder = BytesBuilder();
    builder.addByte(lines.length);
    for (final line in lines) {
      // a display line is about 40 characters, so one length byte is plenty; clamp to be safe
      final textBytes = utf8.encode(line.text);
      final clamped = textBytes.length > 255 ? textBytes.sublist(0, 255) : textBytes;
      builder.addByte(line.speaker & 0xFF);
      builder.addByte(clamped.length);
      builder.add(clamped);
    }
    return builder.toBytes();
  }
}
