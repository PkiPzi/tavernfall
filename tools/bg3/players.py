#!/usr/bin/env python3
"""Build the parts the game fits together into player characters (see board/assemble.gd).

  players.py bases      a bare body with head (horns, tail) for each race and sex: base_<race>_<f|m>.glb
  players.py outfits    each class's clothes, cut for the human body, in two looks: outfit_<class>_<a|b>_<f|m>.glb (+ .hide.txt)
  players.py hair       hairstyles and beards, baked white so the game can tint them: hair_<name>.glb
  players.py scalps     the strand maps painted on the crown under a hairstyle: scalp_<style>.png (white, tinted by the game)
  players.py all
Output: players/ (gitignored, .gdignore). Skips what exists. Needs BG3_DATA when the game folder is not at the default path.
Run a few at once with: players.py bases & players.py outfits & players.py hair & wait
"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "../../players")  # outside assets/ and marked .gdignore: Godot would otherwise import (and duplicate) every part

# Tails (TIF_*_NKD_Tail_A, DGB_*_NKD_Tail_A) are left out for now: hung on the body skeleton they stick out as a flat blade.
# race -> sex -> (character visual to take body, head and skin from, extra parts such as a tail)
RACES = {
    "human": {"f": ("BASE_Humans_Female_e87dd6f0", []), "m": ("BASE_Humans_Male_000_3b46b020", [])},
    "elf": {"f": ("BASE_Elves_Female_4c3d8aa0", []), "m": ("BASE_Elves_Male_003_f60fa5f2", [])},
    "half-elf": {"f": ("BASE_HalfElves_Female_ebd9d3bf", []), "m": ("BASE_HalfElves_Male_cee79608", [])},
    "tiefling": {"f": ("BASE_Tieflings_Female_5b11557c", []), "m": ("BASE_Tieflings_Male_000_712e1cef", [])},
    "dwarf": {"f": ("BASE_Dwarves_Female_b98a80f4", []), "m": ("BASE_Dwarves_Male_000_4edee83e", [])},
    "halfling": {"f": ("BASE_Halflings_Female_000_02513907", []), "m": ("BASE_Halflings_Male_Guild_e8b7c255", [])},
    "gnome": {"f": ("BASE_Gnomes_Female_05047890", []), "m": ("BASE_Gnomes_Male_Regular_b2b58122", [])},
    "dragonborn": {"f": ("BASE_Dragonborn_Female_366faff6", []), "m": ("BASE_Dragonborn_Male_97ad09df", [])},
    "half-orc": {"f": ("BASE_HalfOrcs_Female_a31730e7", []), "m": ("BASE_HalfOrcs_Male_0350f048", [])},
}
# class -> the story characters whose clothes make the two looks
NPCS = {
    "barbarian": ["S_LOW_HagSurvivors_Bandit_Barbarian_01", "S_LOW_AradinThug1"], "bard": ["S_LOW_HagSurvivors_Bandit_Bard_01", "S_GLO_Volo"],
    "fighter": ["S_LOW_HagSurvivors_Bandit_Fighter_01", "S_CHA_FL1_BanditGuard"], "paladin": ["S_LOW_HagSurvivors_Bandit_Paladin_01", "S_GLO_GithKnight"],
    "warlock": ["S_LOW_HagSurvivors_Bandit_Warlock_01", "S_GOB_Warlock"], "wizard": ["S_LOW_HagSurvivors_Bandit_Wizard_01", "S_CHA_Exterior_Bandit_Caster_01"],
    "sorcerer": ["S_CHA_Exterior_Bandit_Caster_01", "S_LOW_HagSurvivors_Bandit_Wizard_01"],
    "cleric": ["S_END_VeteranCleric", "S_LOW_BaldursGate_FlamingFist_Cleric_001"], "rogue": ["S_LOW_BhaalTemple_UnholyAssassin_01", "S_LOW_Park_BhaalAssassin01"],
    "ranger": ["S_CHA_Exterior_Bandit_Ranger_01", "S_END_GurHunter_002"], "druid": ["S_END_GurHunter_001", "S_WYR_GurCamp_Hunter_001"],
    "monk": ["S_LOW_BhaalTemple_Cultist_01", "S_LOW_BhaalTemple_Cultist_02"],
}
HAIR_F = ["Straight_Short_L", "Straight_Short_E", "Straight_Short_A", "Straight_Short_C_Spring", "Straight_Long_B_Spring", "Straight_Long_D",
          "Curly_Long_A_Spring", "Curly_Short_A", "Afro_Short_A", "Braids_Long_B", "Braids_Short_B", "Dreads_Long_A_Spring", "Wavy"]
HAIR_M = ["Straight_Short_C", "Straight_Short_G", "Straight_Short_J", "Straight_Long_A_Spring", "Wavy_Short_A", "Wavy_Long_B", "Curly_Short_A",
          "Afro_Short_A", "Braids_Long_B_Spring", "Dreads_Short_A", "Straight_Short_E", "Wavy_Short_D"]
BEARDS = ["Short_A", "Short_C", "Short_G", "Short_L", "Long_A", "Long_D", "Long_E"]


def run(out, *args):
    """Build one part; returns how many animations it got (-1 if the build failed)."""
    if os.path.exists(out):
        return 99
    os.makedirs(OUT, exist_ok=True)
    cmd = ["uv", "run", "-q", "--with", "lz4", "--with", "zstandard", "--with", "numpy", "python", os.path.join(HERE, "creature.py"), out + ".tmp", *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    line = (r.stdout.strip().splitlines() or [(r.stderr.strip().splitlines() or ["?"])[-1]])[-1]
    print(line, flush=True)
    if os.path.exists(out + ".tmp"):  # written whole before it takes its name, so two runs never leave half a file
        os.replace(out + ".tmp", out)
        if os.path.exists(out + ".tmp.hide.txt"):
            os.replace(out + ".tmp.hide.txt", out + ".hide.txt")
    import re
    m = re.search(r"(\d+) animations", line)
    return int(m.group(1)) if m else -1


def bases():
    for race, sexes in RACES.items():
        for sex, (cv, extra) in sexes.items():
            out = f"{OUT}/base_{race}_{sex}.glb"
            borrow = race in ("dragonborn", "half-orc")  # their own rigs have few clips: the human clips fit (bones match by name)
            if borrow:
                run(out, cv, *extra, "--bare", "--rig", f"HUM_{sex.upper()}_Rig")
            elif run(out, cv, *extra, "--bare") < 7:  # a race whose rig has few clips of its own borrows the human ones (bones match by name)
                os.remove(out)
                run(out, cv, *extra, "--bare", "--rig", f"HUM_{sex.upper()}_Rig")


def outfits():
    for cls, npcs in NPCS.items():
        for look, npc in zip("ab", npcs):
            for sex in "fm":
                run(f"{OUT}/outfit_{cls}_{look}_{sex}.glb", npc, "--dress", "--sex", sex.upper(), "--skel", f"HUM_{sex.upper()}_Base", "--anims", "none")


def hair():
    for sex, names in (("F", HAIR_F), ("M", HAIR_M)):
        for n in names:
            run(f"{OUT}/hair_{sex.lower()}_{n}.glb", f"HAIR_HUM_{sex}_{n}", "--skel", f"HUM_{sex}_Base", "--white-hair", "--anims", "none")
    for n in BEARDS:
        run(f"{OUT}/beard_{n}.glb", f"BEARD_HUM_M_{n}", "--skel", "HUM_M_Base", "--white-hair", "--anims", "none")


def scalps():
    import creature, index
    creature.con = index.db()
    os.makedirs(OUT, exist_ok=True)
    for _, _, _, tex in creature.SCALPS:
        out = f"{OUT}/scalp_{tex}.png"
        if os.path.exists(out):
            continue
        row = creature.con.execute("select source from res where bank='Texture' and source like ? escape '\\' limit 1", (f"%/{tex}\\_Scalp.DDS",)).fetchone()
        mask = row and creature.dds_png(row[0], 1)
        if mask:
            os.replace(creature.hair_png(mask, [1, 1, 1], 1), out)
            print("scalp", tex, flush=True)


if __name__ == "__main__":
    for step in (sys.argv[1:] or ["all"]):
        if step in ("bases", "all"): bases()
        if step in ("outfits", "all"): outfits()
        if step in ("hair", "all"): hair()
        if step in ("scalps", "all"): scalps()
