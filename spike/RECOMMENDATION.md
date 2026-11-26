# Colour-pass spike: recommendation

**Status: not decided. No measurements have been taken yet.** The kit is built and tested offline,
but the experiments need two things only JP can supply.

## What is ready
- Spike APK with a raw-audio recorder (branch `spike/colour-pass`, built by CI).
- `probe.py`: yes/no checks of the Chirp 3 claims (diarization in Recognize at 8 kHz, min/max counts,
  `nb-NO`, mixed languages, streaming diarization, latency at 10/20/30 s).
- `run_windows.py` with three trackers (`none`, `overlap`, `anchors`) and `score.py` (word accuracy,
  wrong turns, swaps per 10 minutes, latency, cost multiplier). The tracker and scoring logic is unit tested
  offline (`test_logic.py`, 9 tests). Note one result already visible in the tests: the overlap method gives a
  person a new colour if they were silent during the overlap. The anchors method is meant to fix that.

## What is missing
1. A service account file path (`GOOGLE_APPLICATION_CREDENTIALS`) and project id for the live API calls.
2. Recordings made with the Frame: 2, 3 and 4 English speakers (about 5 minutes each, from `make_script.py`),
   one mixed Norwegian/English, one phone-mic control. See `README.md`.

## Decision rule (proposed, JP confirms)
- **Build as specified:** with the better method, at least ~85 percent of words coloured correctly for 2 speakers
  (~75 percent for 3), at most about 1 colour swap per 10 minutes, median colour delay about 5 s or less.
- **Build reduced:** identity is not stable but speaker changes are detected well: colour changes when the
  speaker changes (alternating colours, no identity promise).
- **Stop:** below about 80 percent of words right for 2 speakers, or swaps above about 1 per 10 minutes with no
  usable reduced mode. In that case this is reported the same day, before any end-to-end build.

## Results
_To be filled in after the sessions: table of accuracy, swaps per 10 minutes, latency and cost multiplier per tracker, per speaker count._
