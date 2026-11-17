#!/usr/bin/env bash
# Launch Tavernfall (imports new assets first if needed, which can take a few minutes the first time).
#   ./run.sh               fullscreen on the default GPU (what the application menu / rofi runs)
#   ./run.sh --nvidia      render on the NVIDIA GPU via PRIME offload
#   TAVERN_WINDOWED=1 ./run.sh   a normal window instead of fullscreen
# Any other arguments go to Godot. Output goes to ~/.cache/tavernfall/run.log when there is no terminal.
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"
command -v godot >/dev/null || { echo "Godot 4 is not installed (sudo pacman -S godot)"; exit 1; }
if [ "${1:-}" = "--nvidia" ]; then
  shift
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __VK_LAYER_NV_optimus=NVIDIA_only
fi
# no terminal (rofi, a desktop file): keep the output somewhere you can read it
if [ ! -t 1 ]; then
  mkdir -p "$HOME/.cache/tavernfall"
  exec >>"$HOME/.cache/tavernfall/run.log" 2>&1
  echo "--- $(date) ---"
fi
# import when the project was never imported or an asset is newer than the last import
if [ ! -d .godot/imported ] || [ -n "$(find assets -type f -newer .godot/uid_cache.bin -not -name '*.import' -print -quit 2>/dev/null)" ]; then
  godot --headless --import
fi
# the tiling window manager would shrink a normal window to a postage stamp
[ -n "${TAVERN_WINDOWED:-}" ] || set -- --fullscreen "$@"
exec godot --path "$DIR" "$@"
