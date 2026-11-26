"""Cut a recording into windows, send each to Chirp 3 Recognize with diarization, and track identities.

    python spike/run_windows.py --project P --wav talk.wav --tracker overlap --window 20 --hop 10 --out overlap.json

Compare trackers on the same recording: none (baseline), overlap (method A), anchors (method B).
For anchors use --hop equal to --window (no overlap needed; the clips replace it).
The result file also records latency and how many audio seconds were billed.
"""
import argparse
import json

from common import BYTES_PER_SECOND, make_client, read_wav, recognize, slice_pcm
from identity import TRACKERS


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--wav", required=True)
    parser.add_argument("--tracker", choices=sorted(TRACKERS), default="overlap")
    parser.add_argument("--window", type=float, default=20.0, help="seconds of new+overlap audio per request")
    parser.add_argument("--hop", type=float, default=10.0, help="seconds between window starts")
    parser.add_argument("--lang", default="en-US", help="comma-separated language codes")
    parser.add_argument("--region", default="eu")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    client = make_client(args.region)
    pcm = read_wav(args.wav)
    duration = len(pcm) / BYTES_PER_SECOND
    tracker = TRACKERS[args.tracker]()
    languages = [c.strip() for c in args.lang.split(",") if c.strip()]

    words, latencies, errors, billed, start = [], [], 0, 0.0, 0.0
    while start < duration - 3:
        window_pcm = slice_pcm(pcm, start, start + args.window)
        audio, offset = tracker.prepare(window_pcm)
        billed += len(audio) / BYTES_PER_SECOND
        try:
            latency, api_words, _ = recognize(client, args.project, args.region, audio, languages)
            latencies.append(latency)
            fresh = tracker.assign(api_words, start, offset, window_pcm)
            words += [vars(w) for w in fresh]
            print(f"window {start:6.1f}s: {len(fresh):3d} new words, {latency:.1f}s", flush=True)
        except Exception as error:
            errors += 1
            print(f"window {start:6.1f}s: ERROR {type(error).__name__}: {str(error)[:200]}", flush=True)
        start += args.hop

    summary = {
        "tracker": args.tracker, "window": args.window, "hop": args.hop,
        "recording_seconds": duration, "billed_seconds": billed,
        "cost_multiplier": round(billed / duration, 2),
        "median_latency": sorted(latencies)[len(latencies) // 2] if latencies else None,
        "errors": errors, "words": words,
    }
    with open(args.out, "w") as f:
        json.dump(summary, f, indent=1)
    print({k: v for k, v in summary.items() if k != "words"})


if __name__ == "__main__":
    main()
