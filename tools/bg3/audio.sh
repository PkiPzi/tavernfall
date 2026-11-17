#!/bin/sh
# Exports BG3 sound events into assets/bg3/audio (gitignored). With no arguments: everything in audio_events.txt.
# Run from tools/bg3; needs vgmstream-cli and ffmpeg.
OUT=../../assets/bg3/audio
mkdir -p $OUT
[ $# -eq 0 ] && set -- $(cat audio_events.txt)
for e in "$@"; do
  uv run -q --with lz4 --with zstandard --with numpy python audio.py export "$e" $OUT
done
