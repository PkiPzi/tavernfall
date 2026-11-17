extends RefCounted
# BG3's own generic portraits (assets/bg3/portraits, from the game's portrait atlas): a goblin face for a goblin,
# a robed human for a sorcerer. File names carry the kind, e.g. "<uuid>-eqp_staff_robe_(icon_human_male).png".
# Portraits.pick(creature) -> a resource path, or "" when none fits (the caller then renders the 3D model instead).

const DIR := "res://assets/bg3/portraits/"

static var _files: Array = []  # {path, icon, name}

static func _load() -> void:
	if not _files.is_empty():
		return
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".png"):
			continue
		var open := f.rfind("(icon_")
		if open < 0:
			continue
		var name := f.substr(37, open - 37)  # after the 36-character id and the dash
		if "daisy" in name:  # the same face on every body
			continue
		_files.append({"path": DIR + f, "icon": f.substr(open + 6, f.length() - open - 11), "name": name})

# What a creature may look like: BG3 icon kinds, in order of preference. Words are looked for in the SRD index.
const MONSTER_ICONS = {"hobgoblin": ["goblin_male"], "goblin": ["goblin_male", "goblin_female"], "skeleton": ["skeleton"], "zombie": ["zombie"], "ghoul": ["zombie"],
	"wolf": ["wolf", "worg_male"], "worg": ["worg_male", "wolf"], "dog": ["dog", "wolf"], "jackal": ["hyena", "wolf"], "hyena": ["hyena"], "ogre": ["ogre"], "gnoll": ["gnoll"],
	"spider": ["spider_normal", "spider_critter"], "owlbear": ["owlbear"], "rat": ["rat"], "bugbear": ["bugbear_male"], "harpy": ["harpy"], "minotaur": ["minotaur"],
	"bear": ["bear"], "boar": ["boar"], "imp": ["imp"], "quasit": ["quasit"], "mimic": ["mimic"], "ooze": ["ooze"], "beholder": ["beholder"], "hag": ["hag"],
	"redcap": ["redcap"], "myconid": ["myconid_slender"], "mind-flayer": ["mindflayer"], "mindflayer": ["mindflayer"], "werewolf": ["werewolf"], "golem": ["adamantine_golem"],
	"animated": ["animated_armor"], "armor": ["animated_armor"], "kuo": ["kuotoa"], "snake": ["snake"], "crab": ["crab"], "bat": ["bird_bluejay"], "eagle": ["bird_bluejay"],
	"hook-horror": ["hookhorror"], "dragon": ["dragon"], "ettercap": ["ettercap"], "bulette": ["bulette"], "mephit": ["mephit_mud"], "wraith": ["skeleton"], "specter": ["skeleton"],
	"ghost": ["skeleton"], "shadow": ["skeleton"], "mummy": ["zombie"]}
const HUMAN_WORDS = ["bandit", "thug", "cultist", "guard", "scout", "veteran", "knight", "noble", "commoner", "spy", "assassin", "priest", "mage", "acolyte",
	"gladiator", "druid", "berserker", "warrior", "tribal", "pirate", "captain"]

# Race word (as the creator spells it) -> icon stem; the gender is appended.
const RACE_ICON = {"human": "human", "elf": "elf", "half-elf": "halfelf", "dwarf": "dwarf", "halfling": "halfling", "gnome": "gnomes", "tiefling": "tiefling",
	"half-orc": "human", "dragonborn": "human"}

# Equipment words in the file names that suit each class, best first.
const CLASS_TAGS = {"wizard": ["staff_robe", "robe", "staff"], "sorcerer": ["staff_robe", "robe", "staff"], "warlock": ["dagger_robe", "robe", "dagger"],
	"rogue": ["shortbow_dagger_leather", "dagger_leather", "shortsword_leather", "dagger"], "ranger": ["longbow_leather", "longbow_dagger_leather", "shortbow_leather", "longbow"],
	"fighter": ["longsword_scalemail", "greatsword_scalemail", "hammer_chainmail_shield", "longsword", "greatsword"],
	"paladin": ["longsword_scalemail", "greatsword_scalemail", "hammer_chainmail_shield", "longsword"],
	"cleric": ["warhammer_leather", "club_leather_shield", "hammer_chainmail_shield", "warpick_leather"],
	"barbarian": ["greataxe_scalemail", "greatclub_leather", "greatsword", "axe"], "bard": ["shortsword_leather", "dagger_leather", "shortsword"],
	"druid": ["staff_leather", "club_leather_shield", "staff"], "monk": ["unarmed"]}

static func _stable(c) -> int:
	return absi(hash("%s%s" % [c.name, c.spec.get("variant", 0) if c.is_pc else 0]))

static func pick(c) -> String:
	_load()
	if _files.is_empty():
		return ""
	var icons: Array = []
	var tags: Array = []
	if c.is_pc:
		var gender := "female" if str(c.spec.get("gender", "")) in ["woman", "female", "f"] else "male"
		icons = ["%s_%s" % [RACE_ICON.get(str(c.spec.get("race", "human")), "human"), gender], "human_%s" % gender]
		tags = CLASS_TAGS.get(c.cls, [])
	else:
		var idx := str(c.index)
		for w in MONSTER_ICONS:
			if w in idx:
				icons = MONSTER_ICONS[w]
				break
		if icons.is_empty() and HUMAN_WORDS.any(func(w): return w in idx):
			icons = ["human_male", "human_female"]
	for icon in icons:
		var pool: Array = _files.filter(func(f): return f.icon == icon)
		if pool.is_empty():
			continue
		var best := 0
		var scored := []
		for f in pool:
			var s := 0
			for i in tags.size():
				if tags[i] in f.name:
					s = maxi(s, tags.size() - i)
			scored.append(s)
			best = maxi(best, s)
		var top: Array = []
		for i in pool.size():
			if scored[i] == best:
				top.append(pool[i])
		# a plain "(icon_x)" with nothing worn is a face for hire; the dressed ones come first when the class asks
		return top[_stable(c) % top.size()].path
	return ""
