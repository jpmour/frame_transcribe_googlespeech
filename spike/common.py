"""Shared helpers for the colour-pass spike: WAV reading and Chirp 3 requests.

Credentials: set GOOGLE_APPLICATION_CREDENTIALS to the path of your service account JSON
file (keep that file outside the repo). Never commit it.
"""
import time
import wave
from dataclasses import dataclass

from google.api_core.client_options import ClientOptions
from google.cloud.speech_v2 import SpeechClient
from google.cloud.speech_v2.types import cloud_speech

SAMPLE_RATE = 8000
BYTES_PER_SECOND = SAMPLE_RATE * 2  # 16-bit mono


@dataclass
class Word:
    text: str
    start: float  # seconds, relative to the start of the request audio
    end: float
    label: str  # speaker label from the API ("" if none); numbering restarts per request


def read_wav(path):
    """Read raw PCM bytes from an 8 kHz, 16-bit, mono WAV (what the app records)."""
    with wave.open(path, "rb") as w:
        if (w.getframerate(), w.getsampwidth(), w.getnchannels()) != (SAMPLE_RATE, 2, 1):
            raise SystemExit(
                f"{path} must be 8000 Hz, 16-bit, mono. Convert with: "
                "ffmpeg -i in.wav -ar 8000 -ac 1 -sample_fmt s16 out.wav")
        return w.readframes(w.getnframes())


def slice_pcm(pcm, start_s, end_s):
    a = int(start_s * SAMPLE_RATE) * 2
    b = int(end_s * SAMPLE_RATE) * 2
    return pcm[a:b]


def make_client(region):
    return SpeechClient(client_options=ClientOptions(api_endpoint=f"{region}-speech.googleapis.com"))


def build_config(languages, model="chirp_3", diarize=True, word_offsets=True,
                 punctuation=True, min_speakers=None, max_speakers=None):
    features = cloud_speech.RecognitionFeatures(
        enable_word_time_offsets=word_offsets,
        enable_automatic_punctuation=punctuation,
    )
    if diarize:
        diar = cloud_speech.SpeakerDiarizationConfig()
        if min_speakers:
            diar.min_speaker_count = min_speakers
        if max_speakers:
            diar.max_speaker_count = max_speakers
        features.diarization_config = diar
    return cloud_speech.RecognitionConfig(
        explicit_decoding_config=cloud_speech.ExplicitDecodingConfig(
            encoding=cloud_speech.ExplicitDecodingConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=SAMPLE_RATE,
            audio_channel_count=1,
        ),
        language_codes=list(languages),
        model=model,
        features=features,
    )


def recognize(client, project, region, pcm, languages, **config_options):
    """One non-streaming request. Returns (latency_seconds, [Word], [result language codes])."""
    request = cloud_speech.RecognizeRequest(
        recognizer=f"projects/{project}/locations/{region}/recognizers/_",
        config=build_config(languages, **config_options),
        content=pcm,
    )
    started = time.time()
    response = client.recognize(request=request)
    latency = time.time() - started
    words, langs = [], []
    for result in response.results:
        langs.append(result.language_code)
        if not result.alternatives:
            continue
        for w in result.alternatives[0].words:
            words.append(Word(w.word, w.start_offset.total_seconds(),
                              w.end_offset.total_seconds(), w.speaker_label))
    return latency, words, langs
