#!/bin/sh
# Smoke test for the BG3 tools: a prop and a dressed, animated creature must still convert.
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
run() { uv run -q --with lz4 --with zstandard --with numpy python "$@"; }
run creature.py "$out/chest.glb" CONT_GEN_Chest_Common_A | grep -q "1 meshes, 4 bones, 0 animations"
run creature.py "$out/goblin.glb" S_SCL_DriderCaravan_GoblinMelee_000 --rig GOB_M_Rig | grep -q "12 meshes, 257 bones, 8 animations"
rm -r "$out"
echo ok
