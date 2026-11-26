/// One finished utterance from the speech API.
/// TODO (parking lot P2): add a timestamp here and show it in the transcript.
class Utterance {
  const Utterance(this.text, {this.languageCode});

  final String text;

  /// Language the API detected for this utterance (e.g. `no-no`, `en-us`), if it said.
  /// The colour pass will use this to only colour English speech.
  final String? languageCode;
}
