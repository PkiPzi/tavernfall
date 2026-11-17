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
- Stage 1, rules: `rules/`. Test with `godot --headless --path . -s tests/run_tests.gd` (1334 checks).
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

- Launching (2026-11-17): `run.sh` and the `.desktop` entries (rofi/app menu) work with no terminal; output goes to
  `~/.cache/tavernfall/run.log`. Fixed the Escape menu, whose buttons crashed because a lambda cannot call itself
  through a captured variable (GDScript captures by value; use a box array).

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
- Images: Pollinations only; Cloudflare Workers AI needs a key that does not exist yet. No scene pictures.

## Baldur's Gate 3 assets (decided 2026-11-17, uncommitted)
The user owns BG3 and wants its models, icons, fonts and sounds used directly, for private play only. This replaces
"inspiration only, original art" below and answers item 6 of the overhaul list (no more KayKit chibi models).
Engine stays Godot: BG3's own engine cannot be reused, and its assets convert to `.glb` and `.png`.
- `tools/bg3/` holds a working converter; **read `tools/bg3/README.md` first**, it lists every command, what is
  approximated, what is not done, and the integration steps in order. `tools/bg3/check.sh` is the smoke test.
- Done and checked by screenshot: creature/weapon/prop to textured, skinned, animated `.glb` (goblin, owlbear,
  skeleton, greataxe, chest). Exported into `assets/bg3/`: 1522 skill icons, 3045 item icons, class and race icons,
  resource pips, d20 faces, the game's fonts.
- Monsters now load BG3 models (2026-11-17): `Scenery.BG3_MODEL` maps SRD index to `assets/bg3/models/<x>.glb` (goblin, owlbear, skeleton, zombie, ogre, gnoll, kobold, ghoul, wolf, spider, rat), falling back to KayKit when the file is missing. BG3 animation names are aliased to the KayKit ones in `Scenery.character`, so `battle.gd` is unchanged. Bugbear is left out: on the goblin rig it crumples. Run `godot --headless --import` after adding models (about 5x the .glb size in `.godot/`).
- Heroes load BG3 too (2026-11-17): `Scenery.BG3_HERO`, `hero_<class>.glb`, one dressed story NPC per class (S_LOW_HagSurvivors_Bandit_* for barbarian/bard/fighter/paladin/warlock/wizard; veteran cleric, Bhaal assassin, bandit ranger, Gur hunter, Bhaal cultist for the rest; sorcerer shares wizard). Origin companions (Gale, Karlach...) are stored naked with red skin: do not use. Animations of some bodies needed `--rig HUM_F_Rig` / `HUM_M_Rig`. Race is ignored for now.
- Terrain (2026-11-17): `board/ground.gdshader` blends two BG3 tileable terrain textures (assets/bg3/terrain, from Textures.pak `TT_*`) by a mask of rough ground/road, noise-broken edges. Cell = 1.5 m (`Scenery.CELL`, BG3's 5 ft), board 16x12, models life size. BG3 props (assets/bg3/props, `tools/bg3/props.sh`) are normalised to a longest side in metres by `Scenery.bg3_prop`; templates list them in `bg3props`/`bg3edge`. Sky, sun, ACES grading in `Scenery._light`.
- Portraits are rendered locally from the BG3 models by `board/bust.gd` (head bone framing; `tools/bg3/bust_sheet.gd` makes a contact sheet to check framing). `Game.portrait` uses it first.
- Battle HUD (`ui/hud.gd`, used by `board/battle.gd`) is built from BG3's own interface art exported by `tools/bg3/ui_export.sh` into assets/bg3/ui: portrait ring hotbar with end caps, End Turn orb, turn-order cards, action/bonus pips, movement bar, skill/weapon icons from assets/bg3/icons. Hit-chance tag follows the pointer (`Combat.hit_chance`). Test screenshots: run Godot with `--fullscreen` (a tiling WM otherwise shrinks the window).
- Materials fixed: body skin (was the red underwear texture), hair tinted from the character's hair colour, invisible helper meshes skipped.
- Screenshot recipe: `TAVERN_MUTE=1 TAVERN_SAVES=/tmp/x TAVERN_ART=off TAVERN_ENC="forest:goblin=2" TAVERN_PARTY="wizard,fighter" TAVERN_SHOT=out.png TAVERN_SHOT_AT=8 godot --path . --fullscreen board/battle.tscn`
- Dungeon walls are BG3 temple pieces (`WALL_Dungeon_Temple_A_*` tiled by `Scenery.bg3_wall`, pillars at the posts), torches are `Scenery.torch` (BG3 torch model, GPU particle flame, flickering light). Other templates still use KayKit walls.
- Roll overlay `ui/diceroll.gd` plays BG3's d20 tumble sprite sheets (assets/bg3/dice) with title, maths, outcome; replaced the 3D die.
- Theme: `Ui.make_theme` uses BG3 art (cc/btnnormal_*, cc/appearancepane) and is applied by `Game._ready` (also to controls under CanvasLayers via node_added). Fonts: Cinzel buttons/titles, EB Garamond text. BG3's own fonts are in assets/bg3/fonts (not used yet).
- Party creation is `ui/creator.gd` (3D dais in a SubViewport, race/class icon pickers, sheet, story step); menu.gd just hosts it. `Scenery.RACE_SCALE` sizes heroes by race; the model itself is per class only.
- Added 2026-11-17 (later): cave template = layered BG3 cliff boulders + `Scenery.fire_pit`; outdoor moods day/dusk/night (night has campfires); target info panel + hit-chance tag + footstep path preview; floating combat text + camera shake on crits; camera glide to the acting hero and a fly-in at battle start; character sheet overlay (`ui/sheet.gd`, press C or click a portrait); story screen shows a speaker bust + name (`speaker` in the DM JSON, `Scenery.npc_model` picks a model by keywords); rules: Help, Hide, Shove (tests in `t_actions`); heroes hold their weapons (`Scenery.equip`, BG3 weapon models on `Dummy_R_Hand`/`Dummy_L_Hand`).
- Later still: second look per class (`hero_<class>_b.glb`, `tools/bg3/hero_variants.py`, `spec.variant`, Look 1/2 in the creator); control spells Web, Entangle, Faerie Fire, Fear, Blur, Invisibility (tests `t_control_spells`); spell effects with glowing orb + trail + impact (`_bolt`, `_burst`; `TAVERN_FX=1` fires one); WASD pan, Space recentres, Esc pause menu (`ui/pause.gd`), journal (J), loading screens (`Game.go`), low-hit-point red vignette, dust motes; audio is BLOCKED until `vgmstream-cli` is installed (`yay -S vgmstream-git`).
- Set dressing (2026-11-17): templates may carry `bg3sets` (composed furniture/camp groups: cell footprint, items with offsets, optional `light`/`fire`) and `bg3bar` (tavern bar along the far wall); `Scenery._group` places them in free middle cells and blocks those squares. Tavern: tables with benches/chairs, bar counter + kegs, candelabras, sacks, hay. Forest: tent camp with a fire, bushes, logs, mushrooms. Convert new props with `creature.py ../../assets/bg3/props/<Name>.glb <Name> --anims none`, then `godot --headless --import` (a missing import makes `ResourceLoader.exists` false and the set silently disappears). Dusk was toned down (less orange); campfire flame is layered with sparks.
- Also (2026-11-17, later): dungeon and cave `bg3sets` too (sarcophagus, statue, goblin tent camp); terrain relief: templates with `"relief": metres` get a FastNoiseLite height image (`Scenery.make_relief`, `height_at`) sampled by `board/ground.gdshader` (vertex displacement) and by `Scenery.world()` so characters, props and markers sit on the hills; markers lift by `Scenery.lift()`, mouse picking iterates the ground height; cover rule (`Combat.cover_bonus`: +2 / +5 from wall squares on the line, ranged attacks and ranged spell attacks, test `t_cover`, shown in the log and hit chance); inventory screen (`ui/inventory.gd`, I, Bag button on the sheet); level-up screen (`ui/levelup.gd`, shown by `ui/story.gd` after a won fight, data from `Game.levelups`); screenshot hook `TAVERN_OVERLAY=sheet|bag|levelup`.
- Audio (2026-11-17): vgmstream-cli is installed, so `tools/bg3/audio.py` now exports. `audio.sh` (no args) exports everything in `audio_events.txt` to assets/bg3/audio as `<event>_<n>.ogg` (loudness normalised, at most 8 recordings per event). It walks all soundbanks and reads media embedded in banks (UI sounds). `Game.bg3(event)` / `Game.sound(event, fallback)` play them, with the bundled CC0 sounds as fallback; used for weapon hits by damage type, misses, footsteps, spell impacts by damage type, healing, UI click/hover, dice, level-up, combat start, and monster pain/death voices (`Game.voice`, `Game.VOICES`). Music and ambience are NOT done: music events only set Wwise states (no recordings behind them), so the CC0 music stays.
- Portraits (2026-11-17): BG3's generic portrait icons (Gustav_Textures.pak `mods/gustav/gui/assets/portraits`, 871 files in assets/bg3/portraits, via `images.py`) are chosen by `ui/portraits.gd` from the creature's SRD index (goblin, skeleton, wolf, ogre...) or, for heroes, race + gender + class equipment words in the file name. `Game.portrait` uses them first and falls back to the local 3D bust.
- Story scenes (2026-11-17): `ui/scenes.gd` maps BG3's loading-screen paintings to 13 scene ids (harbor_city ... market_street) with keywords and a default battlefield template; the DM may name a `scene` for a place (prompt + `ai/prompts.gd` SCENES), else keywords/template decide. `ui/story.gd` shows a Ken Burns establishing-shot card when the place changes.
- Look (2026-11-17): GPU grass (`board/grass.gdshader`, `Scenery.grass`, template key `grass`), plant/moss clutter (`bg3clutter`: ferns, moss, mushrooms), FSR 3D scaling for big screens (`Game._fit_resolution`: 4K ran 19 fps, now ~30), camp fire lights have no shadows.
- Materials (2026-11-17): the converter now exports BG3's physical map as an ORM texture (R occlusion, G roughness, B metal x0.85; BG3's own layout is R metal, G roughness, B occlusion) into every model and prop, so armour and blades are metal and leather is not. Metal needs something to reflect: indoor scenes got a hidden dim sky for reflections (`Scenery._light`). 16x anisotropic filtering, FSR sharpness 0.25, a fine-grain third sampling in the ground shader. A relaxed `Calm` animation (BG3 `*_IDLE_Still_Peace_01`) was added to the standard animation set for story scenes.
- Camera (battle): wheel zooms toward the pointer with easing (3.2 to 52 m), +/- keys, R/F tilt, pinch on a touchpad, Space recentres; the wheel is left to the combat log when the pointer is over it. `TAVERN_ZOOM=4` frames the first hero for screenshots.
- Rules (2026-11-17): two-weapon fighting (`Combat.offhand`, light weapons only, no ability bonus to damage; rogue now carries shortsword + dagger + shortbow), cover (+2/+5), level cap 8 (XP 14000/23000/34000, second ability increase at 8, wizard/sorcerer lightning-bolt and ice-storm).
- Story stage (2026-11-17): `ui/stage.gd` replaces the slowly turning diorama. It builds the place as a small stage (props kept off the middle), the party arrives from the left, whoever the DM names as `speaker` walks in opposite and the lead hero steps up to them, the camera frames the pair above the dialogue box. What the player says drives the cast (`Stage.intent`: talk/approach, set out/leave/walk, look around); on leaving the party walks off, a black curtain falls, and the next scene lifts it as the party arrives again. `Scenery.build` takes `opts {scene, mood}`; `Scenery.SCENE_LOOK` tints fog, ambient and sun per painted scene (haunted marsh is a green night, infernal forge red, underdark blue). Narration words (night, dusk) choose the mood outdoors. `TAVERN_ACT="Talk to someone nearby"` says something to the party after 7 s for screenshots. The dialogue box is lower (speaker face beside the words), panel text margins now clear the painted frame, the battle hint sits on a dark pill.
- Ambience (2026-11-17): `Game.ambience_for(template, mood)` loops BG3 beds (tavern murmur, forest, dense wood, owlbear cave, dark forest with crickets at night, dungeon drip, campfire/torch crackle) as layered players with fades; used by battle and the story stage; the menu fades them out. Exported by `audio.sh` (stereo; the quad beds need `-ac 2`). Beds are the long recordings of an event (a bed is at least 8 s), shorter ones are one-shots and are skipped.
- Animations: the BG3 `CROWD_*` talk clips are for another skeleton (stretched necks): do not use them. The stage uses `Greet` (raised hand) for the lead hero; `Talk` (`CINE_GestureRight...`) exists only on some rigs and silently falls back to the calm stance.
- Rest menu (2026-11-17): `ui/rest.gd` (B or the Rest button in the story): short or long rest with BG3's rest icons, applies it to the living party, a campfire burns on the stage for a few seconds (`Stage.camp`).
- Faces and people (2026-11-17, after "textures look cheap"): found the cause. Heads were baked from one pigment map (HMVY) at half size, so faces were pale masks and eyes flat discs. `creature.skin_png` now bakes at 2048 and adds the cavity shading (Shading_MSKA blue channel), lips and eyebrows (CLEA map), pores and a little contrast; `creature.eye_png` bakes sclera, streaked iris, limbal ring and pupil from the eye masks and makes eyes glossy (`rough` in the material dict). In Godot `Scenery.polish_character` gives every person skin sub-surface scattering, a stronger normal map (1.45), a thin rim, and puts them on render layer 2; `Scenery.character_lights` adds a key and a cool rim that only layer 2 receives. `tools/bg3/face.gd model.glb out.png` renders a face close-up to judge this (`POLISH=1` applies the polish). Story: the camera cuts to an over-the-shoulder close-up of the speaker while they talk (`Stage.set_shot`). NPC "sliding" was a bug: the speaking gesture started while the NPC was still walking and replaced the walk clip; walk clips now run at the speed that matches the move (BG3 walk about 1.8 m/s, run about 3.9 m/s) and gestures wait for arrival.
- Lighting overhaul (2026-11-17, after comparing with real BG3 screenshots: dark rooms, pools of warm light with a hard fall-off, shiny floors, light shafts in fog, graded colour, muted earthy open country): indoor ambient is low (dungeon 0.16, tavern 0.28, cave 0.7), torches are 6.5 energy / 10 m with attenuation 1.5 (`flicker` uses each light's `base` meta), fire pits 10 / 15 m, floors have a template `gloss` (dungeon 0.42, tavern 0.5, cave 0.55) with worn variation in `ground.gdshader` and screen-space reflections indoors, volumetric fog 1.8x with a stronger sun shaft, split-toned colour grade (cool shadows, warm highlights) through `adjustment_color_correction`, contrast 1.18, open country desaturated to 0.92 with sun 2.7 and ambient 0.5, ground tint greener/olive per template, finer grass (6 thin blades, lit like the ground, varied hues), scattered small stones (`bg3clutter`), a frame vignette. Characters stand on a thin glowing ring instead of a filled disc. Moss patches were dropped (they read as black stains).
- Rendering: 3D is drawn at about 1440p inside a 4K window (`Game._fit_resolution`, scale 0.667 x quality factor), FSR 1 + FXAA, MSAA off (FSR 2 gave better edges but cost 10 fps on the GTX 1650: 22 vs 33 fps). About 25-27 fps at 4K, much more at 1440p windows.
- Inside-out meshes (found 2026-11-17): every converted mesh had its triangles turned round twice and its decoded normals pointing into the surface, so everything was inside out and only looked right because the materials are double sided. Rocks showed it as pitch-black shaded sides. `gr2gltf.py` now keeps the winding (the Z mirror already flips it) and negates the decoded QTangent normal; all props and heroes were regenerated. If an old model shows black sides, regenerate it.
- TODO next (autonomous run, in order): story screen dialogue style + speaker portrait; BG3-style title screen; tavern/forest/cave walls & dressing; combat polish (floating text, hit/death effects, status icons); armour variety; more D&D rules (levels past 5, more spells, feats, subclasses, reactions, opportunity attacks UI, spell upcasting picker, short/long rest, inventory/equipment screen, character sheet screen); music/ambience; verify everything with screenshots.
- Not done: icons and fonts do not load BG3 yet; sound stops at raw `.wem` (needs `vgmstream-cli`); models are matte
  (metal map unused); player-race bodies and scenery untested.
- `assets/bg3/` is gitignored and must stay out of git and off the internet. Credits for game-icons SVGs are only
  needed while those are still used.

## Round of 2026-11-17 evening (playtest feedback: bald heroes, race looks, voices, creator choices)
- **Characters are assembled at run time** (`board/assemble.gd`): a bare body with head and horns per race and sex (`players/base_<race>_<f|m>.glb`),
  an outfit per class and look (`outfit_<class>_<a|b>_<f|m>.glb`, cut for the human body, bound to bones by name so it fits every race),
  hair and beards baked white and tinted by the chosen colour, and a strand map painted on the crown (`scalp_*.png`: the hair mesh holds only the locks
  that hang, the crown comes from the head's Scalp_Mesh). Parts are built by `tools/bg3/players.py` into `players/` (gitignored, has a `.gdignore` so Godot does
  not import them). The BG3 data drive is not mounted at /mnt/wdblack any more: `udisksctl mount -b /dev/nvme0n1p2 -o ro`, then `BG3_DATA="/run/media/$USER/New Volume/Games/Baldur's Gate 3/Data"`.
  `Assemble.character(spec)` is used by `Scenery.character` (battle, story stage, menu), the creator, portraits (`Game.portrait`, `Game.bust_spec`) and story NPCs
  (`Scenery.npc_spec`). Without the parts the old per-class models are used.
- Why heroes were bald and chests poked through robes: hair meshes lack the crown; hair made for another rig hung too low (`gr2gltf` now retargets part
  vertices to the body's bind pose); the body's vertex colour (green channel) numbers body regions and outfits name the regions they cover
  (`VertexColorMaskSlots`), so `Assemble.hide_regions` cuts those triangles out of the body. Eyes: `polish_character` no longer gives eyeballs subsurface scatter and rim light.
- Not done: tails (a tail hung on the body skeleton sticks out as a flat blade), hats and helmets (outfits are built without headwear so hair and horns show),
  dragonborn scale colour is a pale default, body skin is a flat tone next to the detailed face, skin tone choice.
- **Spoken story** (`ui/voice.gd`, `tools/tts`): Kokoro text-to-speech on the CPU. Set up: `cd tools/tts && uv venv .venv && uv pip install --python .venv/bin/python kokoro-onnx soundfile`
  and put `kokoro-v1.0.int8.onnx` and `voices-v1.0.bin` (kokoro-onnx release model-files-v1.0) in `tools/tts/models`. The narrator reads the narration, a speaker's `says` is read in a voice
  picked from their name and kind (`Voice.voice_for`). Space or the Skip button ends it; menu and pause screen toggle it. Test with `TAVERN_VOICE_TEST=1 ... --audio-driver Dummy`.
- **Choices with skill checks**: the DM may return a choice as `{text, skill, dc, requires}`. `skill`+`dc` shows `[Persuasion DC 14]` and rolls it for the best hero when picked;
  `requires` shows the option only if a living hero is proficient (a wizard sees the Arcana option, a fighter does not). Tooltip gives the success chance.
- **Creator** (`ui/build_panel.gd`): hair style and colour, beard, outfit look, point-buy ability scores (27 points, racial bonuses shown), class skill picks (+ rogue expertise),
  fighting style, cantrips and first level spells (only spells the engine can resolve). Picks live in the slot's `extra` and go into the hero spec (`Game.make_hero(..., extra)`).
- **Magic Missile / Scorching Ray** (`Combat.cast(..., aims)`): one click per dart or ray, each can target a different foe; Enter sends the rest at the last target. Rays make their own spell attack rolls.
- Smaller: round soft particles instead of squares (`Scenery.soft_dot`), a painted backdrop behind the story stage (`Stage._backdrop`), `TAVERN_CREATE="wizard,tiefling,woman,560"` hook for creator screenshots.

## Round of 2026-11-17 night (playtest fixes, more spells)
- Victory screen: the Continue / Fight again button sits under the banner (the hotbar is empty after a win, so a hotbar button was never drawn).
- Click-to-approach (`Battle._reach`, `_approach_then`): clicking a lone target out of reach of the picked weapon, action (Help 30 ft, Shove, Lay on Hands, strikes) or
  single-target spell walks to the nearest square that reaches it and then acts, if the movement left allows; otherwise the hint says how many feet of walking are needed.
- Spells added (`rules/combat.gd` `SPECIAL`): Bane, Heroism, Hideous Laughter, Color Spray, Blindness/Deafness, Command, Hypnotic Pattern, Stinking Cloud, Slow, Haste,
  Spirit Guardians (aura, start of the foe's turn), Lesser Restoration, Expeditious Retreat, Longstrider, Barkskin, True Strike, Spare the Dying. Shield is a reaction cast
  automatically when it turns a hit into a miss (`REACTIONS`, `selectable()`; no prompt yet). Shortcuts: Heroism heals instead of temporary hit points, Haste's extra action is any
  action and its tiredness is not modelled, Stinking Cloud only costs the first turn.
- Misty Step (`Combat.misty_step`, any free square within 30 ft, bonus action). Upcasting: with a spell picked press U to step through the slot levels that have a slot left
  (hint shows the level; default is still the lowest). The Help/Shove/Off-hand hint text no longer fails on a missing key.
- Still missing: Revivify (needs a dead target), Mirror Image, reaction prompts (Shield fires by itself).
- Test hooks added to `TAVERN_CLICKS`: `e now` ends the turn, `p x,y` puts the nearest foe there. With `TAVERN_SHOT` set the click hook no longer quits, the screenshot does.
- Story stage: floating hero names are hidden (the portrait column shows them).

## Performance (2026-11-17 night, GTX 1650 Mobile Max-Q 4 GB, 2784x1566 panel)
- Measured with `TAVERN_PERF=<seconds>` (fps, CPU and GPU ms of the main viewport, draw calls, triangles, VRAM; `TAVERN_INVENTORY=1` lists the heaviest meshes).
  Switches for tests: `TAVERN_SCALE=0.7` (fixed 3D scale, no governor), `TAVERN_GOV=off`, `TAVERN_FX_OFF=ssao,ssr,fog,glow,grade,sun,torch,motes,cheap`.
- Finding: GPU-bound (about 32 ms GPU against 1.5 to 5 ms CPU at scale 0.98, which the "Sharp" setting gave). A scene is about 600k triangles in one pass, about 1100 draw
  calls once shadow passes are counted. No single effect dominates: SSR, volumetric fog, glow, the grade, torch shadows and the sun shadow each cost about 3 to 5 ms.
  Do NOT benchmark while another game window is open: two processes time-slice the GPU and every number is wrong (7 fps measured against 30).
- Done: (1) adaptive resolution governor in `game.gd` (`_process`): the picture setting is the ceiling (Fast 720p, Balanced 1080p, Sharp the full window), the governor
  steps the internal resolution so the median GPU time stays under 92% of the refresh interval, floor scale 0.42, last stable scale saved in settings; (2) torch and fire
  shadows use two paraboloid passes instead of a six-face cube and switch off beyond 24 m from the camera (`Scenery.cheap_shadow`); (3) project settings: directional shadow map 2048,
  SSAO quality low, smaller fog volume (48x48x40), linear glow upscale; sun shadow distance 45 m.
- To do with a clean GPU: measure the real cost per effect at 1080p, then decide SSR (blocky stair steps in floor reflections), SSAO and volumetric fog settings,
  try FSR 2 (temporal, sharper) against FSR 1, hair meshes (20k triangles each) as non-shadow-casters, Godot mesh LODs for runtime-loaded BG3 models.

## In progress: interface and graphics overhaul (paused 2026-11-16, uncommitted)
The user asked for a Baldur's Gate 3 inspired look (inspiration only, original art): portraits everywhere, richer
selection screens, pictures and interaction instead of text only, and less childlike in-game graphics.
Done so far (on disk, not committed, screens not yet re-checked after the change):
- `assets/fonts` (Cinzel for titles, EB Garamond for text, OFL) and `assets/icons` (58 game-icons.net SVGs,
  CC BY 3.0, black background stripped; credit needed in a credits file).
- `ui/ui.gd` rewritten: `make_theme()`, `title()`, `rule()`, `text_button()`, `icon_button()`, `picture()`, `sheet()`,
  `vignette()`, portraits with a class emblem placeholder, depth of field on `orbit_camera()`.
Still to do, in this order:
1. `game.gd`: set `get_tree().root.theme = Ui.make_theme()` in `_ready`.
2. Battle screen: bottom hotbar of `icon_button`s (portrait, action/bonus/move pips, End Turn), restyled turn strip and log.
3. Story screen: dialogue layout (speaker name and portrait, numbered `text_button` answers), a generated scene
   picture per place, a dice-roll overlay for checks (DC, d20, click to roll). DM JSON gains `"speaker": {name, look}`.
4. Menu: text-list main menu; party creation with slots on the left, a close-up of the 3D hero in the middle,
   race/class icon grids and the stat summary on the right; story hints as a second step.
5. Lighting: ACES tonemap, lower saturation, stronger contrast, vignette, dusk sky outdoors.
6. Ask the user about characters: the KayKit chibi models are what looks childlike. Found CC0 realistic-proportion
   bases (Quaternius Universal Base Characters + Universal Animation Library, in the GitHub repo
   NafisRayan/Animate-Rigged-Humanoid-No-Blender) but no fantasy outfits or monsters for them; the outfit pack is on
   itch.io and needs the user to download it. Poly Haven and ambientCG (CC0, direct download) can supply realistic
   props and floor/wall textures.
