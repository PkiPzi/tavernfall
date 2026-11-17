#!/usr/bin/env bash
# Export BG3's own interface art (frames, buttons, pips, dice, character creation) into assets/bg3/ui/<folder>/.
cd "$(dirname "$0")"
run() { uv run -q --with lz4 --with zstandard --with numpy python "$@"; }
for d in BottomBar Buttons Shared CharacterPanel ActiveRoll Dialogue Combatants TargetInfo Overhead SpellBook Scrollbars CombatLog Equipment Container CC CharacterCreation Portraits PlayerPortraits Reactions Notification Radials RestMenu Journal LoadingScreen Trade ClassIcons Options SaveLoad; do
  low=$(echo $d | tr 'A-Z' 'a-z')
  run images.py Game.pak "public/game/gui/assets/$low/*" ../../assets/bg3/ui/$low
done
