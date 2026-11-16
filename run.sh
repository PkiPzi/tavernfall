#!/usr/bin/env bash
# Launch Tavernfall (imports the models first if needed, which takes a minute).
#   ./run.sh               default GPU
#   ./run.sh --nvidia      render on the NVIDIA GPU via PRIME offload
# Any other arguments go to Godot.
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
[ -d .godot/imported ] || godot --headless --import
exec godot --path "$DIR" "$@"
