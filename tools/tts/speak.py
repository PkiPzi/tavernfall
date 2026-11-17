#!/usr/bin/env python3
"""Text-to-speech worker for Tavernfall (Kokoro, runs on the CPU, nothing leaves the machine).
Reads one JSON object per line on stdin: {"text": "...", "voice": "bm_george", "speed": 1.0, "out": "/path/file.wav"}
and answers one line per request: "ok <out>" or "error <message>". Run with .venv/bin/python.
`speak.py --voices` lists the voices. `speak.py --say "text" voice out.wav` makes one file."""
import json, os, sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = os.path.dirname(os.path.abspath(__file__))
k = Kokoro(os.path.join(HERE, "models/kokoro-v1.0.int8.onnx"), os.path.join(HERE, "models/voices-v1.0.bin"))


def say(text, voice, speed, out):
    lang = "en-gb" if voice.startswith("b") else "en-us"
    samples, rate = k.create(text, voice=voice, speed=speed, lang=lang)
    sf.write(out, samples, rate)


if len(sys.argv) > 1 and sys.argv[1] == "--voices":
    print(" ".join(k.get_voices()))
elif len(sys.argv) > 1 and sys.argv[1] == "--say":
    say(sys.argv[2], sys.argv[3], 1.0, sys.argv[4])
else:
    print("ready", flush=True)
    for line in sys.stdin:
        try:
            r = json.loads(line)
            say(r["text"], r.get("voice", "bm_george"), float(r.get("speed", 1.0)), r["out"])
            print("ok " + r["out"], flush=True)
        except Exception as e:  # one bad line must not end the worker
            print("error " + str(e).replace("\n", " "), flush=True)
