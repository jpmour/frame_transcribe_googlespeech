# Colour-pass spike (one day)

Question: can speaker colours for English be made **stable and timely enough** to be useful?
Answer with measured numbers, then decide: build, build reduced, or stop. See the plan for the
two methods (overlap, anchors) and the thresholds.

This folder is a throw-away research kit. It is not part of the app.

## Setup (once)

```powershell
python -m venv spike\.venv
spike\.venv\Scripts\python -m pip install -r spike\requirements.txt
# the service account JSON stays OUTSIDE the repo; only its path goes in this variable
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\Users\<you>\frame-keys\service-account.json"
```

The service account needs the Speech-to-Text client role, and the API enabled for the `eu` location.
Offline checks of the logic need no credentials: `spike\.venv\Scripts\python spike\test_logic.py`.

## 1. Record real Frame audio

1. Install the APK from the `spike/colour-pass` branch build (it installs over the normal app, same signing).
2. Turn on "Record raw audio (spike)" in the app, double-tap to stream, read the script, double-tap to pause.
3. Tap "Share last recording" and send the `.wav` to the PC (8 kHz, 16-bit, mono).
4. For each session make the matching script and keep it next to the recording:

```powershell
python spike\make_script.py --speakers 2 --turns 40 --out spike\script_2speakers.txt
python spike\make_script.py --speakers 3 --turns 40 --out spike\script_3speakers.txt
python spike\make_script.py --speakers 4 --turns 40 --out spike\script_4speakers.txt
```

Sessions wanted (about 5 minutes each): 2, 3 and 4 English speakers; one mixed Norwegian/English;
one control recorded on the phone microphone (separates "bad Frame mic" from "bad diarizer").
Only record people who agree to it. Recordings stay on this PC and are not committed (`*.wav` is ignored).

## 2. Probe the API (answers the yes/no questions)

```powershell
python spike\probe.py --project <project-id> --wav spike\rec_2speakers.wav
```

## 3. Compare the trackers on each recording

```powershell
cd spike
python run_windows.py --project <id> --wav rec_3speakers.wav --tracker none     --window 20 --hop 10 --out out\none.json
python run_windows.py --project <id> --wav rec_3speakers.wav --tracker overlap  --window 20 --hop 10 --out out\overlap.json
python run_windows.py --project <id> --wav rec_3speakers.wav --tracker anchors  --window 20 --hop 20 --out out\anchors.json
python score.py out\none.json    script_3speakers.txt
python score.py out\overlap.json script_3speakers.txt
python score.py out\anchors.json script_3speakers.txt
```

Also try `--window 10` and `--window 30` to find the balance between delay and accuracy.

## 4. Decide

Write the numbers into `RECOMMENDATION.md` (word accuracy, swaps per 10 minutes, median latency,
cost multiplier, for 2/3/4 speakers). Early-warning rule: if the better method gets under about 80 percent
of words right for 2 speakers, or a person's colour swaps more than about once per 10 minutes, say
"not good enough" straight away.
