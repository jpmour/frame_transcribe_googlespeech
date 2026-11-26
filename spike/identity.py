"""Keeping one person = one identity across separate Recognize requests.

Each request numbers its speakers from scratch ("1" in one request may be "2" in the next).
Three trackers share one interface so the spike can compare them on the same recordings:

  NoTracking     baseline: use the request's own label (shows how bad swapping is)
  OverlapTracker method A: windows overlap in time; map labels by who overlaps whom
  AnchorTracker  method B: put a short clip of each known speaker in front of every request;
                 the label the API gives a clip tells us who is who

Interface:
    audio, offset = tracker.prepare(window_pcm)       # what to send, and seconds added in front
    words = tracker.assign(api_words, window_start, offset, window_pcm)   # -> [AbsWord]
"""
from collections import defaultdict
from dataclasses import dataclass

from common import BYTES_PER_SECOND, Word, slice_pcm


@dataclass
class AbsWord:
    text: str
    start: float  # absolute seconds in the recording
    end: float
    identity: int  # 1, 2, 3 ... one per person; the display colour is (identity - 1) % 5 + 1


def _absolute(words, window_start, offset):
    """Words in request time -> absolute time, dropping words that belong to the prepended clips."""
    shift = window_start - offset
    return [(w, w.start + shift, w.end + shift) for w in words if (w.start + w.end) / 2 >= offset]


class NoTracking:
    name = "none"

    def __init__(self):
        self.covered_until = 0.0

    def prepare(self, window_pcm):
        return window_pcm, 0.0

    def assign(self, words, window_start, offset=0.0, window_pcm=None):
        result = [AbsWord(w.text, s, e, int(w.label) if w.label.isdigit() else 0)
                  for w, s, e in _absolute(words, window_start, offset)
                  if s >= self.covered_until]
        if result:
            self.covered_until = max(a.end for a in result)
        return result


class OverlapTracker:
    name = "overlap"

    def __init__(self, min_overlap=1.5):
        self.min_overlap = min_overlap
        self.history = []  # (start, end, identity) from earlier windows
        self.covered_until = 0.0
        self.next_identity = 1

    def prepare(self, window_pcm):
        return window_pcm, 0.0

    def _overlap_scores(self, abs_words):
        scores = defaultdict(float)  # (label, identity) -> seconds of shared speech
        for w, start, end in abs_words:
            if start >= self.covered_until:
                continue
            for h_start, h_end, identity in self.history:
                shared = min(end, h_end) - max(start, h_start)
                if shared > 0:
                    scores[(w.label, identity)] += shared
        return scores

    def assign(self, words, window_start, offset=0.0, window_pcm=None):
        abs_words = _absolute(words, window_start, offset)
        mapping, used = {}, set()
        for (label, identity), seconds in sorted(self._overlap_scores(abs_words).items(), key=lambda kv: -kv[1]):
            if seconds >= self.min_overlap and label not in mapping and identity not in used:
                mapping[label] = identity
                used.add(identity)
        result = []
        for w, start, end in abs_words:
            if w.label not in mapping:
                mapping[w.label] = self.next_identity
                self.next_identity += 1
            result.append(AbsWord(w.text, start, end, mapping[w.label]))
        # remember only words we have not seen in an earlier (overlapping) window
        fresh = [a for a in result if a.start >= self.covered_until]
        self.history = [h for h in self.history if h[1] > self.covered_until - 120]
        self.history += [(a.start, a.end, a.identity) for a in fresh]
        if fresh:
            self.covered_until = max(a.end for a in fresh)
        return fresh


class AnchorTracker:
    name = "anchors"
    GAP_SECONDS = 0.5

    def __init__(self, clip_seconds=3.0, max_clip_seconds=4.0):
        self.clip_seconds = clip_seconds
        self.max_clip_seconds = max_clip_seconds
        self.anchors = {}  # identity -> PCM clip of that person speaking alone
        self.layout = []  # (identity, start, end) of each clip inside the last request
        self.covered_until = 0.0
        self.next_identity = 1

    def prepare(self, window_pcm):
        parts, self.layout, t = [], [], 0.0
        silence = bytes(int(self.GAP_SECONDS * BYTES_PER_SECOND) // 2 * 2)
        for identity, clip in sorted(self.anchors.items()):
            duration = len(clip) / BYTES_PER_SECOND
            self.layout.append((identity, t, t + duration))
            parts += [clip, silence]
            t += duration + self.GAP_SECONDS
        return b"".join(parts) + window_pcm, t

    def _label_to_identity(self, words):
        votes = defaultdict(lambda: defaultdict(int))  # identity -> label -> word count
        for w in words:
            mid = (w.start + w.end) / 2
            for identity, start, end in self.layout:
                if start <= mid <= end:
                    votes[identity][w.label] += 1
        mapping, strength = {}, {}
        for identity, counts in votes.items():
            label, count = max(counts.items(), key=lambda kv: kv[1])
            # if the diarizer merged two people into one label, the clearer clip wins
            if label not in mapping or count > strength[label]:
                mapping[label], strength[label] = identity, count
        return mapping

    def _learn_clips(self, result, window_start, window_pcm):
        """Keep a clean clip for each identity we have not got one for yet."""
        run = []
        for a in result + [None]:
            if a is not None and (not run or (a.identity == run[0].identity and a.start - run[-1].end < 0.7)):
                run.append(a)
                continue
            if run and run[0].identity not in self.anchors and run[-1].end - run[0].start >= self.clip_seconds:
                end = min(run[-1].end, run[0].start + self.max_clip_seconds)
                self.anchors[run[0].identity] = slice_pcm(window_pcm, run[0].start - window_start, end - window_start)
            run = [a] if a is not None else []

    def assign(self, words, window_start, offset=0.0, window_pcm=None):
        mapping = self._label_to_identity(words)
        abs_words = _absolute(words, window_start, offset)
        result = []
        for w, start, end in abs_words:
            if w.label not in mapping:
                mapping[w.label] = self.next_identity
                self.next_identity += 1
            result.append(AbsWord(w.text, start, end, mapping[w.label]))
        self.next_identity = max([self.next_identity] + [a.identity + 1 for a in result])
        fresh = [a for a in result if a.start >= self.covered_until]
        if window_pcm is not None:
            self._learn_clips(fresh, window_start, window_pcm)
        if fresh:
            self.covered_until = max(a.end for a in fresh)
        return fresh


TRACKERS = {t.name: t for t in (NoTracking, OverlapTracker, AnchorTracker)}
