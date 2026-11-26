"""Score a run_windows.py result against the recording script (who really said what).

    python spike/score.py overlap.json script.txt

script.txt has one line per turn, in the order spoken:   A: the sentence that speaker A read
Truth for each recognised word comes from aligning the recognised words to the script words,
so no hand labelling is needed.

Reports:
  word accuracy   recognised words given to the right person (after the best identity->speaker mapping)
  identities      how many identities the tracker created (more than the real speaker count = splits)
  wrong turns     turns whose majority identity maps to the wrong person; "swaps per 10 min" is the
                  rate that matters for the build / reduced / stop decision
"""
import difflib
import json
import re
import sys
from collections import Counter, defaultdict


def normalise(text):
    return re.sub(r"[^\w]", "", text.lower())


def load_script(path):
    """-> [(normalised word, speaker)] and the number of turns."""
    truth, turns = [], 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if ":" not in line:
                continue
            speaker, text = line.split(":", 1)
            turns += 1
            truth += [(n, speaker.strip()) for n in map(normalise, text.split()) if n]
    return truth, turns


def align(hyp, truth):
    """hyp: [(normalised word, identity)] -> [(identity, true speaker)] for matched words, in order."""
    matcher = difflib.SequenceMatcher(None, [h[0] for h in hyp], [t[0] for t in truth], autojunk=False)
    pairs = []
    for block in matcher.get_matching_blocks():
        for k in range(block.size):
            pairs.append((hyp[block.a + k][1], truth[block.b + k][1]))
    return pairs


def best_mapping(pairs):
    """One-to-one identity -> speaker, strongest overlaps first."""
    counts = Counter(pairs)
    mapping, used = {}, set()
    for (identity, speaker), _ in counts.most_common():
        if identity not in mapping and speaker not in used:
            mapping[identity] = speaker
            used.add(speaker)
    return mapping


def turn_errors(pairs, mapping):
    """Split matched words into turns (runs of the same true speaker) and count wrong ones."""
    turns, current = [], []
    for identity, speaker in pairs:
        if current and current[-1][1] != speaker:
            turns.append(current)
            current = []
        current.append((identity, speaker))
    if current:
        turns.append(current)
    wrong = 0
    for turn in turns:
        if len(turn) < 3:
            continue
        majority = Counter(i for i, _ in turn).most_common(1)[0][0]
        wrong += mapping.get(majority) != turn[0][1]
    return len([t for t in turns if len(t) >= 3]), wrong


def score(result, truth):
    words = sorted(result["words"], key=lambda w: w["start"])
    hyp = [(n, w["identity"]) for w in words if (n := normalise(w["text"]))]
    pairs = align(hyp, truth)
    mapping = best_mapping(pairs)
    correct = sum(mapping.get(i) == s for i, s in pairs)
    turns, wrong = turn_errors(pairs, mapping)
    minutes = result["recording_seconds"] / 60
    per_speaker = defaultdict(lambda: [0, 0])
    for i, s in pairs:
        per_speaker[s][1] += 1
        per_speaker[s][0] += mapping.get(i) == s
    return {
        "tracker": result["tracker"],
        "matched_words": len(pairs), "script_words": len(truth),
        "word_accuracy_pct": round(100 * correct / max(1, len(pairs)), 1),
        "per_speaker_pct": {s: round(100 * c / max(1, n), 1) for s, (c, n) in sorted(per_speaker.items())},
        "identities_created": len({i for i, _ in pairs}),
        "turns": turns, "wrong_turns": wrong,
        "swaps_per_10_min": round(wrong / max(minutes, 0.1) * 10, 1),
        "median_latency_s": result["median_latency"], "cost_multiplier": result["cost_multiplier"],
        "errors": result["errors"],
    }


if __name__ == "__main__":
    truth_words, _ = load_script(sys.argv[2])
    print(json.dumps(score(json.load(open(sys.argv[1])), truth_words), indent=1))
