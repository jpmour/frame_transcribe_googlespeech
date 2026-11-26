"""Quick checks of what Chirp 3 (EU) really does, versus what the docs say.

    python spike/probe.py --project my-project --wav english_two_speakers.wav

Each check prints OK or the API's error, so one run answers several brief questions:
 - does diarization work in Recognize on 8 kHz audio (and with word offsets)?
 - are min/max speaker counts accepted on Chirp 3?
 - is `nb-NO` accepted as well as `no-NO`?
 - does STREAMING diarization really fail?
 - what is the latency for 10 / 20 / 30 second windows?
"""
import argparse

from google.cloud.speech_v2.types import cloud_speech

from common import (BYTES_PER_SECOND, build_config, make_client, read_wav,
                    recognize, slice_pcm)


def check(name, fn):
    try:
        print(f"[OK]   {name}: {fn()}")
    except Exception as error:  # we want to see every API error text
        print(f"[FAIL] {name}: {type(error).__name__}: {str(error)[:300]}")


def labels_of(words):
    return sorted({w.label for w in words})


def streaming_diarization(client, project, region, pcm):
    """Streaming with a diarization config. The docs say Chirp 3 rejects or ignores it."""
    config = cloud_speech.StreamingRecognitionConfig(config=build_config(["en-US"], diarize=True, word_offsets=False))
    recognizer = f"projects/{project}/locations/{region}/recognizers/_"

    def requests():
        yield cloud_speech.StreamingRecognizeRequest(recognizer=recognizer, streaming_config=config)
        for i in range(0, len(pcm), 3200):
            yield cloud_speech.StreamingRecognizeRequest(audio=pcm[i:i + 3200])

    labels = set()
    for response in client.streaming_recognize(requests=requests()):
        for result in response.results:
            for alt in result.alternatives[:1]:
                labels.update(w.speaker_label for w in alt.words)
    return f"speaker labels seen in streaming: {sorted(labels)}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--wav", required=True, help="8 kHz mono WAV with at least 30 s of English")
    parser.add_argument("--region", default="eu")
    args = parser.parse_args()

    client = make_client(args.region)
    pcm = read_wav(args.wav)
    clip = slice_pcm(pcm, 0, 20)

    def rec(languages, **options):
        latency, words, langs = recognize(client, args.project, args.region, clip, languages, **options)
        return f"{len(words)} words, labels {labels_of(words)}, langs {langs}, {latency:.1f}s"

    check("diarize + word offsets (20 s)", lambda: rec(["en-US"]))
    check("diarize, no word offsets", lambda: rec(["en-US"], word_offsets=False))
    check("diarize with min/max speaker counts 2..4", lambda: rec(["en-US"], min_speakers=2, max_speakers=4))
    check("no diarization, no-NO", lambda: rec(["no-NO"], diarize=False))
    check("no diarization, nb-NO", lambda: rec(["nb-NO"], diarize=False))
    check("no-NO + en-US together, diarize", lambda: rec(["no-NO", "en-US"]))
    check("no-NO + en-US together, no diarize", lambda: rec(["no-NO", "en-US"], diarize=False))
    for seconds in (10, 20, 30):
        piece = slice_pcm(pcm, 0, seconds)
        if len(piece) < seconds * BYTES_PER_SECOND:
            print(f"[SKIP] latency {seconds}s: recording too short")
            continue
        check(f"latency, {seconds} s window",
              lambda p=piece: "%.2fs" % recognize(client, args.project, args.region, p, ["en-US"])[0])
    check("STREAMING with diarization config",
          lambda: streaming_diarization(client, args.project, args.region, slice_pcm(pcm, 0, 30)))


if __name__ == "__main__":
    main()
