"""Offline checks of the identity trackers and the scorer. Run: python spike/test_logic.py"""
import unittest

from common import BYTES_PER_SECOND, Word
from identity import AnchorTracker, NoTracking, OverlapTracker
from score import align, best_mapping, load_script, score, turn_errors


def speech(label, start, end, step=0.5):
    """Fake API words for one speaker talking from start to end (request time)."""
    count = int((end - start) / step)
    return [Word(f"w{label}{start}_{k}", start + k * step, start + (k + 1) * step, label) for k in range(count)]


def identities(words, t0, t1):
    return {a.identity for a in words if t0 <= a.start < t1}


class OverlapTrackerTest(unittest.TestCase):
    def test_keeps_identity_when_the_api_swaps_labels(self):
        tracker = OverlapTracker()
        # window 1 (0..10 s): person A in 0..7, person B in 7..10
        first = tracker.assign(speech("1", 0, 7) + speech("2", 7, 10), window_start=0)
        a, b = identities(first, 0, 7), identities(first, 7, 10)
        self.assertEqual(len(a | b), 2)
        # window 2 (5..15 s) overlaps with both A (5..7) and B (7..10), but the API swaps the
        # labels: A is now "2" and B is "1". New speech 10..15 is by A, so label "2".
        second = tracker.assign(speech("2", 0, 2) + speech("1", 2, 5) + speech("2", 5, 10), window_start=5)
        self.assertEqual(identities(second, 10, 15), a)  # A is still A
        self.assertEqual(identities(second, 5, 10), set())  # old audio was not counted twice

    def test_known_weakness_person_silent_in_the_overlap_becomes_new(self):
        tracker = OverlapTracker()
        first = tracker.assign(speech("1", 0, 5) + speech("2", 5, 10), window_start=0)
        a = identities(first, 0, 5)
        # only B speaks in the overlap (5..10); A comes back later under the API's label "2"
        second = tracker.assign(speech("1", 0, 5) + speech("2", 5, 10), window_start=5)
        self.assertNotEqual(identities(second, 10, 15), a)  # A gets a new identity (a colour change)

    def test_new_person_gets_new_identity(self):
        tracker = OverlapTracker()
        tracker.assign(speech("1", 0, 10), window_start=0)
        second = tracker.assign(speech("1", 0, 5) + speech("2", 5, 10), window_start=5)
        self.assertEqual(len(identities(second, 10, 15)), 1)
        self.assertNotIn(1, identities(second, 10, 15))


class NoTrackingTest(unittest.TestCase):
    def test_baseline_shows_the_swap(self):
        tracker = NoTracking()
        tracker.assign(speech("1", 0, 5) + speech("2", 5, 10), window_start=0)
        second = tracker.assign(speech("1", 0, 5) + speech("2", 5, 10), window_start=5)
        self.assertEqual(identities(second, 10, 15), {2})  # same person as before, now labelled 2


class AnchorTrackerTest(unittest.TestCase):
    def test_clip_labels_decide_who_is_who(self):
        tracker = AnchorTracker()
        clip = bytes(3 * BYTES_PER_SECOND)
        tracker.anchors = {1: clip, 2: clip}
        tracker.next_identity = 3
        audio, offset = tracker.prepare(bytes(10 * BYTES_PER_SECOND))
        self.assertAlmostEqual(offset, 2 * (3 + 0.5))
        self.assertEqual(len(audio), int((offset + 10) * BYTES_PER_SECOND))
        # the API labelled clip 1 as "2" and clip 2 as "1"; then the window: "1" speaks, then "2"
        clip_one = speech("2", 0, 3)
        clip_two = speech("1", 3.5, 6.5)
        window = speech("1", offset, offset + 5) + speech("2", offset + 5, offset + 10)
        result = tracker.assign(clip_one + clip_two + window, window_start=40, offset=offset)
        self.assertEqual(identities(result, 40, 45), {2})  # label "1" is the person of clip 2
        self.assertEqual(identities(result, 45, 50), {1})
        self.assertEqual(min(a.start for a in result), 40)  # clip words are not in the output

    def test_learns_a_clip_from_a_long_single_speaker_run(self):
        tracker = AnchorTracker()
        pcm = bytes(20 * BYTES_PER_SECOND)
        tracker.assign(speech("1", 0, 6) + speech("2", 6, 8), window_start=0, offset=0.0, window_pcm=pcm)
        self.assertEqual(list(tracker.anchors), [1])  # 6 s run is long enough, 2 s is not
        self.assertLessEqual(len(tracker.anchors[1]), 4 * BYTES_PER_SECOND)


class ScoreTest(unittest.TestCase):
    TRUTH = [("hello", "A"), ("there", "A"), ("friend", "A"), ("hi", "B"), ("how", "B"), ("are", "B"), ("you", "B"),
             ("fine", "A"), ("thanks", "A"), ("and", "A")]

    def hyp(self, ids):
        return [(w, i) for (w, _), i in zip(self.TRUTH, ids)]

    def test_perfect(self):
        pairs = align(self.hyp([7, 7, 7, 9, 9, 9, 9, 7, 7, 7]), self.TRUTH)
        mapping = best_mapping(pairs)
        self.assertEqual(mapping, {7: "A", 9: "B"})
        self.assertEqual(turn_errors(pairs, mapping), (3, 0))

    def test_swap_is_counted(self):
        pairs = align(self.hyp([7, 7, 7, 9, 9, 9, 9, 9, 9, 9]), self.TRUTH)  # A's last turn lands on B's identity
        mapping = best_mapping(pairs)
        self.assertEqual(turn_errors(pairs, mapping)[1], 1)

    def test_load_script_and_score(self):
        import os, tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
            f.write("A: Hello there friend.\nB: Hi, how are you?\n")
        truth, turns = load_script(f.name)
        os.unlink(f.name)
        self.assertEqual((len(truth), turns), (7, 2))
        words = [{"text": t, "start": k, "end": k + 1, "identity": 1 if k < 3 else 2}
                 for k, t in enumerate(["Hello", "there", "friend", "Hi", "how", "are", "you"])]
        result = score({"words": words, "tracker": "t", "recording_seconds": 60, "median_latency": 1,
                        "cost_multiplier": 1, "errors": 0}, truth)
        self.assertEqual(result["word_accuracy_pct"], 100.0)


if __name__ == "__main__":
    unittest.main()
