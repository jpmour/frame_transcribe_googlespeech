"""Make a reading script for a recording session, so the truth (who said what) is known.

    python spike/make_script.py --speakers 3 --turns 40 --out spike/script_3speakers.txt

Everyone reads their own lines, in order, at a normal pace, in a room, wearing the Frame (one
person wears it, like in a real meeting). Short interjections are included on purpose because
real conversations have them and they are hard for diarization.
"""
import argparse
import random

SENTENCES = [
    "We should move the release to the end of next week.",
    "I think the budget numbers still need another review.",
    "Can you send me the latest version of the document?",
    "The customer asked for a short summary before the meeting.",
    "Let us start with the main risks on the project.",
    "I will check with the team and come back to you tomorrow.",
    "There was a problem with the build on Tuesday evening.",
    "That sounds reasonable, but we need to be careful with the schedule.",
    "Our main competitor has just published a new product.",
    "I would like to hear what everyone thinks about the proposal.",
    "The contract has to be signed before the end of the month.",
    "We could split the work into three smaller parts.",
    "Please remember to update the status page after the call.",
    "The test results look better than we expected last week.",
    "I am not sure that the deadline is realistic for this quarter.",
    "Let us agree on the next steps before we finish today.",
    "The new office will be ready in about six weeks.",
    "He explained the plan clearly, but the cost is still unclear.",
    "We need one person to take responsibility for the follow up.",
    "The report shows a small increase compared to the last period.",
    "I have a question about the second slide in the presentation.",
    "Everything depends on whether the supplier can deliver on time.",
    "It would be good to run a short pilot with two customers first.",
    "We already discussed this in the meeting on Monday morning.",
]
INTERJECTIONS = ["Right.", "Agreed, go on.", "Yes, exactly.", "Hmm, not sure about that.", "Okay, good point."]


def build(speakers, turns, seed):
    rng = random.Random(seed)
    names = "ABCDE"[:speakers]
    lines, last = [], None
    for _ in range(turns):
        who = rng.choice([n for n in names if n != last])
        last = who
        if rng.random() < 0.25:
            text = rng.choice(INTERJECTIONS)
        else:
            text = " ".join(rng.sample(SENTENCES, rng.choice([1, 2])))
        lines.append(f"{who}: {text}")
    return lines


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--speakers", type=int, choices=range(2, 6), default=2)
    parser.add_argument("--turns", type=int, default=40)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(build(args.speakers, args.turns, args.seed)) + "\n")
    print(f"Wrote {args.out}")
