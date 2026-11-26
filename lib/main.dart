import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_speech/endless_streaming_service_v2.dart';
import 'package:google_speech/generated/google/cloud/speech/v2/cloud_speech.pb.dart';
import 'package:google_speech/google_speech.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_frame_app/rx/audio.dart';
import 'package:simple_frame_app/rx/tap.dart';
import 'package:simple_frame_app/tx/code.dart';
import 'package:simple_frame_app/tx/plain_text.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'foreground_service.dart';
import 'settings_panel.dart';
import 'stt_models.dart';
import 'transcript_view.dart';
import 'utterance.dart';

void main() {
  // Set up Android foreground service
  initializeForegroundService();

  runApp(const MainApp());
}

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  MainAppState() {
    // filter logging
    hierarchicalLoggingEnabled = true;
    Logger.root.level = Level.INFO;
    Logger('Bluetooth').level = Level.OFF;
    Logger('RxAudio').level = Level.FINE;
    Logger('RxTap').level = Level.FINE;

    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  /// speech to text application members
  final TextEditingController _serviceAccountJsonController = TextEditingController();
  final TextEditingController _projectIdController = TextEditingController();
  final TextEditingController _languageCodeController = TextEditingController();
  SttModel _model = SttModel.chirp3;
  StreamSubscription<StreamingRecognizeResponse>? _recognitionSubs;
  // 16-bit linear PCM from Frame mic
  Stream<Uint8List>? _audioSampleStream;
  static const _sampleRate = 8000;

  // tap subscription and audio streaming status
  StreamSubscription<int>? _tapSubs;
  bool _streaming = false;

  // transcription UI display
  String _partialResult = '';
  // TODO (parking lot P1): save the transcript to a timestamped file with path_provider
  // TODO (parking lot P4): session list screen to resume/delete past sessions (needs P1)
  final List<Utterance> _transcript = List.empty(growable: true);
  final ScrollController _transcriptController = ScrollController();
  final ScrollController _partialResultController = ScrollController();
  String? _errorMsg;

  @override
  void initState() {
    super.initState();

    // load up the saved text field data
    _loadPrefs()
      // then kick off the connection to Frame and start the app if possible
      .then((_) => tryScanAndConnectAndStart(andRun: true));
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serviceAccountJsonController.text = prefs.getString('service_account_json') ?? '';
      _projectIdController.text = prefs.getString('project_id') ?? '';
      // mixed Norwegian/English by default (Google's code for Norwegian is no-NO)
      _languageCodeController.text = prefs.getString('language_code') ?? 'no-NO,en-US';
      _model = SttModel.byId(prefs.getString('stt_model'));
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('service_account_json', _serviceAccountJsonController.text);
    await prefs.setString('project_id', _projectIdController.text);
    await prefs.setString('language_code', _languageCodeController.text);
    await prefs.setString('stt_model', _model.id);
  }

  Future<void> _onModelChanged(SttModel model) async {
    setState(() => _model = model);
    // saved right away, used the next time recognition starts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stt_model', model.id);
  }

  /// "no-NO, en-US" -> ['no-NO', 'en-US']
  List<String> get _languageCodes => _languageCodeController.text
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();

  /// This application uses google cloud speech-to-text to listen to audio from the Frame mic, convert to text,
  /// and send the text to the Frame in real-time. It has a running main loop in this function
  /// and also on the Frame (frame_app.lua)
  @override
  Future<void> run() async {
    // validate Google Cloud Speech-to-Text API parameters exist at least
    _errorMsg = null;
    if (_serviceAccountJsonController.text.isEmpty || _projectIdController.text.isEmpty || _languageCodes.isEmpty) {
      setState(() {
        _errorMsg = 'Error: Set values for service account, project id and language code';
      });

      return;
    }

    setState(() {
      currentState = ApplicationState.running;
      _partialResult = '';
      _transcript.clear();
    });

    try {
      // listen for double taps to start/stop transcribing
      _tapSubs?.cancel();
      _tapSubs = RxTap().attach(frame!.dataResponse)
        .listen((taps) async {
          if (taps >= 2) {
            if (!_streaming) {
              _streaming = true;
              // clear the display, the transcribed text will start showing
              await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: ' '));
              await _startRecognition();
            }
            else {
              await _stopRecognition();
              _streaming = false;

              // prompt the user to begin tapping
              await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: 'Double-Tap to resume!'));
            }
          }
          // ignore spurious 1-taps
        });

      // let Frame know to subscribe for taps and send them to us
      await frame!.sendMessage(TxCode(msgCode: 0x10, value: 1));

      // prompt the user to begin tapping
      await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: 'Double-Tap to begin!'));

    } catch (e) {
      _errorMsg = 'Error executing application logic: $e';
      _log.fine(_errorMsg);

      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  /// Once running(), audio streaming is controlled by taps. But the user can cancel
  /// here as well, whether they are currently streaming audio or not.
  @override
  Future<void> cancel() async {
    setState(() {
      currentState = ApplicationState.canceling;
    });

    // cancel the subscription for taps
    _tapSubs?.cancel();

    // cancel the endless recognition subscription if it's running
    _recognitionSubs?.cancel();

    // tell the Frame to stop streaming audio (regardless of if we are currently)
    await frame!.sendMessage(TxCode(msgCode: 0x30, value: 0));

    // let Frame know to stop sending taps too
    await frame!.sendMessage(TxCode(msgCode: 0x10, value: 0));

    // clear the display
    await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: ' '));

    setState(() {
      currentState = ApplicationState.ready;
    });
  }

  /// Turn an API error into one readable line for the screen.
  String _describeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    final shortText = text.length > 200 ? '${text.substring(0, 200)}...' : text;
    return 'Speech API error (model ${_model.id}, ${_languageCodes.join(',')}): $shortText';
  }

  /// When we receive a tap to start the transcribing, we need to start
  /// audio streaming on Frame and start streaming recognition on the google speech API end
  Future<void> _startRecognition() async {
    final model = _model;
    final recognitionConfig = model.buildConfig(languageCodes: _languageCodes, sampleRate: _sampleRate);

    // tell Frame to start streaming audio
    await frame!.sendMessage(TxCode(msgCode: 0x30, value: 1));

    try {
      // TODO (parking lot P6): fall back to an on-device recogniser when there is no network
      // The model decides the regional endpoint (Chirp 3 does not work on the global one)
      final speechToText = EndlessStreamingServiceV2.viaServiceAccount(
        ServiceAccount.fromString(_serviceAccountJsonController.text),
        projectId: _projectIdController.text,
        cloudSpeechEndpoint: model.endpoint,
        location: model.location,
      );

      // TODO put this object where I can call on it later to detach()
      // TODO (parking lot P5): count dropped BLE audio packets and show them in the UI
      var rxAudio = RxAudio(streaming: true);
      // the audio stream from Frame, which needs to be closed() to stop the streaming recognition
      _audioSampleStream = rxAudio.attach(frame!.dataResponse);

      String prevText = '';

      speechToText.endlessStreamingRecognize(
        StreamingRecognitionConfigV2(
            config: recognitionConfig,
            streamingFeatures: StreamingRecognitionFeatures(interimResults: true)
        ),
        _audioSampleStream!,
        restartTime: const Duration(seconds: 120),
        transitionBufferTime: const Duration(milliseconds: 500)
      );

      // note: we stop the previous recognition stream by stopping its audio stream first
      // but also manage stream subscription here
      _recognitionSubs?.cancel();
      _recognitionSubs = speechToText.endlessStream.listen((data) async {
        // log the streamed results
        _log.fine(() => 'Result: $data');

        // responses can arrive without any results (e.g. speech activity events)
        final results = data.results.where((e) => e.alternatives.isNotEmpty).toList();
        if (results.isEmpty) return;

        // use the first alternative of each result. Finished parts are separated from
        // the interim part that is still changing.
        String join(Iterable<StreamingRecognitionResult> parts) => parts
            .map((e) => e.alternatives.first.transcript)
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final finalResults = results.where((e) => e.isFinal).toList();
        final finalText = join(finalResults);
        final interimText = join(results.where((e) => !e.isFinal));
        final currentText = join(results);

        if (_log.isLoggable(Level.FINE)) {
          _log.fine(() => 'Recognized text: $currentText');
        }

        // if the current text is different from the previous text, send an update to Frame
        // (there are many responses that split in different places, have different stability values,
        // but concatenate to the same string in our case, so don't update Frame display)
        if (currentText != prevText) { // TODO (&& Latin-only script?)
          prevText = currentText;
          // Frame can display 6 lines of plain text, so work out the text wrapping
          List<String> wrappedText = TextUtils.wrapText(currentText, 640, 4);

          // then send the bottom 6 lines joined with newlines as a single string
          // (they get split and drawn on the Lua side)
          String displayText = wrappedText.sublist(wrappedText.length <= 6 ? 0 : wrappedText.length - 6)
                                  .join('\n');

          await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: displayText));
        }

        // When a complete utterance is detected, isFinal is set and we can append
        // the utterance to the final transcript.
        // In between, there are non-final fragments, and they can be shown as previews but not appended
        // to the final transcript. A newline doesn't need to be added either.
        setState(() {
          if (finalText.isNotEmpty) {
            // keep the language the API detected for this utterance
            _transcript.add(Utterance(finalText, languageCode: finalResults.first.languageCode));
          }
          _partialResult = interimText;
        });
        _scrollToBottom();

      }, onError: (error) async {
        _log.warning('Error occurred in endless stream: $error');
        // show the problem, and stop streaming audio so the user can fix it and double-tap again
        await _stopRecognition();
        _streaming = false;
        await frame!.sendMessage(TxPlainText(msgCode: 0x0b, text: 'Speech error. Double-Tap to retry'));
        setState(() {
          _errorMsg = _describeError(error);
          currentState = ApplicationState.ready;
        });
      }, onDone: () {
        // audio stream was stopped so Recognizer stream stopped
        _log.info('Endless Stream is done');
        _recognitionSubs?.cancel();
        speechToText.dispose();
        setState(() {
          currentState = ApplicationState.ready;
        });
      });

    } catch (e) {
      _log.warning(() => 'Error executing application logic: $e');
      await _stopRecognition();
      _streaming = false;
      setState(() {
        _errorMsg = _describeError(e);
      });
    }
  }

  /// When we receive a tap to stop transcribing, cancel the audio streaming from Frame,
  /// which will send "final chunk" message, which will close the audio stream
  /// and the streaming recognizer stream will stop because its audio stream stopped
  Future<void> _stopRecognition() async {
    // tell Frame to stop streaming audio
    await frame!.sendMessage(TxCode(msgCode: 0x30, value: 0));

    // TODO we should also be able to send
    // rxAudio.detach() to close the controller controlling our audio stream
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptController.hasClients) {
        _transcriptController.animateTo(
          _transcriptController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      if (_partialResultController.hasClients) {
        _partialResultController.animateTo(
          _partialResultController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    startForegroundService();
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Transcribe - Google Cloud Speech',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Transcribe - Google Cloud Speech'),
            actions: [getBatteryWidget()]
          ),
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SettingsPanel(
                    serviceAccountController: _serviceAccountJsonController,
                    projectIdController: _projectIdController,
                    languageController: _languageCodeController,
                    model: _model,
                    onModelChanged: _onModelChanged,
                    onSave: _savePrefs,
                    errorMsg: _errorMsg,
                  ),
                  Expanded(
                    child: TranscriptView(
                      transcript: _transcript,
                      partialResult: _partialResult,
                      transcriptController: _transcriptController,
                      partialController: _partialResultController,
                    ),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: Stack(
            children: [
              if (_transcript.isNotEmpty) Positioned(
                bottom: 90,
                right: 20,
                child: FloatingActionButton(
                  onPressed: () {
                    // TODO (parking lot P3): export as JSON or SRT with timestamps and speakers
                    Share.share(_transcript.map((u) => u.text).join('\n'));
                  },
                  child: const Icon(Icons.share)),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: getFloatingActionButtonWidget(const Icon(Icons.mic), const Icon(Icons.mic_off)) ?? Container(),
              ),
            ]
          ),
          persistentFooterButtons: getFooterButtonsWidget(),
        ),
      )
    );
  }
}
