extends RefCounted
# One combatant: a player character or a monster.

const XP_FOR_LEVEL = [0, 0, 300, 900, 2700, 6500]  # index = level
const MAX_LEVEL = 5  # shortcut: stops at level 5, raise when higher-level features are coded
# The ability a class raises by 2 at level 4 (shortcut: no choice of feat or split).
const PRIMARY = {"barbarian": "str", "bard": "cha", "cleric": "wis", "druid": "wis", "fighter": "str", "monk": "dex",
	"paladin": "str", "ranger": "dex", "rogue": "dex", "sorcerer": "cha", "warlock": "cha", "wizard": "int"}
const SIZE = {"Tiny": 0.6, "Small": 0.8, "Medium": 1.0, "Large": 1.45, "Huge": 1.9, "Gargantuan": 2.3}

var name := ""
var side := "party"
var is_pc := false
var kind := "humanoid"
var cls := ""
var level := 1
var xp := 0
var xp_value := 0  # monsters: xp granted when defeated
var abil := {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
var prof := 2
var max_hp := 1
var hp := 1
var ac := 10
var speed := 30
var save_profs := []
var skills := {}       # skill -> 1 proficient, 2 expertise
var flat_saves := {}   # monsters: ability -> total bonus
var flat_skills := {}  # monsters: skill -> total bonus
var attacks := []      # {name, bonus, damage:[{dice,type}], ranged, reach, range, long, finesse}
var resist := []
var vuln := []
var immune := []
var cond_immune := []
var features := []
var res := {}          # uses left: second_wind, action_surge, channel_divinity, arcane_recovery, rage, ki, lay_on_hands
var res_max := {}
var short_res := ["second_wind", "action_surge", "channel_divinity", "ki"]
var multi := 1         # attacks per Attack action (Extra Attack, monster Multiattack)
var multi_seq := []    # monsters: which attack each swing of a Multiattack uses
var rage_bonus := 0
var size := 1.0        # model scale
var hit_die := 8
var hit_dice := 0
var slots := {}        # spell level -> slots left
var slots_max := {}
var spells := []
var cast_abil := ""
var sneak_dice := 0
var crit_min := 20
var items := {}        # item -> count
var spec := {}         # what the character was made from, reused on level up

var conditions := []   # {id, rounds, save, dc, wake, by}
var death_s := 0
var death_f := 0
var dead := false
var stable := false
var conc := ""         # spell being concentrated on
var pos := Vector2i.ZERO
# this turn
var actions := 0
var bonus := false
var reaction := true
var move_left := 0
var dodging := false
var disengaged := false
var sneak_used := false
var attacks_left := 0  # swings still owed by the Attack action already paid for
var reckless := false
var smite := false     # paladin: spend a slot on the next hit
var cast_bonus_spell := false
var cast_leveled_action := false

func mod(a: String) -> int:
	return floori((abil[a] - 10) / 2.0)

func save_bonus(a: String) -> int:
	if flat_saves.has(a):
		return flat_saves[a]
	return mod(a) + (prof if a in save_profs else 0)

func skill_bonus(srd, skill: String) -> int:
	if flat_skills.has(skill):
		return flat_skills[skill]
	return mod(srd.t.skills[skill].ability_score.index) + prof * skills.get(skill, 0)

func has(cond: String) -> bool:
	return conditions.any(func(c): return c.id == cond)

func spell_dc() -> int:
	return 8 + prof + mod(cast_abil)

func spell_attack() -> int:
	return prof + mod(cast_abil)

# spec: {name, race, subrace?, class, level?, abilities{str..cha}, skills[], expertise[],
#        armor?, shield?, weapons[], spells[], style?, items{}}
static func make_pc(srd, s: Dictionary):
	var c = new()
	c.spec = s
	c.name = s.name
	c.is_pc = true
	c.cls = s["class"]
	c.level = s.get("level", 1)
	if c.level >= 4 and not s.get("asi", false):  # built straight at level 4+
		_improve(s)
	c.abil = s.abilities.duplicate()
	for src in [srd.t.races[s.race], srd.t.subraces.get(s.get("subrace", ""), {})]:
		for b in src.get("ability_bonuses", []):
			c.abil[b.ability_score.index] += int(b.bonus)
	c.speed = int(srd.t.races[s.race].speed)
	for k in s.get("skills", []):
		c.skills[k] = 1
	for k in s.get("expertise", []):
		c.skills[k] = 2
	c.items = s.get("items", {}).duplicate()
	c.derive(srd)
	c.refill()
	return c

static func _improve(s: Dictionary) -> void:
	var a: String = PRIMARY[s["class"]]
	s.abilities[a] = min(20, s.abilities[a] + 2)
	s["asi"] = true

# Everything that follows from class, level, abilities and gear.
func derive(srd) -> void:
	var c = srd.t.classes[cls]
	var profs: Array = c.proficiencies.map(func(p): return p.index)
	hit_die = int(c.hit_die)
	save_profs = c.saving_throws.map(func(x): return x.index)
	cast_abil = c.spellcasting.spellcasting_ability.index if c.has("spellcasting") else ""
	features = []
	for lv in srd.t.levels.values():
		if lv["class"].index == cls and int(lv.level) <= level:
			for f in lv.features:
				features.append(f.index)
	var lv = srd.t.levels["%s-%d" % [cls, level]]
	var cs: Dictionary = lv.get("class_specific", {})
	prof = int(lv.prof_bonus)
	slots_max = {}
	for i in range(1, 10):
		var n := int(lv.get("spellcasting", {}).get("spell_slots_level_%d" % i, 0))
		if n > 0:
			slots_max[i] = n
	res_max = {}
	if "second-wind" in features:
		res_max["second_wind"] = 1
	if "arcane-recovery" in features:
		res_max["arcane_recovery"] = 1
	for k in [["action_surges", "action_surge"], ["channel_divinity_charges", "channel_divinity"]]:
		if int(cs.get(k[0], 0)) > 0:
			res_max[k[1]] = int(cs[k[0]])
	if int(cs.get("rage_count", 0)) > 0:
		res_max["rage"] = int(cs.rage_count)
	if int(cs.get("ki_points", 0)) > 0:
		res_max["ki"] = int(cs.ki_points)
	if "lay-on-hands" in features:
		res_max["lay_on_hands"] = 5 * level
	rage_bonus = int(cs.get("rage_damage_bonus", 0))
	multi = 2 if features.any(func(f): return f.contains("extra-attack")) else 1
	sneak_dice = int(cs.get("sneak_attack", {}).get("dice_count", 0))
	crit_min = 19 if "improved-critical" in features else 20
	max_hp = hit_die + mod("con") + (level - 1) * (hit_die / 2 + 1 + mod("con")) \
		+ (level if "draconic-resilience" in features else 0)
	speed = int(srd.t.races[spec.race].speed) + int(cs.get("unarmored_movement", 0)) + (10 if "fast-movement" in features else 0)

	var style: String = spec.get("style", "") if features.any(func(f): return f.ends_with("fighting-style")) else ""
	var shield: bool = spec.get("shield", false)
	ac = 10 + mod("dex")
	if "barbarian-unarmored-defense" in features:
		ac += mod("con")
	elif "monk-unarmored-defense" in features:
		ac += mod("wis")
	elif "draconic-resilience" in features:
		ac += 3
	if spec.get("armor", "") != "":
		var a = srd.t.equipment[spec.armor].armor_class
		ac = int(a.base)
		if a.dex_bonus:
			ac += min(mod("dex"), int(a.get("max_bonus", 99)))
		if style == "defense":
			ac += 1
	if shield:
		ac += 2

	attacks = []
	for wi in spec.get("weapons", []):
		var w = srd.t.equipment[wi]
		var props: Array = w.properties.map(func(p): return p.index)
		var ranged: bool = w.weapon_range == "Ranged"
		var a := "dex" if ranged else "str"
		if ("finesse" in props or cls == "monk") and mod("dex") > mod("str"):
			a = "dex"
		var proficient: bool = (w.weapon_category.to_lower() + "-weapons") in profs or (wi + "s") in profs
		var two_handed: bool = "two-handed" in props or (w.has("two_handed_damage") and not shield and style != "dueling")
		var dmg = w.two_handed_damage if w.has("two_handed_damage") and two_handed else w.damage
		var flat := mod(a) + (2 if style == "dueling" and not ranged and not two_handed else 0)
		attacks.append({
			"name": w.name, "ranged": ranged, "finesse": "finesse" in props, "abil": a,
			"bonus": mod(a) + (prof if proficient else 0) + (2 if style == "archery" and ranged else 0),
			"damage": [{"dice": "%s%+d" % [dmg.damage_dice, flat], "type": dmg.damage_type.index}],
			"reach": 10 if "reach" in props else 5,
			"range": int(w.range.normal), "long": int(w.range.get("long", w.range.normal)),
		})
	if "martial-arts" in features:
		var ma: Dictionary = cs.martial_arts
		var a := "dex" if mod("dex") > mod("str") else "str"
		attacks.append({"name": "Unarmed Strike", "ranged": false, "finesse": false, "abil": a, "unarmed": true,
			"bonus": mod(a) + prof, "damage": [{"dice": "%dd%d%+d" % [ma.dice_count, ma.dice_value, mod(a)], "type": "bludgeoning"}],
			"reach": 5, "range": 5, "long": 5})
	spells = spec.get("spells", [])
	for sp in spells:  # warlocks also get the Fiend patron's expanded list
		assert(srd.t.spells[sp].classes.any(func(x): return x.index == cls) \
			or (cls == "warlock" and sp in ["burning-hands", "scorching-ray", "fireball"]), "%s cannot learn %s" % [cls, sp])

func refill() -> void:
	hp = max_hp
	hit_dice = level
	slots = slots_max.duplicate()
	res = res_max.duplicate()

static func make_monster(srd, index: String, label := ""):
	var m = srd.t.monsters[index]
	var c = new()
	c.name = label if label != "" else m.name
	c.side = "enemy"
	c.kind = m.type
	c.abil = {"str": int(m.strength), "dex": int(m.dexterity), "con": int(m.constitution),
		"int": int(m.intelligence), "wis": int(m.wisdom), "cha": int(m.charisma)}
	c.prof = int(m.get("proficiency_bonus", 2))
	c.max_hp = int(m.hit_points)
	c.hp = c.max_hp
	c.ac = int(m.armor_class[0].value)
	c.speed = int(m.speed.get("walk", "0"))
	c.xp_value = int(m.xp)
	c.size = SIZE.get(m.size, 1.0)
	c.resist = m.damage_resistances
	c.vuln = m.damage_vulnerabilities
	c.immune = m.damage_immunities
	c.cond_immune = m.condition_immunities.map(func(x): return x.index)
	for p in m.proficiencies:
		var id: String = p.proficiency.index
		if id.begins_with("saving-throw-"):
			c.flat_saves[id.trim_prefix("saving-throw-")] = int(p.value)
		elif id.begins_with("skill-"):
			c.flat_skills[id.trim_prefix("skill-")] = int(p.value)
	var reach_re := RegEx.create_from_string("reach (\\d+) ft")
	var range_re := RegEx.create_from_string("range (\\d+)(?:/(\\d+))? ft")
	for a in m.get("actions", []):
		if not a.has("attack_bonus"):
			continue
		var dmg := []
		for d in a.get("damage", []):
			if d.has("damage_dice"):  # skips "choose one" damage options
				dmg.append({"dice": d.damage_dice, "type": d.damage_type.index})
		var rm := range_re.search(a.desc)
		var rr := reach_re.search(a.desc)
		c.attacks.append({
			"name": a.name, "bonus": int(a.attack_bonus), "damage": dmg, "finesse": false, "abil": "str",
			"ranged": rr == null and rm != null,
			"reach": int(rr.get_string(1)) if rr else 5,
			"range": int(rm.get_string(1)) if rm else 5,
			"long": int(rm.get_string(2)) if rm and rm.get_string(2) != "" else (int(rm.get_string(1)) if rm else 5),
		})
	# Multiattack: the swings it lists, by attack number. shortcut: at most 3, non-attack parts are skipped.
	for a in m.get("actions", []):
		for part in a.get("actions", []) if a.name == "Multiattack" else []:
			for i in c.attacks.size():
				if c.attacks[i].name == part.action_name:
					for k in int(part.count):
						c.multi_seq.append(i)
	c.multi_seq = c.multi_seq.slice(0, 3)
	c.multi = max(1, c.multi_seq.size())
	return c

# Spend hit dice, get short-rest features back. Wizards also use Arcane Recovery here.
func short_rest(dice, spend := 0) -> Dictionary:
	var healed := 0
	for i in min(spend, hit_dice):
		if hp >= max_hp:
			break
		hit_dice -= 1
		healed += max(dice.die(hit_die) + mod("con"), 0)
	hp = min(max_hp, hp + healed)
	for k in short_res:
		if res_max.has(k):
			res[k] = res_max[k]
	if cls == "warlock":  # Pact Magic comes back on a short rest
		slots = slots_max.duplicate()
	var recovered := 0
	if res.get("arcane_recovery", 0) > 0:
		var budget := ceili(level / 2.0)
		for lv in range(5, 0, -1):  # highest slots first, none above 5th
			while lv <= budget and slots.get(lv, 0) < slots_max.get(lv, 0):
				slots[lv] += 1
				budget -= lv
				recovered += lv
		if recovered > 0:
			res["arcane_recovery"] = 0
	return {"healed": healed, "slot_levels_recovered": recovered}

func long_rest() -> void:
	if dead:
		return
	var dice_back: int = max(1, level / 2)
	var had := hit_dice
	refill()
	hit_dice = min(level, had + dice_back)
	conditions = []
	conc = ""
	death_s = 0
	death_f = 0
	stable = false

# Returns how many levels were gained.
func gain_xp(srd, amount: int) -> int:
	xp += amount
	var gained := 0
	while level < MAX_LEVEL and xp >= XP_FOR_LEVEL[level + 1]:
		var old := [max_hp, slots_max.duplicate(), res_max.duplicate()]
		level += 1
		gained += 1
		if level == 4 and not spec.get("asi", false):
			var was: int = spec.abilities[PRIMARY[cls]]
			_improve(spec)
			abil[PRIMARY[cls]] += spec.abilities[PRIMARY[cls]] - was
		derive(srd)
		hp += max_hp - old[0]
		hit_dice += 1
		for k in slots_max:
			slots[k] = slots.get(k, 0) + slots_max[k] - old[1].get(k, 0)
		for k in slots.keys():  # warlock slots move up a level instead of adding one
			if not slots_max.has(k):
				slots.erase(k)
		for k in res_max:
			res[k] = res.get(k, 0) + res_max[k] - old[2].get(k, 0)
	return gained

# What a save file needs to rebuild this character.
func to_dict() -> Dictionary:
	spec["level"] = level
	return {"spec": spec, "xp": xp, "hp": hp, "hit_dice": hit_dice, "slots": slots, "res": res, "items": items, "dead": dead}

static func from_dict(srd, d: Dictionary):
	var c = make_pc(srd, d.spec)
	c.xp = d.xp
	c.hp = d.hp
	c.hit_dice = d.hit_dice
	c.slots = {}
	for k in d.slots:  # JSON turns the keys into text
		c.slots[int(k)] = d.slots[k]
	c.res = d.res
	c.items = d.items
	c.dead = d.dead
	return c
