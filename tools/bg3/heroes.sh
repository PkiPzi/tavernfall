#!/usr/bin/env zsh
# Build the 12 hero models (one dressed story NPC per class) and the monster models into assets/bg3/models/.
# Usage: ./heroes.sh [name ...]   (no names = all; the hero_ prefix is part of the name)
cd "$(dirname "$0")"
M=../../assets/bg3/models; mkdir -p $M
run() { uv run -q --with lz4 --with zstandard --with numpy python "$@"; }
declare -A SRC=(
 [hero_barbarian]="S_LOW_HagSurvivors_Bandit_Barbarian_01_9b19aa71-7d43-4f63-9aee-dd9a5e09fede --rig HUM_M_Rig"
 [hero_bard]="S_LOW_HagSurvivors_Bandit_Bard_01_ede83d7d-ba00-4064-aa8c-0bab713b3518"
 [hero_fighter]="S_LOW_HagSurvivors_Bandit_Fighter_01_4e3bb260-3d2e-48b0-86cf-c2693592915b --rig HUM_F_Rig"
 [hero_paladin]="S_LOW_HagSurvivors_Bandit_Paladin_01_2eda24ed-9fca-4020-b514-4e041a1247f8 --rig HUM_M_Rig"
 [hero_warlock]="S_LOW_HagSurvivors_Bandit_Warlock_01_1802e84d-f136-43c6-9c41-2c934ae56fa3 --rig HUM_M_Rig"
 [hero_wizard]="S_LOW_HagSurvivors_Bandit_Wizard_01_e17a32d6-78e5-4c33-b718-c548c058aac4"
 [hero_cleric]="S_END_VeteranCleric_df1fc277-0c4d-4e55-82f5-65f89aeb4c39 --rig HUM_F_Rig"
 [hero_rogue]="S_LOW_BhaalTemple_UnholyAssassin_01_d00763c7-cac6-47b8-86be-a13ddd346861"
 [hero_ranger]="S_CHA_Exterior_Bandit_Ranger_01_fa1a1fbd-2152-40e4-b53d-29e95d54279e --rig HUM_M_Rig"
 [hero_druid]="S_END_GurHunter_001_4a0d7314-d355-40ff-95d3-eca357dd305c"
 [hero_monk]="S_LOW_BhaalTemple_Cultist_01"
 [goblin]="S_SCL_DriderCaravan_GoblinMelee_000 --rig GOB_M_Rig"
 [owlbear]="Owlbear_000"
 [skeleton]="SHA_Skeleton_Melee"
 [zombie]="BASE_Undead_Zombie_a42a8493-b701-4d71-bdc8-0857e718c247"
 [ogre]="BASE_Ogres"
 [gnoll]="BASE_Gnolls"
 [kobold]="BASE_Kobolds"
 [ghoul]="GHOUL_Body_A"
 [wolf]="CINE_BASE_Quadruped_Beast_Wolf_05835354-5b81-4296-89b6-d458235abecc"
 [spider]="BASE_Quadruped_Beast_Spider"
 [rat]="RAT_A"
)
names=("$@"); [ ${#names[@]} -eq 0 ] && names=(${(k)SRC})
for n in "${names[@]}"; do
  [ -n "${SRC[$n]}" ] || continue
  run creature.py $M/$n.glb ${=SRC[$n]} 2>&1 | tail -1
done
