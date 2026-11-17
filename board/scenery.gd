extends RefCounted
const Assemble = preload("res://board/assemble.gd")
# Builds the places: floor, walls, props, lights and the character models.
# Used by the battle board and by the story screen's diorama.

const W := 16
const H := 12
const CELL := 1.5   # metres: one 5 ft square, so BG3 models are life size

# Per template: floor tiles, slow ground, props that block a square [model, size],
# wall pieces, wall decoration, light colours.
const TEMPLATES = {
	"dungeon": {
		"tex": ["tt_paving_dungeon_marble_c", "tt_ground_dirt_rocks_gravel_a"], "tile": 4.5, "gloss": 0.42, "ambient_energy": 0.16,
		"floor": ["floor_tile_small", "floor_tile_small", "floor_tile_small", "floor_tile_small",
			"floor_tile_small_broken_A", "floor_tile_small_broken_B", "floor_tile_small_weeds_A", "floor_tile_small_weeds_B"],
		"rough": ["floor_dirt_small_A", "floor_dirt_small_B", "floor_dirt_small_C", "floor_dirt_small_D"],
		"props": [["pillar", 0.5], ["barrel_large", 0.5], ["box_large", 0.55], ["crates_stacked", 0.42], ["column", 0.7]],
		"bg3props": [["BLD_Bhaal_Temple_Pillar_B", 4.2, 1.2], ["CONT_Barrel_A", 1.2, 1.0], ["CONT_Emerald_Enclave_Crate_Wood_A", 1.0, 1.0],
			["CONT_Emerald_Enclave_Crate_Wood_B", 1.0, 1.0], ["DEC_CEM_Tombstone_A", 1.3, 0.8], ["FUR_Cazador_Sarcophagus_A", 2.6, 0.6],
			["DEC_Dungeon_Skull_Pile_Medium_A", 1.8, 0.4], ["DEC_Bhaal_Statue_Grim_Reaper_A", 2.6, 0.5], ["CONT_GEN_Chest_Common_A", 0.8, 0.5]],
		"walls": ["wall", "wall", "wall", "wall_cracked"], "deco": "banner_patternA_red",
		"bg3clutter": [["NAT_Rock_Boulder_A_Brown", 0.15, 0.45, 26], ["NAT_Cave_Plant_Fern_I", 0.5, 0.8, 4]],
		"bg3sets": [
			{"cells": [2, 2], "items": [["FUR_Cazador_Sarcophagus_A", 0, 0, 0, 2.4], ["DEC_Dungeon_Skull_Pile_Medium_A", 1.3, 0.9, 0.5, 0.9]]},
			{"cells": [2, 1], "items": [["DEC_GEN_BrokenColumn_A", -0.4, 0, 0.3, 2.0], ["BLD_Bhaal_Wall_Rubble_Mid_A", 0.6, 0.1, 1.0, 1.6]]},
			{"cells": [1, 1], "items": [["DEC_Bhaal_Statue_Grim_Reaper_A", 0, 0, 0.6, 2.6]]},
			{"cells": [2, 1], "items": [["CONT_GEN_Chest_Common_A", -0.4, 0, 0.1, 1.0], ["DEC_Dungeon_Skull_Pile_Medium_A", 0.7, 0.2, 2.0, 0.8], ["CONT_Barrel_A", 0.9, -0.2, 0, 1.1]]},
			{"cells": [1, 1], "items": [["DEC_CEM_Tombstone_A", 0, 0, 0.2, 1.3]]},
		],
		"bg3sets_count": 5,
		"bg3walls": ["WALL_Dungeon_Temple_A_1D_6H_4W_S_Piece_A", "WALL_Dungeon_Temple_A_1D_6H_4W_S_Piece_B"], "bg3post": "BLD_Bhaal_Temple_Pillar_B",
		"ambient": Color("7f8ab5"), "torch": Color("ff9040"), "fog": 0.025, "prop_rate": 0.09, "rough_rate": 0.12,
	},
	"tavern": {
		"tex": ["tt_floor_wood_oak_a", "tt_floor_wood_oak_parquet_a"], "tile": 3.0, "gloss": 0.5, "ambient_energy": 0.28,
		"floor": ["floor_wood_small", "floor_wood_small", "floor_wood_small_dark"],
		"rough": ["floor_wood_small_dark"],
		"props": [["table_small", 0.5], ["barrel_large", 0.5], ["keg", 0.5], ["stool", 0.6], ["chair", 0.55], ["box_small", 0.6]],
		"bg3props": [["CONT_Barrel_A", 1.2, 1.0], ["CONT_Emerald_Enclave_Crate_Wood_A", 1.0, 1.0], ["CONT_GEN_Chest_Common_A", 0.9, 0.8], ["CONT_Barrel_A", 1.2, 1.0]],
		"walls": ["wall", "wall_shelves", "wall_window_closed", "wall"], "deco": "banner_patternB_yellow",
		# composed furniture: footprint in cells [w, d], items [model, dx, dz (m from the centre), yaw, longest side (m), lift (m)], turned 90 degrees half the time
		"bg3sets": [
			{"cells": [3, 2], "items": [["DEC_GEN_Hide_Rugs_Cow_A", 0, 0, 0.3, 2.2], ["FUR_GEN_Table_Wood_Poor_A", 0, 0, 0, 2.7], ["FUR_GEN_Bench_Wood_Poor_A", 0, -1.0, 0, 2.4],
				["FUR_GEN_Bench_Wood_Poor_A", 0, 1.0, PI, 2.4], ["FUR_GEN_Chair_Wood_Poor_A", 1.75, 0, -PI / 2, 1.0]]},
			{"cells": [2, 2], "items": [["FUR_GEN_Table_Common_B", 0, 0, 0, 2.5], ["FUR_GEN_Stool_Wood_Poor_A", -0.7, -0.95, 0.4, 0.6], ["FUR_GEN_Stool_Wood_Poor_A", 0.7, 0.95, 2.0, 0.6],
				["FUR_GEN_Chair_Wood_Poor_A", 1.5, 0, -PI / 2, 1.0], ["FUR_GEN_Chair_Wood_Poor_A", -1.5, 0, PI / 2, 1.0]]},
			{"cells": [2, 1], "items": [["CONT_GEN_Burlap_Sack_A", -0.5, 0.1, 0.5, 0.9], ["CONT_GEN_Burlap_Sack_B", 0.35, -0.1, 2.2, 0.8], ["CONT_GEN_Crate_Fruit_Wood_A", 0.2, 0.25, 0.1, 1.0]]},
			{"cells": [2, 1], "items": [["DEC_Farm_Hay_Bale_A", -0.55, 0, 0.1, 1.1], ["DEC_Farm_Hay_Bale_A", 0.6, 0.1, -0.3, 1.1]]},
			{"cells": [1, 1], "light": 1, "items": [["LTS_GEN_Candle_Candelabra_Common_A_Standing_A", 0, 0, 0, 1.9]]},
		],
		"bg3sets_count": 6,
		# a bar along the far wall: two counters with kegs behind
		"bg3bar": {"at": [6, 0], "cells": [4, 1], "items": [["FUR_GEN_Kitchen_Counter_A_6W_A", -1.5, 0.1, 0, 3.0], ["FUR_GEN_Kitchen_Counter_A_6W_A", 1.5, 0.1, 0, 3.0],
			["CONT_Barrel_A", -2.5, -0.9, 0, 1.2], ["CONT_Barrel_A", 2.4, -0.9, 0.5, 1.2]]},
		"bg3walls": ["WALL_Dungeon_Abbey_House_A_1D_5H_4W_S_Piece_A", "WALL_Dungeon_Abbey_House_A_1D_5H_4W_S_Piece_B", "WALL_Dungeon_Abbey_House_A_1D_5H_4W_S_Piece_C"],
		"ambient": Color("b59a7f"), "torch": Color("ffb060"), "fog": 0.01, "prop_rate": 0.06, "rough_rate": 0.0,
	},
	"cave": {
		"tex": ["tt_ground_rock_granite_b", "tt_ground_mud_soil_a"], "tile": 5.0, "gloss": 0.55,
		"floor": ["floor_dirt_small_A", "floor_dirt_small_B", "floor_dirt_small_C", "floor_dirt_small_D", "floor_dirt_small_weeds"],
		"rough": ["floor_tile_small_broken_A", "floor_tile_small_broken_B"],
		"props": [["column", 0.7], ["box_small", 0.6], ["barrel_small", 0.6], ["trunk_small_A", 0.6]],
		"bg3cliffs": [["NAT_Cliff_Boulder_A_Grey", 6.5, 9.5], ["NAT_Cliff_Boulder_B_Brown", 6.0, 9.0]], "ambient_energy": 0.7, "sun": 0.8,
		"bg3props": [["NAT_Cave_Speleothem_Column_A_Large_A_Grey", 3.5, 1.2], ["NAT_Cave_Speleothem_Stalagmite_A_Cluster_A_Grey", 1.8, 1.4],
			["NAT_Rock_Boulder_A_Brown", 1.5, 1.0], ["CONT_Barrel_A", 1.2, 0.4], ["DEC_Dungeon_Skull_Pile_Medium_A", 1.8, 0.5]],
		"bg3clutter": [["NAT_Rock_Boulder_A_Brown", 0.2, 0.6, 30], ["NAT_Cave_Plant_Fern_A", 0.6, 1.0, 14], ["NAT_Cave_Plant_Fern_E", 0.7, 1.1, 10], ["DEC_NAT_Fungi_Mushroom_Agaric_B", 0.25, 0.4, 14]],
		"bg3sets": [
			{"cells": [3, 2], "fire": [0.0, 0.3], "items": [["DEC_GEN_Market_Tent_Poor_B", 0, -0.8, 0, 3.4], ["CONT_GEN_Burlap_Sack_A", -1.3, 0.6, 0.8, 0.8], ["CONT_Emerald_Enclave_Crate_Wood_A", 1.4, 0.5, 0.2, 0.9],
				["DEC_Dungeon_Skull_Pile_Medium_A", 1.3, -0.9, 1.0, 0.8]]},
			{"cells": [2, 1], "items": [["DEC_Dungeon_Skull_Pile_Medium_A", 0, 0, 0.4, 1.5], ["NAT_Rock_Boulder_A_Brown", 0.9, 0.2, 1, 0.9]]},
			{"cells": [2, 1], "items": [["CONT_GEN_Chest_Common_A", -0.3, 0, 0.3, 1.0], ["CONT_GEN_Burlap_Sack_B", 0.6, 0.1, 2, 0.8]]},
		],
		"bg3sets_count": 3,
		"walls": ["wall_broken", "wall_cracked", "wall"], "deco": "",
		"ambient": Color("5f7a8f"), "torch": Color("ffa860"), "fog": 0.05, "prop_rate": 0.1, "rough_rate": 0.18,
	},
	# Open-air places: a flat coloured ground instead of floor tiles, trees instead of walls, daylight.
	"forest": {
		"tex": ["tt_forest_grass_b", "tt_forest_soil_c"], "tile": 5.0,
		"ground": Color("3c5a2a"), "mud": Color("4a3d28"), "edge": ["trees_A_medium", "trees_B_medium", "trees_A_small", "tree_single_A"],
		"props": [["tree_single_A", 1.0], ["tree_single_B", 1.0], ["rock_single_A", 1.2], ["rock_single_C", 1.2], ["tree_single_A_cut", 1.0]],
		"bg3props": [["NAT_Rock_Boulder_A_Brown", 1.6, 1.2], ["NAT_Rock_Boulder_A_Brown", 2.2, 1.2], ["NAT_Cliff_Boulder_B_Brown", 2.4, 1.0],
			["NAT_Tree_Dead_Fallen_A", 3.6, 0.8], ["CONT_GEN_Berry_Bush_A", 1.7, 1.0], ["CONT_GEN_Berry_Bush_A", 1.4, 1.0]],
		"bg3edge": [["NAT_Tree_Beech_B", 12.0, 17.0], ["NAT_Tree_Beech_Thin_A", 12.0, 18.0], ["NAT_Tree_Aspen_A", 8.0, 11.0],
			["NAT_Tree_Cork_Small_A", 6.0, 8.0], ["NAT_Tree_Cypress_A", 8.0, 12.0]],
		"bg3sets": [
			{"cells": [3, 2], "fire": [0.0, 0.5], "items": [["DEC_GEN_Market_Tent_Poor_B", 0, -0.7, 0, 3.6], ["NAT_Tree_Log_A", -1.2, 1.0, 0.2, 1.8], ["NAT_Tree_Log_A", 1.3, 0.9, -0.3, 1.6],
				["CONT_GEN_Burlap_Sack_A", -1.1, -0.5, 0.8, 0.8], ["CONT_Emerald_Enclave_Crate_Wood_A", 1.2, -0.6, 0.2, 0.9]]},
			{"cells": [2, 2], "items": [["NAT_Coastal_Plant_Bush_Pine_Medium_A", -0.5, -0.3, 0, 1.9], ["NAT_Coastal_Plant_Bush_Pine_Medium_A", 0.6, 0.4, 2, 1.5], ["NAT_Coastal_Plant_Bush_Pine_Medium_A", 0.3, -0.7, 4, 1.2]]},
			{"cells": [2, 1], "items": [["NAT_Tree_Log_A", 0, 0, 0.4, 2.6], ["DEC_NAT_Fungi_Mushroom_Agaric_A", 0.5, 0.35, 0, 0.3], ["DEC_NAT_Fungi_Mushroom_Agaric_A", 0.7, 0.2, 1, 0.22]]},
			{"cells": [2, 2], "items": [["NAT_Coastal_Plant_Bush_Pine_Medium_A", 0, 0, 1, 2.2], ["NAT_Rock_Boulder_A_Brown", 0.9, 0.6, 0, 1.2]]},
			{"cells": [1, 1], "items": [["DEC_NAT_Fungi_Mushroom_Agaric_A", -0.2, 0, 0, 0.3], ["DEC_NAT_Fungi_Mushroom_Agaric_A", 0.2, 0.15, 2, 0.22], ["DEC_NAT_Fungi_Mushroom_Agaric_A", 0, -0.2, 4, 0.26]]},
		],
		"bg3sets_count": 5,
		"tint": Color(0.8, 0.86, 0.62), "relief": 0.55, "bg3clutter": [["NAT_Rock_Boulder_A_Brown", 0.22, 0.7, 40], ["NAT_Cave_Plant_Fern_E", 0.7, 1.1, 26], ["NAT_Cave_Plant_Fern_A", 0.6, 0.9, 20], ["DEC_NAT_Fungi_Mushroom_Agaric_A", 0.2, 0.35, 12]], "grass": {"base": Color("3a4a1c"), "tip": Color("8a9648"), "density": 36, "height": 0.2}, "ambient": Color("a8c49a"), "fog": 0.012, "prop_rate": 0.12, "rough_rate": 0.1,
	},
	"road": {
		"tex": ["tt_forest_grass_a", "tt_gravel_a"], "tile": 5.0,
		"ground": Color("5b6b34"), "mud": Color("6b5638"), "edge": ["trees_A_small", "rock_single_D", "tree_single_B", "rock_single_E"],
		"props": [["rock_single_B", 1.2], ["crate_A_small", 1.3], ["barrel", 1.3], ["sack", 1.3], ["wheelbarrow", 1.1], ["tree_single_A", 1.0]],
		"bg3props": [["NAT_Rock_Boulder_A_Brown", 1.4, 1.2], ["CONT_Emerald_Enclave_Crate_Wood_A", 1.0, 1.0], ["CONT_Barrel_A", 1.2, 1.0],
			["NAT_Rock_Boulder_A_Brown", 1.9, 1.0], ["CONT_GEN_Berry_Bush_A", 1.6, 1.0]],
		"bg3edge": [["NAT_Tree_Beech_Thin_A", 10.0, 16.0], ["NAT_Tree_Aspen_A", 7.0, 10.0], ["NAT_Tree_Cork_Small_A", 5.0, 7.0], ["NAT_Tree_Cypress_A", 8.0, 11.0]],
		"tint": Color(0.86, 0.95, 0.7), "relief": 0.35, "bg3clutter": [["NAT_Rock_Boulder_A_Brown", 0.2, 0.6, 40], ["NAT_Cave_Plant_Fern_I", 0.6, 0.9, 14]], "grass": {"base": Color("4a5222"), "tip": Color("a8a468"), "density": 24, "height": 0.18}, "ambient": Color("c9c2a0"), "fog": 0.006, "prop_rate": 0.07, "rough_rate": 0.0, "track": true,
	},
}

# Which model and which of its built-in gear each class shows.
# shortcut: the pack has no mace or goblin; clerics carry a sword and every monster is a skeleton
# until more CC0 packs are added.
const LOOK = {
	"fighter": ["Knight", ["1H_Sword", "Rectangle_Shield", "Knight_Helmet"]],
	"rogue": ["Rogue_Hooded", ["Knife", "Knife_Offhand"]],
	"cleric": ["Knight", ["1H_Sword", "Badge_Shield"]],
	"wizard": ["Mage", ["2H_Staff"]],
	"barbarian": ["Barbarian", ["2H_Axe"]],
	"bard": ["Rogue_Hooded", ["1H_Crossbow"]],
	"druid": ["Mage", ["2H_Staff", "Round_Shield"]],
	"monk": ["Barbarian", []],
	"paladin": ["Knight", ["2H_Sword", "Knight_Helmet"]],
	"ranger": ["Rogue_Hooded", ["2H_Crossbow"]],
	"sorcerer": ["Mage", ["1H_Wand"]],
	"warlock": ["Mage", ["Spellbook_open"]],
}
# The pack has only skeletons for monsters, so the kind of creature shows as a tint (and its size as scale).
const KIND_TINT = {"humanoid": Color("9fc27a"), "beast": Color("b08a5a"), "giant": Color("9aa3b5"), "fiend": Color("d0553f"),
	"dragon": Color("c0453a"), "ooze": Color("6fd08a"), "plant": Color("5fa04a"), "fey": Color("c79be0"),
	"elemental": Color("6fc0e0"), "aberration": Color("a070c0"), "monstrosity": Color("c0a060"), "construct": Color("8a8a95"),
	"celestial": Color("ffe9a0")}
const GEAR = ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword",
	"2H_Sword", "Knight_Helmet", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable", "Spellbook",
	"Spellbook_open", "1H_Wand", "2H_Staff", "1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug"]
# BG3 models (tools/bg3, gitignored assets/bg3). SRD index -> file; anything else falls back to the KayKit skeletons.
# Heroes are dressed BG3 characters, one per class (race is ignored): hero_<class>.glb.
const BG3_HERO = {"sorcerer": "wizard"}
# How tall a hero of each race stands next to a human: the model is the same, the size is not.
const RACE_SCALE = {"halfling": 0.74, "gnome": 0.72, "dwarf": 0.86, "half-orc": 1.07, "dragonborn": 1.1, "half-elf": 1.0, "elf": 1.02, "tiefling": 1.0, "human": 1.0}
const BG3_ANIM = {"Talk": "talk", "Greet": "greet", "Calm": "calm", "Idle": "idle", "Running_A": "run", "Walking_A": "walk", "1H_Melee_Attack_Chop": "attack", "2H_Ranged_Shoot": "shoot",
	"Hit_A": "hit", "Spellcast_Shoot": "cast", "Death_A": "die"}
const MONSTERS = ["Skeleton_Warrior", "Skeleton_Rogue", "Skeleton_Minion", "Skeleton_Mage"]

static func mat(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

# Which model stands in for someone the story describes ("old bearded priest", "goblin scout"). Keyword first, then a stable pick.
const NPC_WORDS = {"goblin": "goblin", "skeleton": "skeleton", "undead": "skeleton", "zombie": "zombie", "ghoul": "ghoul", "ogre": "ogre", "giant": "ogre",
	"gnoll": "gnoll", "kobold": "kobold", "wolf": "wolf", "spider": "spider", "rat": "rat", "owlbear": "owlbear",
	"priest": "hero_cleric", "cleric": "hero_cleric", "acolyte": "hero_cleric", "monk": "hero_monk", "wizard": "hero_wizard", "mage": "hero_wizard",
	"sage": "hero_wizard", "scholar": "hero_wizard", "bard": "hero_bard", "innkeeper": "hero_bard", "merchant": "hero_bard", "minstrel": "hero_bard",
	"guard": "hero_fighter", "soldier": "hero_fighter", "knight": "hero_paladin", "paladin": "hero_paladin", "thief": "hero_rogue",
	"rogue": "hero_rogue", "assassin": "hero_rogue", "spy": "hero_rogue", "hunter": "hero_ranger", "ranger": "hero_ranger", "scout": "hero_ranger",
	"druid": "hero_druid", "hermit": "hero_druid", "witch": "hero_warlock", "warlock": "hero_warlock", "cultist": "hero_warlock", "barbarian": "hero_barbarian"}
const NPC_PEOPLE = ["hero_bard", "hero_fighter", "hero_ranger", "hero_cleric", "hero_druid", "hero_rogue", "hero_monk"]

static func npc_model(look: String) -> String:
	var low := look.to_lower()
	for w in NPC_WORDS:
		if w in low:
			return "res://assets/bg3/models/%s.glb" % NPC_WORDS[w]
	return "res://assets/bg3/models/%s.glb" % NPC_PEOPLE[absi(low.hash()) % NPC_PEOPLE.size()]

# A person in the story, built from parts like a hero: race, sex, hair and clothes follow from the words that describe them.
static func npc_spec(look: String, cls: String) -> Dictionary:
	var low := " " + look.to_lower() + " "
	var h := absi(look.to_lower().hash())
	var female := false
	for w in [" woman", " girl", " lady", " queen", " witch", " priestess", " maid", " mother", " wife", " daughter", " sister", " duchess", " matron", " hag", " female", " she "]:
		if w in low:
			female = true
	if not female and not (" man" in low or " male" in low or " king" in low or " lord" in low or " father" in low or " boy" in low or " brother" in low):
		female = h % 2 == 0
	var race := "human"
	for r in [["half-orc", "half-orc"], [" orc", "half-orc"], ["dwarf", "dwarf"], ["dwarven", "dwarf"], ["half-elf", "half-elf"], [" elf", "elf"], ["elven", "elf"], ["halfling", "halfling"],
			["gnome", "gnome"], ["tiefling", "tiefling"], ["dragonborn", "dragonborn"]]:
		if r[0] in low:
			race = r[1]
			break
	if race == "human" and h % 7 == 3:
		race = ["elf", "dwarf", "halfling", "half-elf", "tiefling", "gnome"][(h / 7) % 6]
	var sex := "f" if female else "m"
	var d := Assemble.default_look(h % 100000, sex)
	var old := " old" in low or "elder" in low or "ancient" in low or "grey" in low or "white-haired" in low
	var spec := {"race": race, "sex": sex, "cls": cls, "look": "a" if h % 2 == 0 else "b", "hair": d.hair,
		"hair_color": Assemble.HAIR_COLORS["Grey" if old else d.hair_color], "beard": d.beard}
	if sex == "m" and ("beard" in low or old or "dwarf" in low):
		spec.beard = Assemble.BEARDS[(h / 5) % Assemble.BEARDS.size()]
	return spec

# The spec of the person that npc_actor builds for these words, or {} when there are no player parts or the words name a creature.
static func npc_person(look: String) -> Dictionary:
	var stem := npc_model(look).get_file().get_basename()
	if not Assemble.available() or not stem.begins_with("hero_"):
		return {}
	return npc_spec(look, stem.trim_prefix("hero_").trim_suffix("_b"))

# What makes a BG3 character read as a real person rather than a plastic figure: skin that lets light bleed through,
# a stronger fabric and skin relief, a thin rim of light that separates the figure from the background, and
# the extra lights that only characters receive (a key from the camera side and a cool rim from behind).
static func polish_character(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 | 2  # layer 2 is lit by the character lights
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			if not (m is BaseMaterial3D):
				continue
			var d: BaseMaterial3D = m.duplicate()
			var part := str(mi.name).to_upper()
			if "EYES" in part:  # eyeballs: wet and clean. Subsurface and rim light made them glow orange.
				d.roughness = 0.12
				d.metallic_specular = 0.9
				mi.set_surface_override_material(i, d)
				continue
			if "MOUTH" in part or "HAIR" in part or "SCALP" in part:
				mi.set_surface_override_material(i, d)
				continue
			var skin: bool = "NKD" in str(m.resource_name) or "Head" in str(m.resource_name) or "Body" in str(m.resource_name) or "NKD" in str(mi.name)
			if d.normal_enabled:
				d.normal_scale = 1.45
			d.rim_enabled = true
			d.rim = 0.12
			d.rim_tint = 0.6
			if skin and not "ARM" in str(mi.name):
				d.subsurf_scatter_enabled = true
				d.subsurf_scatter_strength = 0.18
				d.subsurf_scatter_skin_mode = true
			mi.set_surface_override_material(i, d)

# Two lights for characters only (they sit on render layer 2): a warm key from the front left and a cool rim from behind.
static func character_lights(parent: Node3D, key_energy := 0.3) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, -35, 0)
	key.light_energy = key_energy
	key.light_color = Color("ffe6c8")
	key.light_cull_mask = 2
	key.shadow_enabled = false
	parent.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 150, 0)
	rim.light_energy = key_energy * 0.9
	rim.light_color = Color("a8c4ff")
	rim.light_cull_mask = 2
	rim.shadow_enabled = false
	parent.add_child(rim)

# A bystander for the story stage: the BG3 model for a look ("old bearded priest"), idle, at a world position. -> {node, ap}
static func npc_actor(parent: Node3D, look_text: String, at: Vector3) -> Dictionary:
	var path := npc_model(look_text)
	var node := Node3D.new()
	node.position = at
	parent.add_child(node)
	var ap: AnimationPlayer = null
	var scale_used := 1.0
	var stem0 := path.get_file().get_basename()
	var person: Node3D = null
	if stem0.begins_with("hero_") and Assemble.available():
		person = Assemble.character(npc_spec(look_text, stem0.trim_prefix("hero_").trim_suffix("_b")))
	if person != null or ResourceLoader.exists(path):
		var model: Node3D = person if person != null else load(path).instantiate()
		var stem := path.get_file().get_basename()
		model.scale = Vector3.ONE * (1.0 if stem.begins_with("hero_") else clampf(1.0 / STEM_SIZE.get(stem, 1.0), 0.4, 2.8))
		scale_used = model.scale.x
		node.add_child(model)
		polish_character(model)
		ap = model.find_child("AnimationPlayer", true, false)
		if ap != null:
			var lib := ap.get_animation_library("")
			for k in BG3_ANIM:
				if lib.has_animation(BG3_ANIM[k]):
					lib.add_animation(k, lib.get_animation(BG3_ANIM[k]))
			for a in ["Idle", "Calm", "Talk", "Running_A", "Walking_A"]:
				if ap.has_animation(a):
					ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
			var rest := "Calm" if ap.has_animation("Calm") else "Idle"
			if ap.has_animation(rest):
				ap.play(rest)
				ap.seek(randf())
	return {"node": node, "ap": ap, "scale": scale_used}

# Weapons in the hands of a hero model: the main weapon in the right hand (bows in the left), a shield on the left arm.
# The weapon files are authored around the grip, so they go on the hand dummy bones as they are.
const WEAPON_MODEL = {"longsword": "WPN_HUM_Longsword_A_0", "greataxe": "WPN_HUM_Greataxe_A_0", "rapier": "WPN_HUM_Rapier_A_0",
	"shortbow": "WPN_HUM_Shortbow_A_0", "longbow": "WPN_HUM_Longbow_A_0", "dagger": "WPN_HUM_Dagger_A_0", "handaxe": "WPN_HUM_Handaxe_A_0",
	"mace": "WPN_HUM_Mace_A_0", "quarterstaff": "WPN_HUM_Quarterstaff_A_0", "shortsword": "WPN_HUM_Shortsword_A_0",
	"javelin": "WPN_HUM_Javelin_A_0", "scimitar": "WPN_HUM_Scimitar_A_0"}
const LEFT_HAND = ["shortbow", "longbow"]

static func _hold(sk: Skeleton3D, bone: String, file: String, tag: String) -> void:
	var path := "res://assets/bg3/props/%s.glb" % file
	var idx := sk.find_bone(bone)
	if idx < 0 or not ResourceLoader.exists(path):
		return
	for old in sk.get_children():
		if old.name == tag:
			old.queue_free()
	var att := BoneAttachment3D.new()
	att.name = tag
	att.bone_name = bone
	sk.add_child(att)
	var item: Node3D = load(path).instantiate()
	item.scale = Vector3.ONE * 0.85  # the game's weapons read a little long next to these models
	att.add_child(item)

static func equip(model: Node3D, c) -> void:
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk == null:
		return
	var ws: Array = c.spec.get("weapons", [])
	if not c.is_pc:  # dressed monsters carry the weapon of their first attack
		if not model_path(c).contains("hero_") or c.attacks.is_empty():
			return
		ws = [str(c.attacks[0].name).to_lower().replace(" ", "")]
	if not ws.is_empty() and WEAPON_MODEL.has(ws[0]):
		_hold(sk, "Dummy_L_Hand" if ws[0] in LEFT_HAND else "Dummy_R_Hand", WEAPON_MODEL[ws[0]], "MainHand")
	if c.is_pc and c.spec.get("shield", false):
		_hold(sk, "Dummy_L_Hand", "WPN_HUM_Shield_A_0", "OffHand")
	elif c.is_pc and ws.size() > 1 and ws[1] in ["dagger", "shortsword", "handaxe", "scimitar"] and WEAPON_MODEL.has(ws[1]):  # a second light blade in the other hand
		_hold(sk, "Dummy_L_Hand", WEAPON_MODEL[ws[1]], "OffHand")

# Which BG3 model a monster uses: the first word of the SRD name that matches, else by creature type.
# Orcs, bandits, cultists and the like use the dressed human models and carry their own weapon.
const MONSTER_WORDS = [["owlbear", "owlbear"], ["spider", "spider"], ["swarm", "rat"], ["rat", "rat"], ["bat", "rat"], ["hobgoblin", "goblin"],
	["bugbear", "goblin"], ["goblin", "goblin"], ["kobold", "kobold"], ["gnoll", "gnoll"], ["skeleton", "skeleton"], ["zombie", "zombie"],
	["ghoul", "ghoul"], ["ghast", "ghoul"], ["wight", "ghoul"], ["wraith", "ghoul"], ["specter", "ghoul"], ["ghost", "ghoul"], ["mummy", "zombie"],
	["ogre", "ogre"], ["troll", "ogre"], ["giant", "ogre"], ["ettin", "ogre"], ["oni", "ogre"], ["bear", "owlbear"], ["wolf", "wolf"], ["worg", "wolf"],
	["jackal", "wolf"], ["hyena", "wolf"], ["dog", "wolf"], ["lion", "wolf"], ["tiger", "wolf"], ["panther", "wolf"], ["boar", "wolf"],
	["orc", "hero_barbarian"], ["berserker", "hero_barbarian"], ["thug", "hero_barbarian"], ["tribal", "hero_barbarian"], ["bandit", "hero_rogue"],
	["assassin", "hero_rogue"], ["spy", "hero_rogue"], ["scout", "hero_ranger"], ["cult", "hero_warlock"], ["mage", "hero_wizard"],
	["acolyte", "hero_cleric"], ["priest", "hero_cleric"], ["druid", "hero_druid"], ["guard", "hero_fighter"], ["knight", "hero_paladin"],
	["veteran", "hero_fighter"], ["gladiator", "hero_fighter"], ["noble", "hero_bard"], ["commoner", "hero_bard"]]
const KIND_MODEL = {"humanoid": "hero_fighter", "undead": "skeleton", "beast": "wolf", "giant": "ogre", "dragon": "owlbear", "fiend": "ghoul",
	"aberration": "spider", "monstrosity": "owlbear", "elemental": "ogre", "construct": "hero_fighter", "plant": "owlbear", "ooze": "zombie",
	"celestial": "hero_cleric", "fey": "hero_druid", "swarm of Tiny beasts": "rat"}
const STEM_SIZE = {"goblin": 0.8, "kobold": 0.8, "rat": 0.6, "wolf": 1.0, "ogre": 1.45, "owlbear": 1.45, "spider": 1.0, "skeleton": 1.0, "zombie": 1.0,
	"ghoul": 1.0, "gnoll": 1.0}

static func monster_stem(c) -> String:
	for pair in MONSTER_WORDS:
		if pair[0] in c.index:
			return pair[1]
	return KIND_MODEL.get(c.kind, "")

# The BG3 model file of a creature, or "" when it has none.
static func model_path(c) -> String:
	var n: String = ("hero_" + BG3_HERO.get(c.cls, c.cls)) if c.is_pc else monster_stem(c)
	if c.is_pc and int(c.spec.get("variant", 0)) == 1 and ResourceLoader.exists("res://assets/bg3/models/%s_b.glb" % n):
		n += "_b"  # the second look of the class
	return "res://assets/bg3/models/%s.glb" % n if n != "" else ""

# How much to scale the model so the creature has the size its stat block says. Heroes: by race.
static func model_scale(c) -> float:
	if c.is_pc:
		return RACE_SCALE.get(c.spec.get("race", ""), 1.0)
	var stem := monster_stem(c)
	if stem.begins_with("hero_"):
		return clampf(c.size, 0.7, 2.6)  # people are about 1.0 at Medium
	return clampf(c.size / STEM_SIZE.get(stem, 1.0), 0.4, 2.8)

static func world(cell: Vector2i) -> Vector3:
	var x := (cell.x + 0.5) * CELL
	var z := (cell.y + 0.5) * CELL
	return Vector3(x, height_at(x, z), z)

# Gentle hills on open ground (templates with "relief" = highest rise in metres). One float per quarter metre over the board,
# sampled here for placement and by ground.gdshader for the mesh, so they always agree.
static var relief: Image = null

static func make_relief(t: Dictionary) -> void:
	relief = null
	if not t.has("relief") or not ResourceLoader.exists("res://assets/bg3/terrain/%s_bma.png" % t.tex[0]):
		return
	var rw := W * 4
	var rh := H * 4
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.022
	n.fractal_octaves = 2
	relief = Image.create(rw, rh, false, Image.FORMAT_RF)
	for x in rw:
		for y in rh:
			var edge := minf(minf(x, rw - 1 - x), minf(y, rh - 1 - y)) * 0.25  # metres from the border: hills die out toward the rim
			relief.set_pixel(x, y, Color(n.get_noise_2d(x, y) * float(t.relief) * smoothstep(0.0, 4.0, edge), 0, 0))

# Ground height in metres at a point on the board.
static func height_at(x: float, z: float) -> float:
	if relief == null:
		return 0.0
	var fx := clampf(x / (W * CELL), 0.0, 1.0) * (relief.get_width() - 1)
	var fz := clampf(z / (H * CELL), 0.0, 1.0) * (relief.get_height() - 1)
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, relief.get_width() - 1)
	var z1 := mini(z0 + 1, relief.get_height() - 1)
	var ax := fx - x0
	var az := fz - z0
	return lerpf(lerpf(relief.get_pixel(x0, z0).r, relief.get_pixel(x1, z0).r, ax), lerpf(relief.get_pixel(x0, z1).r, relief.get_pixel(x1, z1).r, ax), az)

# How far to lift flat markers (square highlights, footsteps) so a slope does not swallow them.
static func lift() -> float:
	return 0.05 if relief == null else 0.28

static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

static func box(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

# A KayKit dungeon model. They are built on a 2 m grid, so half size fits our 1 m cells.
static func piece(parent: Node, id: String, pos: Vector3, turn := 0.0, size := 0.5) -> Node3D:
	var path := "res://assets/kaykit/dungeon/%s.gltf.glb" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/kaykit/dungeon/%s.glb" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/kaykit/nature/%s.gltf" % id
	var n: Node3D = load(path).instantiate()
	n.position = pos
	n.rotation.y = turn
	n.scale = Vector3.ONE * size * CELL
	parent.add_child(n)
	return n

# A BG3 prop (assets/bg3/props), scaled so its longest side is `height` metres, centred on pos and sitting on the ground.
# Returns null when the file is missing so callers can fall back to the KayKit piece.
static func bg3_prop(parent: Node3D, name: String, pos: Vector3, yaw: float, height: float) -> Node3D:
	var path := "res://assets/bg3/props/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = load(path).instantiate()
	parent.add_child(n)
	_tame_metal(n, name)
	if not name.begins_with("WPN_"):
		for mi in n.find_children("*", "MeshInstance3D", true, false):  # static props: skinning only gets in the way (tiny scales darkened the normals)
			mi.skin = null
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y < 0.01:
		n.queue_free()
		return null
	var k := height / maxf(box.size.x, maxf(box.size.y, box.size.z))
	var c := box.get_center()
	n.scale = Vector3.ONE * k
	n.rotation.y = yaw
	n.position = pos + Vector3(-c.x, -box.position.y, -c.z).rotated(Vector3.UP, yaw) * k
	return n

# One wall segment: its inner face on the line through pos, standing on the ground, stretched along the wall.
# yaw 0 builds a wall behind pos (toward -z) that faces +z. Returns null when the file is missing.
static func bg3_wall(parent: Node3D, name: String, pos: Vector3, yaw: float, stretch := 1.0) -> Node3D:
	var path := "res://assets/bg3/props/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = load(path).instantiate()
	parent.add_child(n)
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		n.queue_free()
		return null
	var c := box.get_center()
	n.scale = Vector3(stretch, 1, 1)
	n.rotation.y = yaw
	n.position = pos + Vector3(-c.x * stretch, -box.position.y, -(box.position.z + box.size.z)).rotated(Vector3.UP, yaw)
	return n

static var _dot: GradientTexture2D
# A soft round dot for small particles: without a texture a particle is a hard square.
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot

# A flame of animated glowing particles at `at`, size 1 = a torch.
static func _flame(parent: Node3D, at: Vector3, size: float) -> void:
	var fire := GPUParticles3D.new()
	fire.position = at
	fire.amount = int(34 * size)
	fire.lifetime = 0.75
	fire.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.3 * size
	pm.initial_velocity_max = 0.8 * size
	pm.gravity = Vector3(0, 2.0 * size, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.7, 0.3, 0.34), Color(1, 0.34, 0.05, 0.3), Color(0.35, 0.05, 0.0, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.3) * size
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	qm.albedo_texture = rt
	quad.material = qm
	fire.draw_pass_1 = quad
	parent.add_child(fire)
	if size > 1.5:  # a big fire throws sparks
		var sp := GPUParticles3D.new()
		sp.position = at
		sp.amount = 14
		sp.lifetime = 1.6
		sp.local_coords = false
		var sm := ParticleProcessMaterial.new()
		sm.direction = Vector3(0, 1, 0)
		sm.spread = 30.0
		sm.initial_velocity_min = 0.8
		sm.initial_velocity_max = 1.8
		sm.gravity = Vector3(0, 0.3, 0)
		sm.scale_min = 0.5
		sm.scale_max = 1.0
		var sg := Gradient.new()
		sg.colors = PackedColorArray([Color(1, 0.8, 0.4, 1), Color(1, 0.4, 0.1, 0.8), Color(1, 0.2, 0.0, 0)])
		var sgt := GradientTexture1D.new()
		sgt.gradient = sg
		sm.color_ramp = sgt
		sp.process_material = sm
		var sq := QuadMesh.new()
		sq.size = Vector2(0.035, 0.035)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		smat.vertex_color_use_as_albedo = true
		smat.albedo_texture = soft_dot()
		sq.material = smat
		sp.draw_pass_1 = sq
		parent.add_child(sp)

# A campfire on the ground: the BG3 fire pit, a big flame, a warm light.
static func fire_pit(parent: Node3D, pos: Vector3, color: Color, shadows := true) -> OmniLight3D:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	bg3_prop(holder, "LTS_Camp_Campfire_A", Vector3.ZERO, randf() * TAU, 1.5)
	_flame(holder, Vector3(0, 0.35, 0), 2.2)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.0, 0)
	l.light_color = color
	l.light_energy = 10.0
	l.omni_range = 15.0
	l.omni_attenuation = 1.4
	l.set_meta("base", 10.0)
	l.shadow_enabled = shadows  # shadowed omni lights are the costly part of a night scene
	holder.add_child(l)
	return l

# A torch on a wall with a living flame and a flickering light. pos is on the wall face, out = direction into the room.
static func torch(parent: Node3D, pos: Vector3, out: Vector3, color: Color, shadows := true) -> OmniLight3D:
	var yaw := atan2(out.x, out.z)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	parent.add_child(holder)
	var stick := bg3_prop(holder, "WPN_HUM_Torch_A_0", Vector3(0, 0.1, 0.18), 0.0, 0.95)
	if stick != null:
		stick.rotation.x = deg_to_rad(-50.0)
	var tip := Vector3(0, 0.55, 0.45)
	_flame(holder, tip, 1.0)
	var l := OmniLight3D.new()
	l.position = tip + Vector3(0, 0.1, 0.25)
	l.light_color = color
	l.light_energy = 6.5  # a pool of warm light with a real fall-off, as in the game's dark rooms, not an even glow
	l.omni_range = 10.0
	l.omni_attenuation = 1.5
	l.set_meta("base", 6.5)
	l.shadow_enabled = shadows
	holder.add_child(l)
	return l

# The ground: one big mesh with two BG3 terrain materials blended by a mask (rough ground, roads).
static func ground(parent: Node3D, t: Dictionary, rough: Dictionary, road: bool, outdoor: bool) -> void:
	var ma := "res://assets/bg3/terrain/%s_bma.png" % t.tex[0]
	var m: Material
	if ResourceLoader.exists(ma):
		var img := Image.create(W, H, false, Image.FORMAT_L8)  # one pixel per cell, then smoothed into blobs
		for cell in rough:
			img.set_pixelv(cell, Color.WHITE)
		if road:
			for x in W:
				for y in [H / 2 - 1, H / 2]:
					img.set_pixel(x, y, Color.WHITE)
		img.resize(W * 16, H * 16, Image.INTERPOLATE_CUBIC)
		img.generate_mipmaps()
		var sm := ShaderMaterial.new()
		sm.shader = load("res://board/ground.gdshader")
		for i in 2:
			var base := "res://assets/bg3/terrain/%s" % t.tex[i]
			sm.set_shader_parameter("col_" + "ab"[i], load(base + "_bma.png"))
			sm.set_shader_parameter("nrm_" + "ab"[i], load(base + "_nm.png"))
		sm.set_shader_parameter("mask", ImageTexture.create_from_image(img))
		sm.set_shader_parameter("field_size", Vector2(W, H) * CELL)
		sm.set_shader_parameter("tile", t.tile)
		sm.set_shader_parameter("roughness_val", t.get("gloss", 0.85))
		if t.has("tint"):
			sm.set_shader_parameter("tint", t.tint)
		if relief != null:
			sm.set_shader_parameter("relief", ImageTexture.create_from_image(relief))
			sm.set_shader_parameter("relief_on", 1.0)
		m = sm
	else:  # no BG3 files on this machine: flat colour
		m = mat(t.get("ground", Color("3a3430")))
	var pm := PlaneMesh.new()
	var pad := 40.0 if outdoor else 0.0
	pm.size = Vector2(W * CELL + 2 * pad, H * CELL + 2 * pad)
	pm.subdivide_width = int(pm.size.x / 0.75) if relief != null else 8
	pm.subdivide_depth = int(pm.size.y / 0.75) if relief != null else 8
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(W * CELL / 2.0, 0.0, H * CELL / 2.0)
	parent.add_child(mi)

# A tuft: three crossed tapering blades, bent a little, about `height` metres tall.
static func _tuft(height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := k * PI / 6.0 + 0.2
		var dir := Vector3(cos(a), 0, sin(a))
		var w := 0.034
		var pts := [[-w, 0.0], [w, 0.0], [-w * 0.7, height * 0.5], [w * 0.7, height * 0.5], [0.0, height]]
		var verts: Array = []
		for i in pts.size():
			var t: float = pts[i][1] / height
			verts.append(dir * pts[i][0] + Vector3(0, pts[i][1], 0) + Vector3(0.05, 0, 0.03) * t * t * height)
		for tri in [[0, 1, 2], [1, 3, 2], [2, 3, 4]]:
			for idx in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(verts[idx])
	return st.commit()

# Grass over the open ground: one multimesh of tufts, thinned out on mud and under props. Adds the fine grain the flat texture lacks.
static func grass(parent: Node3D, t: Dictionary, rough: Dictionary, walls: Dictionary, rng: RandomNumberGenerator) -> void:
	var g: Dictionary = t.get("grass", {})
	if g.is_empty():
		return
	var height: float = g.get("height", 0.38)
	var mesh := _tuft(height)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://board/grass.gdshader")
	sm.set_shader_parameter("base_col", g.base)
	sm.set_shader_parameter("tip_col", g.tip)
	sm.set_shader_parameter("blade_h", height)
	mesh.surface_set_material(0, sm)
	var spots: Array = []
	var per_cell: int = g.get("density", 14)
	for x in range(-2, W + 2):
		for y in range(-2, H + 2):
			var cell := Vector2i(x, y)
			if rough.has(cell) or walls.has(cell):
				continue
			for i in per_cell:
				spots.append(Vector3((x + rng.randf()) * CELL, 0, (y + rng.randf()) * CELL))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var p: Vector3 = spots[i]
		p.y = height_at(p.x, p.z)
		var sc := rng.randf_range(0.6, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.7, 1.3), sc))
		mm.set_instance_transform(i, Transform3D(basis, p))
		var v := rng.randf_range(0.7, 1.15)
		var pick := rng.randf()  # a meadow is never one green: deep, fresh, yellowing and dry patches
		var hue := Color(0.75, 0.9, 0.7) if pick < 0.35 else (Color(0.92, 0.95, 0.65) if pick < 0.65 else (Color(1.0, 0.85, 0.55) if pick < 0.85 else Color(0.78, 0.62, 0.4)))
		mm.set_instance_color(i, Color(hue.r * v, hue.g * v, hue.b * v))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

# Small plants and moss scattered over the ground that never block a square: [model, smallest side, largest side, how many].
static func clutter(parent: Node3D, t: Dictionary, walls: Dictionary, rng: RandomNumberGenerator) -> void:
	for c in t.get("bg3clutter", []):
		for i in c[3]:
			var cell := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
			if walls.has(cell):
				continue
			var at := Vector3((cell.x + rng.randf()) * CELL, 0, (cell.y + rng.randf()) * CELL)
			at.y = height_at(at.x, at.z)
			var made := bg3_prop(parent, c[0], at, rng.randf() * TAU, rng.randf_range(c[1], c[2]))
			if made != null and str(c[0]).begins_with("NAT_Rock"):
				# small stones came out black in daylight for a reason not found yet; a plain matte material with a little self-light always reads
				for mi in made.find_children("*", "MeshInstance3D", true, false):
					var old = mi.get_surface_override_material(0)
					if old is BaseMaterial3D and old.albedo_texture != null:
						var d := StandardMaterial3D.new()
						d.albedo_texture = old.albedo_texture
						d.roughness = 0.9
						d.emission_enabled = true
						d.emission_texture = old.albedo_texture
						d.emission_energy_multiplier = 0.35
						mi.set_surface_override_material(0, d)

# The game's physical maps mark some stone and bark as metal; outdoors that turns rocks black. Only blades, candelabras and the like keep
# their metal; furniture and containers keep a little (hinges, hoops), nature and masonry none.
static func _tame_metal(n: Node3D, name: String) -> void:
	var keep := 0.0
	if name.begins_with("WPN_") or name.begins_with("LTS_"):
		keep = 1.0
	elif name.begins_with("CONT_") or name.begins_with("FUR_") or name.begins_with("DEC_GEN"):
		keep = 0.45
	if keep >= 1.0:
		return
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			if m is BaseMaterial3D:
				var d: BaseMaterial3D = m.duplicate()
				d.metallic = keep
				mi.set_surface_override_material(i, d)

# One composed group of BG3 props on a block of cells; turn rotates it 90 degrees. Items: [model, dx, dz, yaw, size].
static func _group(parent: Node3D, g: Dictionary, top_left: Vector2i, turn: bool, torches: Array) -> void:
	var w: int = g.cells[0]
	var d: int = g.cells[1]
	if turn:
		var tmp := w
		w = d
		d = tmp
	var centre := world(top_left) + Vector3((w - 1) * CELL / 2.0, 0, (d - 1) * CELL / 2.0)
	var spin := PI / 2 if turn else 0.0
	for it in g.items:
		bg3_prop(parent, it[0], centre + Vector3(it[1], 0, it[2]).rotated(Vector3.UP, spin), it[3] + spin, it[4])
	if g.has("fire"):
		var fp: Array = g.fire
		torches.append(fire_pit(parent, centre + Vector3(fp[0], 0, fp[1]).rotated(Vector3.UP, spin), Color("ffa860"), false))
	if g.get("light", 0) > 0:
		_flame(parent, centre + Vector3(0, 1.75, 0), 0.45)
		var l := OmniLight3D.new()
		l.position = centre + Vector3(0, 1.9, 0)
		l.light_color = Color("ffb868")
		l.light_energy = 2.2
		l.omni_range = 7.0
		parent.add_child(l)
		torches.append(l)

# Two walls (the near sides stay open so you can see in), props that block squares,
# ground that slows you. Random every time. Returns {walls, rough, torches}.
# spots: cells that must stay free of props (where characters will stand).
# How a painted scene (ui/scenes.gd) tints the stage it is built on: mood (outdoors), fog colour and thickness, ambient light, sun colour.
const SCENE_LOOK = {
	"harbor_city": {"mood": "day", "fog": Color("cfd8dc"), "sun": Color("fff0d0")},
	"coastal_ruins": {"mood": "day", "fog": Color("aab4bd"), "fog_density": 0.012, "sun": Color("e8ecf4")},
	"underdark": {"ambient": Color("3a64a8"), "ambient_energy": 0.8, "fog": Color("26466e"), "sun": Color("8fd0ff")},
	"elven_vale": {"mood": "dusk", "fog": Color("e8d8a8"), "sun": Color("ffd890")},
	"beach_wreck": {"mood": "day", "fog": Color("d8d2c0"), "sun": Color("fff4dc")},
	"haunted_marsh": {"mood": "night", "fog": Color("3a5a4e"), "fog_density": 0.03, "sun": Color("a8ffd0")},
	"chained_hall": {"ambient": Color("7a6a88"), "fog": Color("2a2030")},
	"sunken_temple": {"ambient": Color("5a6a9a"), "ambient_energy": 0.35, "fog": Color("26304e"), "sun": Color("a8bcff")},
	"river_valley": {"mood": "day", "fog": Color("c4d4dc")},
	"cursed_wood": {"mood": "night", "fog": Color("4a3a6a"), "fog_density": 0.022, "sun": Color("c0a8ff")},
	"infernal_forge": {"ambient": Color("b84a28"), "ambient_energy": 0.7, "fog": Color("5a1a0a"), "sun": Color("ff7a3a")},
	"dragon_lair": {"ambient": Color("a8582a"), "ambient_energy": 0.6, "fog": Color("4a2410"), "sun": Color("ff9a50")},
	"market_street": {"mood": "day", "fog": Color("d8d0c0"), "sun": Color("fff0d8")},
}
static var look := {}  # the SCENE_LOOK entry for the stage being built, read by _light

# opts: {scene: a scenes.gd id, mood: "day" | "dusk" | "night" for open ground (else random)}
static func build(parent: Node3D, template: String, rng: RandomNumberGenerator, spots := [], opts := {}) -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template, TEMPLATES.dungeon)
	var walls := {}
	var rough := {}
	var torches := []
	var claimed := {}
	make_relief(t)
	look = SCENE_LOOK.get(str(opts.get("scene", "")), {})
	var outdoor: bool = t.has("ground")
	if t.has("bg3sets") and ResourceLoader.exists("res://assets/bg3/props/%s.glb" % t.bg3sets[0].items[0][0]):
		if t.has("bg3bar"):
			var b: Dictionary = t.bg3bar
			_group(parent, b, Vector2i(b.at[0], b.at[1]), false, torches)
			for i in b.cells[0]:
				walls[Vector2i(b.at[0] + i, b.at[1])] = true
		for k in t.bg3sets_count:  # random free blocks in the middle, away from where the characters start
			var g: Dictionary = t.bg3sets[k % t.bg3sets.size()]
			var turn: bool = rng.randf() < 0.5 and g.cells[0] != g.cells[1]
			var gw: int = g.cells[1] if turn else g.cells[0]
			var gd: int = g.cells[0] if turn else g.cells[1]
			for attempt in 12:
				var tl := Vector2i(rng.randi_range(4, W - 5 - gw + 1), rng.randi_range(1, H - 1 - gd))
				var free := true
				for i in gw:
					for j in gd:
						var c := tl + Vector2i(i, j)
						# keep a one-cell margin round every set so squares stay reachable
						free = free and not walls.has(c) and not (c in spots)
				if free:
					_group(parent, g, tl, turn, torches)
					for i in gw:
						for j in gd:
							walls[tl + Vector2i(i, j)] = true
					for i in range(-1, gw + 1):  # margin: keep the scatter pass off the neighbours
						for j in range(-1, gd + 1):
							claimed[tl + Vector2i(i, j)] = true
					break
	for x in range(-1, W + 1):
		for y in range(-1, H + 1):
			var cell := Vector2i(x, y)
			if x < 0 or y < 0 or x >= W or y >= H:
				walls[cell] = true
				continue
			var open: bool = x < 4 or x > W - 5 or cell in spots or walls.has(cell) or claimed.has(cell)  # keep the starting columns clear
			var quarter := (rng.randi() % 4) * PI / 2
			if not open and rng.randf() < t.prop_rate:
				var made := false
				if t.has("bg3props"):
					var q: Array = t.bg3props[rng.randi() % t.bg3props.size()]
					var yaw := rng.randf() * TAU
					var jitter := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)) * CELL
					made = bg3_prop(parent, q[0], world(cell) + jitter, yaw, q[1] * rng.randf_range(0.9, 1.15)) != null
				if not made:
					var p: Array = t.props[rng.randi() % t.props.size()]
					piece(parent, p[0], world(cell), quarter, p[1])
				walls[cell] = true
			elif not open and rng.randf() < t.rough_rate:
				rough[cell] = true
	ground(parent, t, rough, t.get("track", false), outdoor)
	clutter(parent, t, walls, rng)
	if outdoor:
		grass(parent, t, rough, walls, rng)
		var rim := []  # a forest wall round the far sides, two or three trees deep, plus a few at the near corners
		for i in range(-3, W + 4):
			for row in 3:
				rim.append(Vector3((i + rng.randf()) * CELL, 0, (-4.5 - row * 2.4 - rng.randf()) * CELL))
		for i in range(-1, H + 2):
			for row in 3:
				rim.append(Vector3((-4.5 - row * 2.4 - rng.randf()) * CELL, 0, (i + rng.randf()) * CELL))
		for at in rim:
			var done := false
			if t.has("bg3edge"):
				var e: Array = t.bg3edge[rng.randi() % t.bg3edge.size()]
				done = bg3_prop(parent, e[0], at, rng.randf() * TAU, rng.randf_range(e[1], e[2])) != null
			if not done:
				piece(parent, t.edge[rng.randi() % t.edge.size()], at, rng.randf() * TAU, 1.3)
		var mood: String = OS.get_environment("TAVERN_MOOD") if OS.get_environment("TAVERN_MOOD") != "" else str(opts.get("mood", "")) if opts.get("mood", "") != "" else str(look.get("mood", ["day", "day", "dusk", "night"][rng.randi() % 4]))
		if mood == "night":  # campfires so the fight is lit
			for spot in [Vector2i(W / 5, H - 2), Vector2i(W * 3 / 5, 1)]:
				torches.append(fire_pit(parent, world(spot), Color("ffa860")))
				walls[spot] = true
		_light(parent, t, true, mood)
		return {"walls": walls, "rough": rough, "torches": torches, "mood": mood}
	box(parent, Vector3(W * CELL, 0.4, H * CELL), Vector3(W * CELL / 2.0, -0.25, H * CELL / 2.0), mat(Color("211d1b")))
	if t.has("bg3cliffs") and ResourceLoader.exists("res://assets/bg3/props/%s.glb" % t.bg3cliffs[0][0]):
		for i in range(-2, W + 3):  # two ranks of rock along the far side and the left side
			for row in 2:
				var at := Vector3((i + rng.randf()) * CELL, 0, (-2.6 - row * 3.4 - rng.randf() * 1.2))
				var q: Array = t.bg3cliffs[rng.randi() % t.bg3cliffs.size()]
				bg3_prop(parent, q[0], at, rng.randf() * TAU, rng.randf_range(q[1], q[2]))
		for i in range(-1, H + 3):
			for row in 2:
				var at := Vector3((-2.6 - row * 3.4 - rng.randf() * 1.2), 0, (i + rng.randf()) * CELL)
				var q: Array = t.bg3cliffs[rng.randi() % t.bg3cliffs.size()]
				bg3_prop(parent, q[0], at, rng.randf() * TAU, rng.randf_range(q[1], q[2]))
		for spot in [Vector2i(W / 4, 0), Vector2i(W * 3 / 4, 0), Vector2i(0, H / 3), Vector2i(0, H * 2 / 3)]:
			torches.append(fire_pit(parent, world(spot), t.torch))
			walls[spot] = true
		_light(parent, t, false)
		return {"walls": walls, "rough": rough, "torches": torches}
	if t.has("bg3walls") and ResourceLoader.exists("res://assets/bg3/props/%s.glb" % t.bg3walls[0]):
		var span_x := W * CELL
		var span_z := H * CELL
		var nx := roundi(span_x / 4.0)
		var nz := roundi(span_z / 4.0)
		for i in nx:  # far wall along x, then the left wall along z; pieces of about 4 m, nudged to fit
			bg3_wall(parent, t.bg3walls[rng.randi() % t.bg3walls.size()], Vector3((i + 0.5) * span_x / nx, 0, 0), 0.0, span_x / nx / 4.0)
		for i in nz:
			bg3_wall(parent, t.bg3walls[rng.randi() % t.bg3walls.size()], Vector3(0, 0, (i + 0.5) * span_z / nz), PI / 2, span_z / nz / 4.0)
		if t.has("bg3post"):
			bg3_prop(parent, t.bg3post, Vector3(-0.4, 0, -0.4), 0.0, 6.4)
			for f in [0.25, 0.5, 0.75]:
				bg3_prop(parent, t.bg3post, Vector3(span_x * f, 0, -0.5), 0.0, 6.4)
				bg3_prop(parent, t.bg3post, Vector3(-0.5, 0, span_z * f), 0.0, 6.4)
		var n := 0
		for f in [0.125, 0.375, 0.625, 0.875]:  # only every other torch casts shadows: eight shadow maps cost too much
			torches.append(torch(parent, Vector3(span_x * f, 2.3, 0), Vector3(0, 0, 1), t.torch, n % 2 == 0))
			torches.append(torch(parent, Vector3(0, 2.3, span_z * f), Vector3(1, 0, 0), t.torch, n % 2 == 1))
			n += 1
		_light(parent, t, false)
		return {"walls": walls, "rough": rough, "torches": torches}
	for i in W / 2:
		piece(parent, t.walls[rng.randi() % t.walls.size()], Vector3((2 * i + 1) * CELL, 0, -0.25 * CELL))
	for i in H / 2:
		piece(parent, t.walls[rng.randi() % t.walls.size()], Vector3(-0.25 * CELL, 0, (2 * i + 1) * CELL), PI / 2)
	piece(parent, "pillar", Vector3(-0.25 * CELL, 0, -0.25 * CELL))
	if t.deco != "":
		piece(parent, t.deco, Vector3(W * CELL / 2.0, 0, -0.25 * CELL))
		piece(parent, t.deco, Vector3(-0.25 * CELL, 0, H * CELL / 2.0), PI / 2)
	for spot in [[Vector3(W * CELL * 0.25, 1.4, 0), 0.0], [Vector3(W * CELL * 0.75, 1.4, 0), 0.0],
			[Vector3(0, 1.4, H * CELL * 0.25), PI / 2], [Vector3(0, 1.4, H * CELL * 0.75), PI / 2]]:
		piece(parent, "torch_mounted", spot[0], spot[1])
		var l := OmniLight3D.new()
		l.position = spot[0] + Vector3(0.5, 0.6, 0.0).rotated(Vector3.UP, spot[1] - PI / 2)
		l.light_color = t.torch
		l.light_energy = 4.0
		l.omni_range = 14.0
		l.shadow_enabled = true
		parent.add_child(l)
		torches.append(l)
	_light(parent, t, false)
	return {"walls": walls, "rough": rough, "torches": torches}

static func _light(parent: Node3D, t: Dictionary, outdoor: bool, mood := "day") -> void:
	parent.get_viewport().msaa_3d = Viewport.MSAA_DISABLED  # FSR 2 brings its own temporal anti-aliasing
	var env := Environment.new()
	if outdoor:  # a real sky: it lights the scene softly from every side and shows at the horizon
		var sky_mat := ProceduralSkyMaterial.new()
		var sky_tint: Array = {"day": [Color("4f7fc2"), Color("c9d6dc")], "dusk": [Color("3d5390"), Color("d9b0a0")],
			"night": [Color("070b1c"), Color("1a2540")]}[mood]
		sky_mat.sky_top_color = sky_tint[0]
		sky_mat.sky_horizon_color = sky_tint[1]
		sky_mat.ground_horizon_color = Color("a7b09a") if mood == "day" else Color("40382f")
		sky_mat.ground_bottom_color = Color("3b4a35") if mood == "day" else Color("14160f")
		sky_mat.sun_angle_max = 25.0
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = {"day": 0.8, "dusk": 0.75, "night": 0.4}[mood]
		env.fog_enabled = true  # distant haze that melts the tree line into the sky
		env.fog_light_color = {"day": Color("c4d2d8"), "dusk": Color("a89a92"), "night": Color("1b2744")}[mood]
		env.fog_density = 0.006
		env.fog_sky_affect = 0.4
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("08080b")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = t.ambient
		env.ambient_light_energy = t.get("ambient_energy", 0.2)
		# a dim sky that nobody sees, only metal does: armour and blades need something to reflect or they come out black
		var refl := ProceduralSkyMaterial.new()
		refl.sky_top_color = Color("40475a")
		refl.sky_horizon_color = (t.ambient as Color).lerp(t.torch, 0.5) if t.has("torch") else t.ambient
		refl.ground_horizon_color = refl.sky_horizon_color.darkened(0.4)
		refl.ground_bottom_color = Color("15110f")
		var refl_sky := Sky.new()
		refl_sky.sky_material = refl
		env.sky = refl_sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	if look.has("fog") and outdoor:
		env.fog_light_color = look.fog
	if look.has("fog_density") and outdoor:
		env.fog_density = look.fog_density
	if look.has("ambient") and not outdoor:
		env.ambient_light_color = look.ambient
		env.ambient_light_energy = look.get("ambient_energy", env.ambient_light_energy)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.adjustment_enabled = true  # the graded, slightly contrasty look of the game
	env.adjustment_contrast = 1.18
	env.adjustment_saturation = 1.1 if not outdoor else 0.92  # open country in the game is earthy, not candy green
	# split toning like the game's grade: cool, slightly lifted shadows and warm highlights (each channel has its own curve)
	var grade := Gradient.new()
	grade.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	grade.colors = PackedColorArray([Color(0.0, 0.012, 0.03), Color(0.30, 0.31, 0.33), Color(0.69, 0.68, 0.66), Color(1.0, 0.965, 0.915)])
	var grade_tex := GradientTexture1D.new()
	grade_tex.gradient = grade
	grade_tex.width = 256
	env.adjustment_color_correction = grade_tex
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	if not outdoor:  # polished and wet floors pick up the torches: the lit-room look of the game
		env.ssr_enabled = true
		env.ssr_max_steps = 24
		env.ssr_fade_in = 0.12
		env.ssr_fade_out = 1.5
		env.ssr_depth_tolerance = 0.3
	env.ssil_enabled = false  # costly and barely visible next to SSAO and the torch light
	env.volumetric_fog_enabled = not outdoor  # open ground has plain haze (the fog above); the volume costs frames on big screens
	env.volumetric_fog_density = t.fog * (0.5 if outdoor else 1.8)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_anisotropy = 0.55  # light shafts are brightest looking toward the light
	env.volumetric_fog_albedo = look.get("fog", Color("b9a58f")) if not outdoor else Color("b9a58f")
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var motes := GPUParticles3D.new()  # slow dust in the torch light, or pollen in the sun
	motes.amount = 90
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(60, 14, 60))
	motes.position = Vector3(W * CELL / 2.0, 1.2, H * CELL / 2.0)
	var mpm := ParticleProcessMaterial.new()
	mpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mpm.emission_box_extents = Vector3(W * CELL / 2.0, 1.6, H * CELL / 2.0)
	mpm.direction = Vector3(0.3, 0.2, 0.1)
	mpm.spread = 90.0
	mpm.initial_velocity_min = 0.03
	mpm.initial_velocity_max = 0.14
	mpm.gravity = Vector3(0, 0.01, 0)
	mpm.scale_min = 0.4
	mpm.scale_max = 1.0
	motes.process_material = mpm
	var mq := QuadMesh.new()
	mq.size = Vector2(0.045, 0.045)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.albedo_texture = soft_dot()
	mm.albedo_color = Color(1.0, 0.86, 0.62, 0.5) if not outdoor or mood != "night" else Color(0.7, 0.8, 1.0, 0.35)
	mq.material = mm
	motes.draw_pass_1 = mq
	parent.add_child(motes)
	var sun := DirectionalLight3D.new()  # comes in over the open sides, shadows fall toward the walls
	sun.rotation_degrees = Vector3(-48, 38, 0) if outdoor else Vector3(-52, 32, 0)
	sun.light_energy = 2.3 if outdoor else t.get("sun", 0.55)
	sun.light_color = Color("ffe2b0") if outdoor else Color("c3ceff")
	if outdoor and mood == "dusk":
		sun.rotation_degrees = Vector3(-16, 38, 0)  # low and golden, long shadows
		sun.light_energy = 1.35
		sun.light_color = Color("ffd8b4")
	elif outdoor and mood == "night":
		sun.rotation_degrees = Vector3(-55, 38, 0)  # moonlight
		sun.light_energy = 0.55
		sun.light_color = Color("9bb4ff")
	if look.has("sun"):
		sun.light_color = look.sun
	sun.light_volumetric_fog_energy = 2.5 if not outdoor else 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03  # the default swallows small stones whole
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	parent.add_child(sun)

static func flicker(torches: Array) -> void:
	for t in torches:
		var base: float = t.get_meta("base", 4.0)
		t.light_energy = base * (1.0 + sin(Time.get_ticks_msec() * 0.011 + t.position.x) * 0.06 + randf() * 0.05)

# The animated model for a creature, on a team-coloured disc. n picks the monster variant.
static func character(parent: Node3D, c, n: int) -> Dictionary:
	var node := Node3D.new()
	node.position = world(c.pos)
	node.rotation.y = PI / 2 if c.side == "party" else -PI / 2
	parent.add_child(node)
	var disc := MeshInstance3D.new()
	var ring := TorusMesh.new()  # a thin glowing ring on the ground, as in the game, not a filled disc
	ring.inner_radius = 0.52
	ring.outer_radius = 0.6
	ring.rings = 40
	ring.ring_segments = 6
	disc.mesh = ring
	disc.scale.y = 0.15
	disc.material_override = mat(Color("5aa0ff") if c.side == "party" else Color("ff5a3c"), 2.2, 0.9)
	disc.position.y = 0.05
	disc.name = "disc"
	node.add_child(disc)
	var bg3 := model_path(c)
	var ap: AnimationPlayer
	var built: Node3D = Assemble.character(Assemble.spec_of(c)) if c.is_pc and Assemble.available() else null  # a player's own race, hair and outfit
	if built != null or (bg3 != "" and ResourceLoader.exists(bg3)):
		var model: Node3D = built if built != null else load(bg3).instantiate()
		model.scale = Vector3.ONE * (1.0 if built != null else model_scale(c))  # life size: a cell is 5 ft = 1.5 m
		node.add_child(model)
		polish_character(model)
		ap = model.find_child("AnimationPlayer", true, false)
		var lib := ap.get_animation_library("")
		for k in BG3_ANIM:  # the battle code plays the KayKit names
			if lib.has_animation(BG3_ANIM[k]):
				lib.add_animation(k, lib.get_animation(BG3_ANIM[k]))
		for a in ["Idle", "Calm", "Talk", "Running_A", "Walking_A"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		equip(model, c)
	else:
		var look: Array = LOOK[c.cls] if c.is_pc else [MONSTERS[n % MONSTERS.size()], []]
		var model: Node3D = load("res://assets/kaykit/chars/%s.glb" % look[0]).instantiate()
		model.scale = Vector3.ONE * 0.8 * c.size
		node.add_child(model)
		if not c.is_pc and KIND_TINT.has(c.kind):
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				for i in mi.mesh.get_surface_count():
					var m: BaseMaterial3D = mi.mesh.surface_get_material(i).duplicate()
					m.albedo_color = KIND_TINT[c.kind]
					mi.set_surface_override_material(i, m)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if mi.name in GEAR:
				mi.visible = mi.name in look[1]
		if not c.is_pc:  # skeletons come empty-handed; put a blade in the right hand
			var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
			var hand := BoneAttachment3D.new()
			hand.bone_name = "handslot.r"
			sk.add_child(hand)
			hand.add_child(load("res://assets/kaykit/gear/Skeleton_Blade.gltf").instantiate())
		ap = model.find_child("AnimationPlayer", true, false)
		for a in ["Idle", "Running_A"]:
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	ap.play("Idle")
	ap.seek(randf())
	var info := Label3D.new()
	info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info.no_depth_test = true
	info.font_size = 36
	info.outline_size = 12
	info.position.y = 2.3 * maxf(c.size, 1.0)
	node.add_child(info)
	return {"node": node, "c": c, "info": info, "ap": ap, "scale": model_scale(c) if bg3 != "" else 1.0}
