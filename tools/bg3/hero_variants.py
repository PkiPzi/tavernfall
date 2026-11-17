#!/usr/bin/env python3
"""Build the second look of each hero class: python3 hero_variants.py [class ...]
Each variant is another dressed BG3 NPC. If the first conversion has fewer than 7 animations, the generic
human rigs are tried (HUM_M_Rig, HUM_F_Rig) and the best result is kept."""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "../../assets/bg3/models")
VARIANTS = {
    "fighter": "S_CHA_FL1_BanditGuard", "rogue": "S_LOW_Park_BhaalAssassin01", "ranger": "S_END_GurHunter_002",
    "wizard": "S_CHA_Exterior_Bandit_Caster_01", "cleric": "S_LOW_BaldursGate_FlamingFist_Cleric_001",
    "barbarian": "S_LOW_AradinThug1", "bard": "S_GLO_Volo", "paladin": "S_GLO_GithKnight", "warlock": "S_GOB_Warlock",
    "monk": "S_LOW_BhaalTemple_Cultist_02", "druid": "S_WYR_GurCamp_Hunter_001",
}

def build(name, rig):
    out = os.path.join(OUT, f"hero_{name}_b.glb")
    cmd = ["uv", "run", "-q", "--with", "lz4", "--with", "zstandard", "--with", "numpy", "python", os.path.join(HERE, "creature.py"), out, VARIANTS[name]]
    if rig:
        cmd += ["--rig", rig]
    res = subprocess.run(cmd, capture_output=True, text=True)
    m = re.search(r"(\d+) animations", res.stdout)
    return int(m.group(1)) if m else -1

for name in (sys.argv[1:] or VARIANTS):
    best = (build(name, ""), "")
    for rig in ("HUM_M_Rig", "HUM_F_Rig"):
        if best[0] >= 7:
            break
        n = build(name, rig)
        if n > best[0]:
            best = (n, rig)
    if best[1]:
        build(name, best[1])  # leave the best rig's file on disk
    print(name, best)
