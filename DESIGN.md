# Tavernfall: design

Personal single-machine D&D game with Claude as Dungeon Master. Decisions agreed on 2026-11-16.

## Scope
- Personal use only. Nothing hosted. Internet is used only for AI calls.
- Party of 1-4 characters, hot-seat on one screen. One person can run the whole party.
- AI is required to play. No no-AI mode.

## Tech
- Godot 4, GDScript. Rules engine must be testable headless from the command line.
- Tiles and sounds from free CC0 packs (Kenney, KayKit).
- Machine: GTX 1650 4 GB VRAM, 16 GB RAM. Local Ollama models are only 2-4B.

## Rules
- Full 5e from SRD 5.1, loaded from an open JSON dataset. Nothing outside the SRD.
- Code owns all rules and dice. Claude only narrates and proposes checks/encounters in a fixed format.
- First version: complete core engine (checks, saves, advantage, combat, conditions, rests, levelling)
  with fighter, rogue, cleric, wizard at levels 1-3. More classes and levels after.

## Story
- User gives a few hints; Claude writes the story plan (setting, villain, locations, characters, planned fights).
- Second source: paste a link or text of a free adventure; Claude converts it to the same plan format.
- No bundled stories.

## Play
- Outside battle: story screen with narration, a picture or 3D diorama of the location,
  3-4 suggested choices and a free-text box. No free walking around maps.
- In battle: 3D tabletop board, rotatable tilted camera, lighting, spell particles, 3D dice.
  Characters and monsters are animated 3D models. Buttons only: move, attack, cast,
  dash, dodge, item, end turn. Free-text combat actions are a later addition.
- Battle maps and dioramas: built by code from templates (dungeon room, forest clearing, tavern,
  cave, road) with random variation plus parameters Claude sets from the story.
- Combat UI conventions in the style of CRPGs: action bar, initiative strip, movement preview.

## AI
- Claude through the existing Claude Code subscription in headless mode (`claude -p`), no API key.
  Behind one small interface so another model can be swapped in.
- Each request sends: story plan, running summary, last few turns.

## Avatar and images
- Avatar = character sheet + one generated portrait, reused as reference for scene images.
- Images are deferred. Order when added: Cloudflare Workers AI (10k neurons/day free), then
  Pollinations.ai (no key), then local generation as last resort. No paid image costs.
- Generated images later become the miniatures.

## Other
- Auto-save every turn to a local file. Multiple save slots; reload after death.
- Sound effects and background music in the first version. No spoken narration.

## Build order
1. Rules engine with tests, no graphics.
2. 3D battle board: one full fight against goblins.
3. Claude as Dungeon Master: story from hints, story screen, saves.
4. Sound, diorama scenes, story import from the web.
5. Images and portraits, then more classes and levels.

## How to run
- `./run.sh` starts the game (`./run.sh --nvidia` renders on the NVIDIA card). `./install.sh` adds "Tavernfall"
  to the application menu (already done on this machine, same pattern as Primordia).
- Needs `godot` 4 and a logged-in `claude` command on the PATH.

## Status
All five build stages are in (2026-11-16).
- Stage 1, rules: `rules/`. Test with `godot --headless --path . -s tests/run_tests.gd` (1252 checks).
- Stage 2, battle board: `board/battle.gd`. Clicking squares is checked by `TAVERN_CLICKS` (see the top of that file);
  this found and fixed a bug where click-to-move never worked.
- Stage 3, Dungeon Master: `ai/`, `ui/story.gd`, `ui/menu.gd`, saves in `game.gd`. Played 17 turns against the
  real `claude -p` in autoplay (fights, checks, rests, a road scene) without errors.
- Stage 4: music and sound effects (`assets/audio`, credits there; on/off in the menu), forest and road places,
  adventure import from pasted text or a web link (the link path is written but was not run against a real page).
- Stage 5: portraits from Pollinations, all 12 SRD classes, levels 1 to 5 (ability +2 at level 4, Extra Attack at 5).
  Class features coded: rage, reckless attack, unarmored defense, martial arts, flurry of blows, lay on hands,
  divine smite, turn undead, pact magic, draconic resilience, fighting styles. Monsters use Multiattack and walk
  round walls.

Test hooks (environment variables): `TAVERN_DM=fake`, `TAVERN_AUTOPLAY=1`, `TAVERN_START=new|builder`,
`TAVERN_SHOT`/`TAVERN_SHOT_AT`, `TAVERN_SEED`, `TAVERN_ENC`, `TAVERN_PARTY`, `TAVERN_CLICKS`, `TAVERN_MUTE=1`,
`TAVERN_ART=off`, and `TAVERN_SAVES=<folder>` so test runs never touch the real save slots.

### Graphics decisions (changed 2026-11-16 at the user's request)
- Characters are animated KayKit 3D models with their gear showing, not flat cut-out miniatures.
- Terrain is KayKit Dungeon pieces (walls, floor tiles, props, torches). Assets are CC0, in `assets/kaykit`.
- GPU effects on: SSAO, SSIL, volumetric fog, glow, MSAA 4x, GPU particles.
- Gaps: no monster models besides skeletons (other creatures are skeletons tinted by kind and scaled by size),
  several classes share a model (monk uses the barbarian, bard and ranger the rogue), no mace for the cleric,
  the die is a tumbling ball not a physics die.
- Forest and road use trees and rocks from the KayKit Medieval Hexagon pack (`assets/kaykit/nature`, CC0).

### Known gaps (add when wanted)
- Not coded: bardic inspiration, wild shape, metamagic and sorcery points, stunning strike, warlock invocations,
  Preserve Life, Destroy Undead, grapple, shove, hide, two-weapon fighting, thrown weapons, cover, exhaustion,
  racial traits, monster special abilities (goblin Nimble Escape, breath weapons).
- Spells: damage, healing, Sleep, Hold Person, Bless, Shield of Faith, Mage Armor and Hunter's Mark work. Lingering
  spells (Moonbeam, Call Lightning, Spiritual Weapon) hit once only. Other utility spells are not offered.
  Magic Missile and Scorching Ray put everything on one target. No upcasting picker (lowest slot is used).
- Level-up is automatic: no choice of spells, subclass or feat. Levels stop at 5.
- Only item is the healing potion.
- A turned undead stands frozen instead of fleeing.
- Images: Pollinations only; Cloudflare Workers AI needs a key that does not exist yet. No scene pictures.
