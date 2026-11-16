extends SceneTree
# Run: godot --headless --path . -s tests/run_tests.gd

const Dice = preload("res://rules/dice.gd")
const Srd = preload("res://rules/srd.gd")
const Creature = preload("res://rules/creature.gd")
const Combat = preload("res://rules/combat.gd")
const AI = preload("res://rules/ai.gd")
const GameScript = preload("res://game.gd")

var srd
var fails := 0
var checks := 0

func eq(got, want, what: String) -> void:
	checks += 1
	if got != want:
		fails += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])

func pc(cls: String, level := 1, extra := {}):
	var base: Dictionary = {
		"fighter": {"abilities": {"str": 15, "dex": 12, "con": 13, "int": 8, "wis": 10, "cha": 10},
			"armor": "chain-mail", "shield": true, "weapons": ["longsword", "crossbow-light"], "style": "defense",
			"skills": ["athletics"]},
		"rogue": {"abilities": {"str": 8, "dex": 15, "con": 13, "int": 12, "wis": 10, "cha": 10},
			"armor": "leather-armor", "weapons": ["rapier", "shortbow"], "skills": ["stealth"], "expertise": ["stealth"]},
		"cleric": {"abilities": {"str": 13, "dex": 10, "con": 13, "int": 8, "wis": 15, "cha": 10},
			"armor": "scale-mail", "shield": true, "weapons": ["mace"],
			"spells": ["sacred-flame", "cure-wounds", "healing-word", "guiding-bolt", "hold-person"]},
		"wizard": {"abilities": {"str": 8, "dex": 13, "con": 13, "int": 15, "wis": 10, "cha": 10},
			"weapons": ["dagger"], "spells": ["fire-bolt", "magic-missile", "burning-hands", "sleep"]},
	}[cls]
	base.merge({"name": cls, "race": "human", "class": cls, "level": level})
	base.merge(extra, true)
	return Creature.make_pc(srd, base)

# A hero from the game's own presets, with the spells it would have learned by that level.
func hero(cls: String, level := 1):
	var spec: Dictionary = GameScript.PRESETS[cls].duplicate(true)
	spec.merge({"name": cls, "race": "human", "class": cls, "level": level})
	for lv in GameScript.LEVEL_SPELLS.get(cls, {}):
		if lv <= level:
			spec.spells += GameScript.LEVEL_SPELLS[cls][lv]
	return Creature.make_pc(srd, spec)

# A fight where `who` acts first; d is the dice so tests can queue rolls.
func duel(who, other, cell := Vector2i(1, 0)):
	var d = Dice.new(1)
	var cb = Combat.new(d, srd)
	who.pos = Vector2i(0, 0)
	other.pos = cell
	for c in [who, other]:
		c.conditions = []
		c.reaction = true
	d.queue = [20, 1]
	cb.start([who, other])
	if other.is_pc:  # a second party member, so one hero going down does not end the fight
		var friend = pc("rogue")
		friend.pos = Vector2i(9, 9)
		cb.all.append(friend)
		cb.order.append(friend)
	return cb

# `who` acts first with `friend` beside them and an ogre far away, for spells and features cast on allies.
func allies(who, friend):
	var cb = duel(who, Creature.make_monster(srd, "ogre"), Vector2i(9, 0))
	friend.pos = Vector2i(1, 0)
	cb.all.append(friend)
	cb.order.append(friend)
	return cb

func _init() -> void:
	srd = Srd.new()
	t_dice()
	t_build()
	t_attacks()
	t_death()
	t_spells()
	t_movement()
	t_rest_and_level()
	t_classes()
	t_data()
	t_fights()
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)

func t_dice() -> void:
	var d = Dice.new(1)
	d.queue = [3, 4]
	eq(d.roll("2d6+3"), 10, "2d6+3")
	d.queue = [1, 2, 3, 4]
	eq(d.roll("2d6 + 3", true), 13, "crit doubles dice only")
	d.queue = [5, 17]
	eq(d.d20(1).roll, 17, "advantage")
	d.queue = [5, 17]
	eq(d.d20(-1).roll, 5, "disadvantage")
	eq(d.roll("7"), 7, "flat")

func t_build() -> void:
	var f = pc("fighter")  # human: 16 str, 13 dex, 14 con
	eq(f.ac, 19, "fighter ac chain+shield+defense")
	eq(f.max_hp, 12, "fighter hp")
	eq(f.attacks[0].bonus, 5, "longsword to hit")
	eq(f.attacks[0].damage[0].dice, "1d8+3", "longsword damage")
	eq(f.attacks[1].ranged, true, "crossbow ranged")
	eq(f.save_bonus("str"), 5, "str save proficient")
	eq(f.save_bonus("wis"), 0, "wis save")
	eq(f.skill_bonus(srd, "athletics"), 5, "athletics")
	eq(f.res, {"second_wind": 1}, "fighter 1 resources")
	var f3 = pc("fighter", 3, {"shield": false, "style": "dueling"})
	eq(f3.max_hp, 12 + 2 * 8, "fighter 3 hp")
	eq(f3.res.action_surge, 1, "action surge")
	eq(f3.crit_min, 19, "champion crit")
	eq(f3.attacks[0].damage[0].dice, "1d8+5", "dueling")
	eq(pc("fighter", 1, {"shield": false}).attacks[0].damage[0].dice, "1d10+3", "versatile two-handed")
	var r = pc("rogue", 3)
	eq(r.sneak_dice, 2, "sneak dice")
	eq(r.skill_bonus(srd, "stealth"), 3 + 4, "expertise")
	eq(r.ac, 11 + 3, "leather")
	eq(r.attacks[0].bonus, 5, "rapier finesse")
	var w = pc("wizard", 3)
	eq(w.slots, {1: 4, 2: 2}, "wizard 3 slots")
	eq(w.max_hp, 6 + 2 + 2 * (4 + 2), "wizard hp")
	eq(w.spell_dc(), 13, "spell dc")
	var c = pc("cleric")
	eq(c.ac, 14 + 0 + 2, "scale+shield")
	eq("disciple-of-life" in c.features, true, "life domain")
	var g = Creature.make_monster(srd, "goblin")
	eq([g.ac, g.max_hp, g.speed, g.xp_value], [15, 7, 30, 50], "goblin")
	eq([g.attacks[0].bonus, g.attacks[0].ranged, g.attacks[1].ranged, g.attacks[1].long], [4, false, true, 320], "goblin attacks")
	eq(g.skill_bonus(srd, "stealth"), 6, "goblin stealth")

func t_attacks() -> void:
	var f = pc("fighter")
	var g = Creature.make_monster(srd, "goblin")
	var cb = duel(f, g)
	eq(cb.current(), f, "initiative order")
	cb.dice.queue = [10, 4]  # 10+5 = 15 hits ac 15, 4+3 damage
	var e = cb.attack(f, g)
	eq([e.hit, e.damage, g.hp], [true, 7, 0], "hit")
	eq(g.dead, true, "monster dies at 0")
	eq(cb.attack(f, g).ok, false, "no second action")

	g = Creature.make_monster(srd, "ogre")
	cb = duel(f, g)
	cb.dice.queue = [1]
	eq(cb.attack(f, g).hit, false, "natural 1 misses")
	cb = duel(f, g)
	cb.dice.queue = [20, 8, 8]
	e = cb.attack(f, g)
	eq([e.crit, e.damage], [true, 19], "crit")
	cb = duel(f, g)
	cb.add_condition(g, "prone")
	cb.dice.queue = [2, 15, 1]
	eq(cb.attack(f, g).rolls, [2, 15], "advantage vs prone in melee")
	cb = duel(f, g)
	cb.dice.queue = [15, 2]
	e = cb.attack(f, g, 1)
	eq([e.mode, e.hit], [-1, false], "ranged attack next to an enemy")
	cb = duel(f, g)
	cb.add_condition(g, "paralyzed")
	cb.dice.queue = [5, 9, 1, 1]  # advantage, then doubled dice
	e = cb.attack(f, g)
	eq([e.hit, e.crit], [true, true], "melee hit on paralyzed is a crit")
	eq(cb.save(g, "dex", 1).success, false, "paralyzed fails dex saves")
	cb = duel(f, g, Vector2i(3, 0))
	eq(cb.attack(f, g).ok, false, "melee out of reach")
	# resistance
	var sk = Creature.make_monster(srd, "skeleton")
	cb = duel(f, sk)
	eq(cb.damage(sk, 5, "bludgeoning"), 10, "vulnerable")
	eq(cb.damage(sk, 5, "poison"), 0, "immune")
	# sneak attack needs an ally next to the target, once a turn
	var r = pc("rogue", 3)
	var ally = pc("fighter")
	g = Creature.make_monster(srd, "ogre")
	cb = duel(r, g)
	cb.dice.queue = [15, 4]
	eq(cb.attack(r, g).has("sneak"), false, "no sneak alone")
	cb = duel(r, g)
	ally.pos = Vector2i(2, 0)
	cb.all.append(ally)
	cb.dice.queue = [15, 4, 6, 6]
	e = cb.attack(r, g)
	eq([e.get("sneak"), e.damage], [12, 4 + 3 + 12], "sneak attack")
	# fighter extras
	var f3 = pc("fighter", 3)
	cb = duel(f3, g)
	cb.dice.queue = [2]
	cb.attack(f3, g)
	eq(cb.action_surge(f3).ok, true, "action surge")
	eq(cb.attack(f3, g).ok, true, "second attack after surge")
	f3.hp = 5
	cb.dice.queue = [6]
	eq([cb.second_wind(f3).healed, f3.bonus], [9, false], "second wind")
	eq(cb.second_wind(f3).ok, false, "second wind once")
	# dodge
	cb = duel(f, g)
	cb.dodge(f)
	cb.end_turn()
	cb.dice.queue = [19, 3]
	eq(cb.attack(g, f).roll, 3, "dodge gives disadvantage")
	f.hp = f.max_hp
	# checks
	cb = duel(f, g)
	cb.dice.queue = [10]
	eq(cb.check(f, "str", 15, "athletics").success, true, "skill check")
	cb.add_condition(f, "poisoned")
	cb.dice.queue = [18, 3]
	eq(cb.check(f, "str", 15, "athletics").success, false, "poisoned check")

func t_death() -> void:
	var f = pc("fighter")
	var g = Creature.make_monster(srd, "goblin")
	var cb = duel(g, f)
	eq(cb.damage(f, 15), 15, "damage")
	eq([f.hp, f.dead, f.has("unconscious"), f.has("prone")], [0, false, true, true], "down, not dead")
	cb.dice.queue = [1]
	cb.end_turn()  # fighter's turn: death save, natural 1
	eq([f.death_f, cb.current() != f], [2, true], "nat 1 = two failures, turn skipped")
	cb.damage(f, 1)
	eq(f.dead, true, "third failure kills")
	f = pc("fighter")
	cb = duel(g, f)
	cb.damage(f, 12)
	cb.dice.queue = [20]
	cb.end_turn()
	eq([f.hp, cb.current()], [1, f], "nat 20 gets up and acts")
	cb.damage(f, 1)
	cb.heal(f, 5)
	eq([f.hp, f.has("unconscious"), f.death_f], [5, false, 0], "healing revives")
	f = pc("fighter")
	cb = duel(g, f)
	cb.damage(f, 24)
	eq(f.dead, true, "massive damage")
	f = pc("fighter")
	cb = duel(g, f)
	cb.damage(f, 12)
	cb.dice.queue = [10]
	cb.end_turn()
	eq([f.death_s, cb.current() != f], [1, true], "death save success")
	f.death_s = 2
	cb.dice.queue = [15]
	cb.end_turn()
	cb.end_turn()
	eq([f.stable, f.hp], [true, 0], "three successes = stable")

func t_spells() -> void:
	var w = pc("wizard", 3)
	var g = Creature.make_monster(srd, "ogre")
	var cb = duel(w, g, Vector2i(4, 0))
	cb.dice.queue = [15, 7]
	var e = cb.cast(w, "fire-bolt", [g])
	eq([e.results[0].hit, e.results[0].damage, w.slots[1]], [true, 7, 4], "fire bolt, no slot used")
	eq(cb.cast(w, "magic-missile", [g]).ok, false, "one action per turn")
	cb = duel(w, g, Vector2i(4, 0))
	cb.dice.queue = [1, 2, 3]
	e = cb.cast(w, "magic-missile", [g])
	eq([e.results[0].damage, w.slots[1]], [9, 3], "magic missile")
	cb = duel(w, g, Vector2i(4, 0))
	cb.dice.queue = [1, 1, 1, 1]
	eq(cb.cast(w, "magic-missile", [g], 2).results[0].damage, 8, "upcast")
	eq(w.slots[2], 1, "level 2 slot used")
	var g2 = Creature.make_monster(srd, "ogre")
	g2.pos = Vector2i(2, 1)
	cb = duel(w, g, Vector2i(2, 0))
	cb.all.append(g2)
	cb.dice.queue = [4, 4, 4, 20, 1]  # 12 fire; first ogre saves, second fails
	e = cb.cast(w, "burning-hands", [g, g2])
	eq([e.results[0].damage, e.results[1].damage], [6, 12], "save for half")
	w.slots = {}
	cb = duel(w, g)
	eq(cb.cast(w, "magic-missile", [g]).error, "no spell slot of level 1", "out of slots")
	eq(cb.cast(w, "shield", [w]).ok, false, "unprepared spell")
	# sleep
	w = pc("wizard")
	var a = Creature.make_monster(srd, "goblin")
	var b = Creature.make_monster(srd, "ogre")
	b.pos = Vector2i(3, 1)
	cb = duel(w, a, Vector2i(3, 0))
	cb.all.append(b)
	cb.dice.queue = [4, 4, 4, 4, 4]
	cb.cast(w, "sleep", [b, a])
	eq([a.has("unconscious"), b.has("unconscious")], [true, false], "sleep takes the weakest")
	cb.damage(a, 1)
	eq(a.has("unconscious"), false, "damage wakes a sleeper")
	# cleric: healing, bonus action rule, hold person and concentration
	var c = pc("cleric", 3)
	var f = pc("fighter")
	f.side = "party"
	var bandit = Creature.make_monster(srd, "bandit")
	cb = duel(c, bandit, Vector2i(2, 0))
	f.pos = Vector2i(0, 1)
	f.hp = 1
	cb.all.append(f)
	cb.dice.queue = [3]
	eq(cb.cast(c, "healing-word", [f]).results[0].healed, 3 + 3 + 3, "healing word + disciple of life")
	eq(cb.cast(c, "guiding-bolt", [bandit]).ok, false, "no leveled spell after a bonus-action spell")
	cb.dice.queue = [5, 1]  # damage, then the save
	eq(cb.cast(c, "sacred-flame", [bandit]).results[0].saved, false, "cantrip still allowed")
	cb = duel(c, bandit, Vector2i(2, 0))
	cb.dice.queue = [1, 1]  # bandit fails the save, then fails again at the end of its turn
	cb.cast(c, "hold-person", [bandit])
	eq([bandit.has("paralyzed"), c.conc], [true, "hold-person"], "hold person")
	cb.end_turn()
	eq(cb.current(), c, "paralyzed creature loses its turn")
	cb.dice.queue = [1]
	cb.damage(c, 4)
	eq([bandit.has("paralyzed"), c.conc], [false, ""], "failed concentration ends the spell")
	eq(cb.castable("bless"), true, "bless is automated")
	eq(cb.castable("guidance"), false, "guidance not automated yet")

func t_movement() -> void:
	var f = pc("fighter")
	var g = Creature.make_monster(srd, "goblin")
	var cb = duel(f, g)
	cb.dice.queue = [1]
	var e = cb.move(f, [Vector2i(-1, 0), Vector2i(-2, 0)])
	eq([f.pos, f.move_left, g.reaction], [Vector2i(-2, 0), 20, false], "move and opportunity attack")
	eq(cb.events.any(func(x): return x.type == "opportunity_attack"), true, "opportunity attack logged")
	cb = duel(f, g)
	cb.disengage(f)
	cb.move(f, [Vector2i(-1, 0)])
	eq(g.reaction, true, "disengage")
	cb = duel(f, g, Vector2i(5, 5))
	cb.blocked[Vector2i(1, 0)] = true
	eq(cb.move(f, [Vector2i(1, 0)]).ok, false, "wall")
	eq(cb.move(f, [Vector2i(2, 0)]).ok, false, "must step to a neighbour")
	cb.difficult[Vector2i(0, 1)] = true
	cb.move(f, [Vector2i(0, 1)])
	eq(f.move_left, 20, "difficult terrain")
	cb.dash(f)
	eq(f.move_left, 50, "dash")
	cb = duel(f, g, Vector2i(5, 5))
	cb.add_condition(f, "prone")
	cb.move(f, [Vector2i(0, 1)])
	eq([f.move_left, f.has("prone")], [10, false], "standing up costs half")
	var r = pc("rogue", 2)
	cb = duel(r, g)
	eq(cb.dash(r, true).ok, true, "cunning action")
	eq(cb.dash(f, true).ok, false, "fighter has no cunning action")

func t_rest_and_level() -> void:
	var d = Dice.new(1)
	var f = pc("fighter", 3)
	f.hp = 5
	f.res = {"second_wind": 0, "action_surge": 0}
	d.queue = [6]
	eq(f.short_rest(d, 1).healed, 8, "hit die + con")
	eq([f.hp, f.hit_dice, f.res.second_wind, f.res.action_surge], [13, 2, 1, 1], "short rest")
	var w = pc("wizard", 3)
	w.slots = {1: 0, 2: 0}
	eq(w.short_rest(d).slot_levels_recovered, 2, "arcane recovery")
	eq(w.slots, {1: 0, 2: 1}, "recovers highest slot")
	eq(w.short_rest(d).slot_levels_recovered, 0, "arcane recovery once a day")
	w.hp = 1
	w.long_rest()
	eq([w.hp, w.slots, w.res.arcane_recovery], [w.max_hp, {1: 4, 2: 2}, 1], "long rest")
	var c = pc("cleric")
	c.hp = 3
	c.slots[1] = 0
	eq(c.gain_xp(srd, 299), 0, "not yet")
	eq(c.gain_xp(srd, 1), 1, "level 2 at 300 xp")
	eq([c.level, c.max_hp, c.hp, c.slots[1], c.res.channel_divinity], [2, 10 + 7, 3 + 7, 1, 1], "level up")
	eq(c.gain_xp(srd, 600), 1, "level 3 at 900 xp")
	eq([c.level, c.slots_max], [3, {1: 4, 2: 2}], "level 3")
	eq(c.gain_xp(srd, 50000), 2, "capped at level 5")
	eq([c.level, c.slots_max, c.abil.wis], [5, {1: 4, 2: 3, 3: 2}, 18], "level 5, wisdom raised at level 4")
	var again = Creature.from_dict(srd, c.to_dict())
	eq([again.level, again.abil.wis, again.max_hp], [5, 18, c.max_hp], "level 5 survives a save")
	var k = hero("warlock", 2)
	k.slots = {1: 0}
	k.short_rest(d)
	eq(k.slots, {1: 2}, "pact magic returns on a short rest")
	k.gain_xp(srd, 900)
	eq(k.slots, {2: 2}, "warlock slots move up at level 3")

func t_classes() -> void:
	var probe = Combat.new(Dice.new(1), srd)
	for cls in GameScript.PRESETS:
		for lv in range(1, 6):
			var h = hero(cls, lv)
			eq(h.max_hp > 0 and h.ac >= 10 and not h.attacks.is_empty(), true, "%s %d builds" % [cls, lv])
			for sp in h.spells:
				eq(probe.castable(sp), true, "%s can cast %s" % [cls, sp])
			eq(h.spells.is_empty() or not h.slots_max.is_empty(), true, "%s %d has slots for its spells" % [cls, lv])
	# barbarian: unarmored defense, rage damage and resistance
	var b = hero("barbarian")
	var sk = Creature.make_monster(srd, "ogre")
	eq([b.ac, b.res.rage], [10 + 2 + 2, 2], "barbarian AC and rages")
	var cb = duel(b, sk)
	eq(cb.rage(b).ok, true, "rage")
	eq([b.bonus, b.res.rage], [false, 1], "rage costs a bonus action and a use")
	cb.dice.queue = [15, 6]
	eq(cb.attack(b, sk).damage, 6 + 3 + 2, "greataxe d12 + str + rage")
	eq(cb.damage(b, 9, "slashing"), 4, "rage halves weapon damage")
	eq(cb.damage(b, 9, "fire"), 9, "but not fire")
	b = hero("barbarian", 2)
	cb = duel(b, sk)
	cb.reckless(b)
	cb.dice.queue = [2, 15, 6]
	eq(cb.attack(b, sk).mode, 1, "reckless attack has advantage")
	# extra attack at level 5, ability increase at level 4
	var f = hero("fighter", 5)
	eq([f.multi, f.abil.str], [2, 18], "fighter 5")
	cb = duel(f, sk)
	eq([cb.attack(f, sk).ok, cb.attack(f, sk).ok, cb.attack(f, sk).ok], [true, true, false], "two swings per action")
	cb.action_surge(f)
	eq([cb.attack(f, sk).ok, cb.attack(f, sk).ok, cb.attack(f, sk).ok], [true, true, false], "action surge gives two more")
	# paladin: smite and lay on hands
	var p = hero("paladin", 2)
	var z = Creature.make_monster(srd, "ogre-zombie")
	cb = duel(p, z)
	p.smite = true
	cb.dice.queue = [15, 4, 3, 3, 3]
	var hit: Dictionary = cb.attack(p, z)
	eq([hit.get("smite"), hit.damage, p.slots[1]], [9, 4 + 3 + 9, 1], "smite: 3d8 against undead, one slot")
	p = hero("paladin", 2)
	var friend = hero("rogue")
	friend.hp = 2
	cb = allies(p, friend)
	eq([cb.lay_on_hands(p, friend).healed, p.res.lay_on_hands], [friend.max_hp - 2, 10 - (friend.max_hp - 2)], "lay on hands")
	# monk: martial arts and flurry
	var m = hero("monk", 2)
	eq([m.ac, m.res.ki, m.speed], [10 + 3 + 2, 2, 40], "monk AC, ki, speed")
	cb = duel(m, sk)
	var before: int = cb.events.size()
	eq(cb.bonus_strike(m, sk, true).ok, true, "flurry")
	eq([cb.events.slice(before).filter(func(e): return e.type == "attack").size(), m.res.ki, m.bonus, m.actions], [2, 1, false, 1],
		"flurry: two strikes, one ki, bonus action only")
	# cleric: turn undead, bless, shield of faith
	var c = hero("cleric", 2)
	var bones = Creature.make_monster(srd, "skeleton")
	cb = duel(c, bones)
	cb.dice.queue = [2]
	eq(cb.turn_undead(c).turned, ["Skeleton"], "skeleton fails and is turned")
	eq([cb.can_act(bones), c.res.channel_divinity], [false, 0], "turned creatures cannot act")
	cb.damage(bones, 1)
	eq(cb.can_act(bones), true, "damage ends turning")
	c = hero("cleric")
	friend = hero("fighter")
	cb = allies(c, friend)
	eq(cb.cast(c, "bless", [c, friend]).ok, true, "bless")
	eq([friend.has("blessed"), c.conc], [true, "bless"], "blessed, concentrating")
	cb.dice.queue = [10, 4]
	eq(cb.save(friend, "wis", 10).total, 10 + friend.save_bonus("wis") + 4, "bless adds d4 to saves")
	eq(cb.cast(c, "shield-of-faith", [friend]).ok, false, "second leveled spell the same turn is refused")
	cb.end_turn()
	while cb.current() != c:
		cb.end_turn()
	eq(cb.cast(c, "shield-of-faith", [friend]).ok, true, "shield of faith")
	eq([cb.ac_of(friend), friend.has("blessed")], [friend.ac + 2, false], "+2 AC, and it replaced bless")
	var w = hero("wizard")
	cb = duel(w, sk)
	cb.cast(w, "mage-armor", [w])
	eq(cb.ac_of(w), 13 + w.mod("dex"), "mage armor")
	# ranger: hunter's mark
	var r = hero("ranger", 2)
	cb = duel(r, sk, Vector2i(4, 0))
	eq(cb.cast(r, "hunters-mark", [sk]).ok, true, "hunter's mark")
	cb.dice.queue = [15, 5, 6]
	eq(cb.attack(r, sk).damage, 5 + 3 + 6, "longbow d8 + dex + mark d6")
	# monsters: multiattack and walking round a wall
	var bear = Creature.make_monster(srd, "brown-bear")
	eq([bear.multi, bear.multi_seq.size()], [2, 2], "bear multiattack")
	cb = duel(bear, hero("fighter"))
	before = cb.events.size()
	AI.take_turn(cb, bear)
	eq(cb.events.slice(before).filter(func(e): return e.type == "attack").size(), 2, "bear bites and claws")
	var g = Creature.make_monster(srd, "goblin")
	cb = duel(g, hero("fighter"), Vector2i(4, 0))
	for y in range(-3, 4):
		cb.blocked[Vector2i(2, y)] = true
	for i in 3:
		AI.take_turn(cb, g)
		while cb.winner() == "" and cb.current() != g:
			cb.end_turn()
	eq(cb.dist(g.pos, Vector2i(4, 0)) <= 5 or g.dead, true, "goblin gets round the wall")
	# mixed parties of the new classes, whole fights
	for s in 20:
		cb = Combat.new(Dice.new(s), srd)
		var all := []
		var party: Array = [["barbarian", "bard", "druid", "monk"], ["paladin", "ranger", "sorcerer", "warlock"]][s % 2]
		for i in 4:
			var h = hero(party[i], 3)
			h.pos = Vector2i(0, i * 2)
			all.append(h)
		for i in 2:
			var foe = Creature.make_monster(srd, "bugbear", "bugbear %d" % i)
			foe.pos = Vector2i(8, i * 3)
			all.append(foe)
		cb.start(all)
		var turns := 0
		while cb.winner() == "" and turns < 2000:
			turns += 1
			AI.take_turn(cb, cb.current())
		eq(cb.winner() != "", true, "mixed fight %d ends" % s)

func t_data() -> void:
	# Every SRD monster must load, and most need at least one usable attack.
	var armed := 0
	for id in srd.t.monsters:
		var m = Creature.make_monster(srd, id)
		eq(m.max_hp > 0 and m.ac > 0, true, "monster %s" % id)
		for a in m.attacks:
			armed += int(not a.damage.is_empty())
	eq(armed > 400, true, "monster attacks parsed (%d)" % armed)
	var cb = Combat.new(Dice.new(1), srd)
	for cls in ["cleric", "wizard"]:
		var ok := 0
		var total := 0
		for sp in srd.t.spells.values():
			if sp.level <= 2 and sp.classes.any(func(x): return x.index == cls):
				total += 1
				ok += int(cb.castable(sp.index))
		print("  %s spells of level 0-2 automated: %d of %d" % [cls, ok, total])

# Whole fights, both sides played by the AI, must always finish in a sane state.
func t_fights() -> void:
	var wins := 0
	for s in 30:
		var cb = Combat.new(Dice.new(s), srd)
		var all := []
		var classes := ["fighter", "rogue", "cleric", "wizard"]
		for i in 4:
			var p = pc(classes[i])
			p.pos = Vector2i(0, i * 2)
			all.append(p)
			var g = Creature.make_monster(srd, "goblin", "goblin %d" % i)
			g.pos = Vector2i(8, i * 2)
			all.append(g)
		cb.start(all)
		var turns := 0
		while cb.winner() == "" and turns < 2000:
			turns += 1
			AI.take_turn(cb, cb.current())
		eq(cb.winner() != "", true, "fight %d ends" % s)
		wins += int(cb.winner() == "party")
		var cells := {}
		for c in all:
			eq(c.hp >= 0 and c.hp <= c.max_hp, true, "hp in bounds")
			if not c.dead:
				eq(cells.has(c.pos), false, "two creatures in one cell")
				cells[c.pos] = true
		if cb.winner() == "party":
			eq(cb.events[-1].xp_each, 50, "xp award")
	print("  party won %d of 30 goblin fights" % wins)
