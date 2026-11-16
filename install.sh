#!/usr/bin/env bash
# Import Tavernfall's assets and add it to your desktop's application menu.
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
command -v godot >/dev/null || { echo "Godot 4 is not installed (sudo pacman -S godot)"; exit 1; }
(cd "$DIR" && godot --headless --import >/dev/null 2>&1 || true)
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS"
for variant in "" "nvidia"; do
  name="Tavernfall"; file="tavernfall.desktop"; args=""
  if [ -n "$variant" ]; then name="Tavernfall (NVIDIA GPU)"; file="tavernfall-nvidia.desktop"; args=" --nvidia"; fi
  cat > "$APPS/$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
GenericName=Tabletop Adventure
Comment=A D&D adventure with Claude as your Dungeon Master
Exec="$DIR/run.sh"$args
Path=$DIR
Icon=$DIR/assets/tavernfall.png
Terminal=false
Categories=Game;RolePlaying;
Keywords=dnd;rpg;dungeon;tabletop;
StartupWMClass=Tavernfall
DESKTOP
done
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" >/dev/null 2>&1 || true
echo "Installed. Look for \"Tavernfall\" in your application menu, or run $DIR/run.sh"
