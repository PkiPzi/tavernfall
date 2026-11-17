# Baldur's Gate 3 asset tools

Turn the user's own BG3 install into files Godot can load: models with skeleton, textures and
animations (`.glb`), icons and interface art (`.png`), fonts, and sound.

**The output is copyrighted game data for the user's private use. It lives in `assets/bg3/`, which is
gitignored. Never commit it, never upload it anywhere.**

- Game data: `/mnt/wdblack/Games/Baldur's Gate 3/Data` (read-only; override with `BG3_DATA`).
- Cache: `~/.cache/tavernfall-bg3/` (`index.db` 1 GB, `tex/` converted textures, `*.gts` texture tables,
  `out/` test models). `raw/` and `src/` there are leftovers from working out the formats and can be deleted.
- Needs: `uv`, `cc`, ImageMagick (`magick`), Godot. Nothing else. No LSLib, no Blender, no Wine.

Run everything from this folder like this (the scripts import each other):

    cd tools/bg3
    run() { uv run -q --with lz4 --with zstandard --with numpy python "$@"; }

## The one command you mostly need

    run creature.py ../../assets/bg3/models/goblin.glb S_SCL_DriderCaravan_GoblinMelee_000 --rig GOB_M_Rig

The name is a **CharacterVisual** (a whole dressed character) or a **Visual** (one monster, weapon, prop).
The result is right-handed, faces +Z, is in metres, and carries animations named
`idle walk run attack shoot cast hit die` (whichever exist for that skeleton).

    run index.py find owlbear CharacterVisual     # find names
    run index.py find WPN_HUM_Longsword Visual
    run creature.py x.glb Owlbear_000 --list       # every animation the skeleton has
    run creature.py x.glb Owlbear_000 --anims 'Roar|Sleep'   # pick by regex, or `all` / `none`

- `--rig PREFIX` adds animations whose name starts with PREFIX. Use it when `--list` is short: the female
  goblin body has 205 animations and no attack, the male rig `GOB_M_Rig` has 994, and the bones match by name.
- `--level 0|1|2` texture size: full, half (default), quarter. Half is plenty for a tabletop camera.
- Extra names after the first are added on the same skeleton (body plus a helmet Visual).

Look at a result without opening the editor (always with the scratch saves folder and mute):

    cd ../.. && TAVERN_MUTE=1 TAVERN_SAVES=/tmp/x godot --path . -s tools/bg3/view.gd -- model.glb shot.png [animation] [seconds] [yaw]

Checked this way: goblin in armour (all 8 animations), owlbear, armoured skeleton, greataxe, treasure chest.

Useful name families: `BASE_<Race>_<Female|Male>...` (player races and civilians), `Owlbear_000`,
`SHA_Skeleton_Melee`, `BASE_Undead_Zombie`, `BASE_Ogres`, `BASE_Bugbears`, `BASE_Gnolls`, `BASE_Kobolds`,
`BASE_Quadruped_Beast_Spider`, `BASE_Mindflayer`; Visuals `WPN_*` weapons, `CONT_*` containers, `FUR_*` furniture,
`DEC_*` decoration. Names starting `S_` or with a level prefix (`GOB_`, `LOW_`, `WYR_` ...) are placed story characters
and usually come fully dressed, which makes them the best picks for enemies.

## Icons, interface art, fonts

Already exported into `assets/bg3/` (214 MB, re-run is cheap, existing files are kept):

| Folder | What | Count |
|---|---|---|
| `icons/skills` | spell and action icons, 144 px, e.g. `spell_evocation_fireball.png`, `action_barbarian_rage.png` | 1522 |
| `icons/items` | item icons, 144 px | 3045 |
| `icons/classes` | class and subclass emblems (`fighter.png`, `lifedomain.png`). The small hotbar versions share these names and were skipped; export `*/classicons/hotbar/*` to its own folder if wanted | 59 |
| `icons/races` | race icons | 39 |
| `icons/resources` | action, bonus action, spell slot pips | 195 |
| `dice` | d20 faces 1 to 20 and roll frames | 25 |
| `fonts` | Alegreya, Alegreya Sans, Quadraat (the game's title face) | 23 |

More with the same tool (glob is matched on the lower-cased path inside the pak):

    run images.py Game.pak 'public/game/gui/assets/tooltips/icons/*' ../../assets/bg3/icons/big 256   # 380 px originals
    run lspk.py list "$BG3_DATA/Game.pak" '*gui/assets/*' | less                                       # browse

Worth a look under `public/game/gui/assets/`: `bottombar` (hotbar frames), `buttons`, `shared` (panels, frames),
`characterpanel`, `dialogue`, `activeroll` and `diceroll` (the roll overlay), `loadingscreen`, `book`, `map`,
`playerportraits`, `cc/icons_backgrounds`, `cc/icons_deities`. Folders ending `_c` are the controller layout.

## Sound

    run audio.py find Fireball
    run audio.py export Spell_Impact_Damage_Fireball_L5 ../../assets/bg3/audio

**Not finished.** The lookup from an event name to its numbered recordings works for simple effects. The last
step, turning Wwise `.wem` into `.ogg`, needs `vgmstream-cli` and `ffmpeg` (installed now);
without it the raw `.wem` is written, which Godot cannot play. Music and layered events (`Music_*`, some
cinematic ones) return 0 recordings: their soundbank objects use a structure `audio.py` only guesses at.

## What each file does

| File | Job |
|---|---|
| `lspk.py` | list and extract `.pak` archives |
| `lsf.py` | read the game's binary resource files into plain dicts |
| `index.py` | `build` once: every resource of every pak into sqlite, plus which pak holds which file. `find`, `show` |
| `codecs.c` | the two decompressors nothing in Python has: BitKnit2 (models) and FastLZ (texture tiles). Built on first use |
| `gr2.py` | read a Granny `.gr2` model or animation file |
| `gr2anim.py` | decode animation curves into glTF keyframes |
| `gr2gltf.py` | meshes, skeleton and skinning into `.glb` (plain, grey). Mirrors Z, the game is left-handed |
| `vtex.py` | cut one texture out of the game's streamed "virtual textures" |
| `creature.py` | ties it together: name, parts, materials, textures, animations, one `.glb` |
| `images.py` | bulk DDS to PNG and font copy |
| `audio.py` | sound event to recordings (see above) |
| `view.gd` | render a `.glb` to a PNG in Godot |
| `check.sh` | smoke test: builds a chest and a goblin and checks the counts |

How the game links things, for when a model comes out wrong:
CharacterVisual (base body, slots, colour overrides) → Visual (a `.gr2` and one material per mesh) → Material
(shader name, textures, colours) → Texture (`.dds`) or VirtualTexture (32-hex name, read by `vtex.py`).
`run index.py show <name-or-id>` prints any of them. A name can exist in several banks (a Visual and its
Material often share one), so in code use `index.get(con, name, "Visual")`.

## How materials are approximated

The game's shaders are compiled, so `creature.material()` bakes the common cases into a plain colour texture:

- **Skin** has no colour texture in the game. It is mixed from four pigment colours by a mask; that mix is baked.
  Close, a little flat.
- **Armour and clothes** are stored grey and dyed by a mask whose colour names the dye slot. The slot table (`DYE`)
  is read from the game's own reference textures; three slots are inferred, noted in the code.
- **Feathers** are tinted with the average of the body texture. **Fur, hair, feathers** use cut-out transparency.
- **Eyes** get a flat colour. Tear lines, lash shadows and other overlay meshes are dropped.

Not done, in order of how much it would show:
1. The metal/roughness map (`_physical.png` from `vtex.py`) is extracted but not put in the `.glb`; everything is
   matte. Wire it in `gr2gltf.convert` as `metallicRoughnessTexture` after checking which channel is which.
2. Normal maps assume the DirectX green direction and are flipped for glTF. Not confirmed by eye; if lighting on
   armour looks inside-out, drop the flip in `creature.vt_png`.
3. Hair colour, tattoos, makeup, scars, glow.
4. Scenery, effects, terrain, whole levels: untested. Single props work.
5. Player-race bodies (`BASE_Humans_*` and friends) are untested; they have separate head, hair and outfit Visuals
   that must be listed together on one command line.

## What to do next in the game (for whoever picks this up)

The hard part is done; what is left is ordinary Godot work. In order:

1. Monsters: convert one model per monster kind the game uses into `assets/bg3/models/`, and load them where the
   KayKit models are loaded now. Animation names are fixed (`idle`, `attack`, `hit`, `die`...), so one loader fits all.
2. Heroes: try `BASE_<Race>_<Sex>` plus outfit Visuals; fall back to dressed story characters per class.
3. Icons: replace the `assets/icons` SVGs in `ui/ui.gd` with `assets/bg3/icons` (class emblems, spell icons,
   resource pips), and the fonts with Quadraat for titles and Alegreya for text.
4. Then the paused overhaul list in `DESIGN.md` (theme hookup, battle hotbar, dialogue layout, dice overlay with
   `assets/bg3/dice`, menu, lighting).
5. If a build must work without the BG3 files, keep the old assets as a fallback when `assets/bg3` is missing.


## Added later (2026-11-17): everything the game uses

| Script | What it makes |
|---|---|
| `heroes.sh [name ...]` | the 12 hero models (`hero_<class>.glb`, one dressed story NPC per class) and the monster models in `assets/bg3/models/`. The table in the script says which BG3 name and which `--rig` each one uses |
| `props.sh <VisualName> ...` | static props, wall pieces, weapons, torches into `assets/bg3/props/<name>.glb` |
| `ui_export.sh` | BG3's own interface art (hotbar, buttons, portrait rings, dice, loading screens, character creation) into `assets/bg3/ui/<folder>/` |
| `glbsize.py a.glb ...` | bounding box in metres of converted files |
| `bust_sheet.gd` | `godot --path . -s tools/bg3/bust_sheet.gd -- out.png` renders every model's portrait bust into one contact sheet |

Terrain textures: `images.py Textures.pak "*/tt_<name>_bma.dds" ../../assets/bg3/terrain 1024` (and `_nm`). BMA is base colour, NM the normal map (x in alpha, y in green).

Material fixes worth knowing: the body skin material (`CHAR_Skin_Body`) uses a VT that is the underwear, so `build()` copies the head's average skin tone onto it; hair, beards and brows are baked from their strand mask and the character's `Hair_Color`; `Helper_Invisible` meshes are skipped. The Origin companions (Gale, Karlach...) are stored naked, so the game uses dressed `S_*` NPCs instead. Some bodies need `--rig HUM_M_Rig` or `HUM_F_Rig` to get their combat animations.
