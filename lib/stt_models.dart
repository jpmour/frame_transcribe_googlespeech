import 'package:google_speech/config/recognition_config_v2.dart';
import 'package:google_speech/generated/google/cloud/speech/v2/cloud_speech.pb.dart' as v2;

/// Everything we know about one speech model: where to call it and what it supports.
/// Requests are built only from this definition, so a feature a model does not
/// support is never sent. To add a model, add one entry to [SttModel.all].
class SttModel {
  const SttModel({
    required this.id,
    required this.label,
    this.endpoint = 'speech.googleapis.com',
    this.location = 'global',
    this.punctuation = true,
    this.noPunctuationLanguages = const <String>{},
    this.multiLanguage = false,
    this.wordTimestamps = false,
  });

  /// Model name sent to the API, also the value saved in preferences.
  final String id;
  final String label;

  /// Regional API endpoint and matching location (Chirp 3 does not work on 'global').
  final String endpoint;
  final String location;

  /// Automatic punctuation is supported by the model...
  final bool punctuation;

  /// ...except for these languages (e.g. Norwegian on `long` has none).
  final Set<String> noPunctuationLanguages;

  /// Accepts several language codes in one request (used for mixed-language speech).
  final bool multiLanguage;

  /// Word time offsets are supported in streaming. Off everywhere for now:
  /// Chirp 3 does not support them in streaming, and the others are unverified.
  /// TODO (colour pass spike): check word offsets for the non-streaming request.
  final bool wordTimestamps;

  static const _norwegian = {'no-NO', 'nb-NO'};

  static const chirp3 = SttModel(
    id: 'chirp_3',
    label: 'Chirp 3 (EU)',
    endpoint: 'eu-speech.googleapis.com',
    location: 'eu',
    multiLanguage: true,
  );

  /// Chirp 3 first (the default), then the models the google_speech package knows.
  static const all = <SttModel>[
    chirp3,
    SttModel(id: 'long', label: 'Long', noPunctuationLanguages: _norwegian),
    SttModel(id: 'short', label: 'Short', noPunctuationLanguages: _norwegian),
    SttModel(id: 'telephony', label: 'Telephony', noPunctuationLanguages: _norwegian),
    SttModel(id: 'phone_call', label: 'Phone call', noPunctuationLanguages: _norwegian),
    SttModel(
      id: 'chirp',
      label: 'Chirp (europe-west4)',
      endpoint: 'europe-west4-speech.googleapis.com',
      location: 'europe-west4',
    ),
    SttModel(id: 'chirp_telephony', label: 'Chirp telephony', punctuation: false),
  ];

  static SttModel byId(String? id) => all.firstWhere((m) => m.id == id, orElse: () => chirp3);

  /// Models without multi-language support only get the first code.
  List<String> languagesToSend(List<String> codes) =>
      multiLanguage || codes.length <= 1 ? codes : [codes.first];

  bool usePunctuation(List<String> codes) =>
      punctuation && !languagesToSend(codes).any(noPunctuationLanguages.contains);

  /// The request config for this model. Input is always 8 kHz 16-bit mono from the Frame mic.
  RecognitionConfigV2 buildConfig({required List<String> languageCodes, required int sampleRate}) {
    return _ModelConfig(
      id,
      languageCodes: languagesToSend(languageCodes),
      features: v2.RecognitionFeatures(
        enableAutomaticPunctuation: usePunctuation(languageCodes) ? true : null,
        enableWordTimeOffsets: wordTimestamps ? true : null,
      ),
      explicitDecodingConfig: v2.ExplicitDecodingConfig(
        encoding: v2.ExplicitDecodingConfig_AudioEncoding.LINEAR16,
        sampleRateHertz: sampleRate,
        audioChannelCount: 1,
      ),
    );
  }
}

/// google_speech's RecognitionModelV2 enum has no `chirp_3`. The API takes the model as a
/// plain string though, so this subclass sets it directly (no fork of the package needed).
class _ModelConfig extends RecognitionConfigV2 {
  _ModelConfig(this.modelId, {super.features, super.explicitDecodingConfig, super.languageCodes});

  final String modelId;

  @override
  v2.RecognitionConfig toConfig() => super.toConfig()..model = modelId;
}
