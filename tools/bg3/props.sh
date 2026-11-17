#!/usr/bin/env bash
# Convert the scenery props the battle board uses into assets/bg3/props/<name>.glb (static, no animations).
# Run from this folder: ./props.sh   (existing files are kept)
cd "$(dirname "$0")"
OUT=../../assets/bg3/props; mkdir -p $OUT
run() { uv run -q --with lz4 --with zstandard --with numpy python "$@"; }
for n in "$@"; do
  [ -f $OUT/$n.glb ] && continue
  run creature.py $OUT/$n.glb $n --anims none 2>&1 | tail -1
done
