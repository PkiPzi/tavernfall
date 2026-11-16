extends RefCounted
# Turn-based 5e combat on a square grid (1 cell = 5 ft, diagonals cost the same).
# Every call returns a Dictionary: {"ok": false, "error": ...} or what happened.
# The same dictionaries are appended to `events` for the UI and the narrator.

# What each condition does. atk/def: 1 advantage, -1 disadvantage on attacks by / against.
const COND = {
	"blinded": {"atk": -1, "def": 1},
	"charmed": {},
	"deafened": {},
	"frightened": {"atk": -1, "checks": -1},  # shortcut: assumes the source stays in sight
	"grappled": {"speed0": true},
	"incapacitated": {"incap": true},
	"invisible": {"atk": 1, "def": -1},
	"paralyzed": {"incap": true, "def": 1, "autofail": true, "crit_melee": true, "speed0": true},
	"petrified": {"incap": true, "def": 1, "autofail": true, "speed0": true, "resist_all": true},
	"poisoned": {"atk": -1, "checks": -1},
	"prone": {"atk": -1},  # attacks against it depend on distance, handled in _mode
	"restrained": {"atk": -1, "def": 1, "dex_save": -1, "speed0": true},
	"stunned": {"incap": true, "def": 1, "autofail": true, "speed0": true},
	"unconscious": {"incap": true, "def": 1, "autofail": true, "crit_melee": true, "speed0": true},
	# Not SRD conditions, but they ride the same list so they time out and end with concentration.
	"turned": {"incap": true},  # shortcut: a turned creature stands frozen instead of fleeing
	"raging": {}, "blessed": {}, "shielded": {}, "mage-armored": {}, "marked": {},
}

var dice
var srd
var all := []
var order := []
var turn_i := -1
var round_no := 0
var events := []
var blocked := {}    # Vector2i -> true: walls and pillars
var difficult := {}  # Vector2i -> true: costs double to enter

func _init(d, s) -> void:
	dice = d
	srd = s

func emit(e: Dictionary) -> Dictionary:
	e["ok"] = true
	events.append(e)
	return e

func err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}

static func dist(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y)) * 5

func flag(c, key: String) -> bool:
	return c.conditions.any(func(x): return COND.get(x.id, {}).has(key))

func active(c) -> bool:
	return not c.dead and c.hp > 0

func can_act(c) -> bool:
	return active(c) and not flag(c, "incap")

func current():
	return order[turn_i]

func at(cell: Vector2i):
	for c in all:
		if not c.dead and c.pos == cell:
			return c
	return null

# "" while the fight is on, otherwise the side left standing.
func winner() -> String:
	var up := {}
	for c in all:
		if active(c):
			up[c.side] = true
	return "" if up.size() > 1 else (up.keys()[0] if up.size() == 1 else "nobody")

func start(creatures: Array) -> Dictionary:
	all = creatures
	var init := {}
	for c in all:
		init[c] = dice.d20().roll + c.mod("dex")
	order = all.duplicate()
	order.sort_custom(func(a, b): return init[a] > init[b] or (init[a] == init[b] and a.abil.dex > b.abil.dex))
	round_no = 1
	turn_i = -1
	emit({"type": "initiative", "order": order.map(func(c): return c.name)})
	return _advance()

func end_turn() -> Dictionary:
	_tick(current())
	return _advance()

func _advance() -> Dictionary:
	for guard in order.size() * 300:
		if winner() != "":
			return emit({"type": "end", "winner": winner(), "xp_each": xp_each()})
		turn_i += 1
		if turn_i >= order.size():
			turn_i = 0
			round_no += 1
		var c = current()
		if c.dead:
			continue
		for x in all:
			x.sneak_used = false
		c.actions = 1
		c.bonus = true
		c.reaction = true
		c.move_left = 0 if flag(c, "speed0") else c.speed
		c.dodging = false
		c.disengaged = false
		c.attacks_left = 0
		c.reckless = false
		c.cast_bonus_spell = false
		c.cast_leveled_action = false
		if c.hp == 0 and not c.stable:
			death_save(c)
		if not can_act(c):
			if c.hp > 0:
				_tick(c)
			continue
		return emit({"type": "turn", "who": c.name, "round": round_no})
	return emit({"type": "end", "winner": "nobody", "xp_each": 0})

# End of a creature's turn: repeat saves and count down timed conditions.
func _tick(c) -> void:
	for x in c.conditions.duplicate():
		if x.get("save", "") != "" and save(c, x.save, x.dc).success:
			remove_condition(c, x.id)
		elif x.rounds > 0:
			x.rounds -= 1
			if x.rounds == 0:
				remove_condition(c, x.id)

func xp_each() -> int:
	var total := 0
	var party := 0
	for c in all:
		if c.is_pc:
			party += 1
		elif not active(c):
			total += c.xp_value
	return total / max(party, 1)

# ---- conditions -------------------------------------------------------------

# rounds -1 = until removed. o: {save, dc} repeat save at end of turn, {wake} ends on damage,
# {by} the caster whose concentration holds it.
func add_condition(c, id: String, rounds := -1, o := {}) -> bool:
	if id in c.cond_immune or c.dead:
		return false
	remove_condition(c, id, false)
	var x := {"id": id, "rounds": rounds}
	x.merge(o)
	c.conditions.append(x)
	emit({"type": "condition", "who": c.name, "condition": id, "on": true})
	return true

func remove_condition(c, id: String, tell := true) -> void:
	var n: int = c.conditions.size()
	c.conditions = c.conditions.filter(func(x): return x.id != id)
	if tell and c.conditions.size() < n:
		emit({"type": "condition", "who": c.name, "condition": id, "on": false})

func break_concentration(c) -> void:
	if c.conc == "":
		return
	emit({"type": "concentration_lost", "who": c.name, "spell": c.conc})
	c.conc = ""
	for t in all:
		for x in t.conditions.duplicate():
			if x.get("by") == c:
				remove_condition(t, x.id)

# ---- d20 tests --------------------------------------------------------------

func check(c, ability: String, dc: int, skill := "", mode := 0) -> Dictionary:
	if flag(c, "checks"):
		mode -= 1
	var r: Dictionary = dice.d20(clampi(mode, -1, 1))
	var total: int = r.roll + (c.skill_bonus(srd, skill) if skill != "" else c.mod(ability))
	return emit({"type": "check", "who": c.name, "skill": skill, "ability": ability,
		"roll": r.roll, "rolls": r.rolls, "total": total, "dc": dc, "success": total >= dc})

func save(c, ability: String, dc: int, mode := 0) -> Dictionary:
	if ability in ["str", "dex"] and flag(c, "autofail"):
		return emit({"type": "save", "who": c.name, "ability": ability, "dc": dc, "roll": 0, "total": 0, "success": false})
	if ability == "dex":
		mode += (-1 if flag(c, "dex_save") else 0) + (1 if c.dodging and can_act(c) else 0)
	var r: Dictionary = dice.d20(clampi(mode, -1, 1))
	var total: int = r.roll + c.save_bonus(ability) + (dice.die(4) if c.has("blessed") else 0)
	return emit({"type": "save", "who": c.name, "ability": ability, "roll": r.roll, "rolls": r.rolls,
		"total": total, "dc": dc, "success": total >= dc})

func death_save(c) -> Dictionary:
	var r: int = dice.d20().roll
	if r == 20:
		heal(c, 1)
	elif r >= 10:
		c.death_s += 1
		if c.death_s >= 3:
			c.stable = true
	else:
		c.death_f += 2 if r == 1 else 1
		if c.death_f >= 3:
			_die(c)
	return emit({"type": "death_save", "who": c.name, "roll": r, "successes": c.death_s,
		"failures": c.death_f, "stable": c.stable, "dead": c.dead})

# ---- damage and healing -----------------------------------------------------

func _die(c) -> void:
	c.dead = true
	c.hp = 0
	c.conditions = []
	break_concentration(c)
	emit({"type": "dead", "who": c.name})

# Returns the damage actually taken after resistance, vulnerability and immunity.
func damage(t, amount: int, type := "", crit := false) -> int:
	if t.dead:
		return 0
	if type in t.immune:
		amount = 0
	elif type in t.resist or flag(t, "resist_all") \
			or (t.has("raging") and type in ["bludgeoning", "piercing", "slashing"]):
		amount /= 2
	elif type in t.vuln:
		amount *= 2
	if amount <= 0:
		return 0
	if t.hp == 0:  # already dying
		if amount >= t.max_hp:
			_die(t)
		else:
			t.stable = false
			t.death_f += 2 if crit else 1
			if t.death_f >= 3:
				_die(t)
		return amount
	var over: int = amount - t.hp
	t.hp = max(t.hp - amount, 0)
	for x in t.conditions.duplicate():
		if x.get("wake", false):
			remove_condition(t, x.id)
	if t.hp == 0:
		if not t.is_pc or over >= t.max_hp:
			_die(t)
		else:
			break_concentration(t)
			t.death_s = 0
			t.death_f = 0
			t.stable = false
			emit({"type": "down", "who": t.name})
			add_condition(t, "unconscious")
			add_condition(t, "prone")
	elif t.conc != "" and not save(t, "con", max(10, amount / 2)).success:
		break_concentration(t)
	return amount

func heal(t, amount: int) -> int:
	if t.dead or amount <= 0:
		return 0
	var was: int = t.hp
	t.hp = min(t.max_hp, t.hp + amount)
	if was == 0:
		t.death_s = 0
		t.death_f = 0
		t.stable = false
		remove_condition(t, "unconscious")
	emit({"type": "heal", "who": t.name, "amount": t.hp - was, "hp": t.hp})
	return t.hp - was

# ---- attacks ----------------------------------------------------------------

# Advantage (1), disadvantage (-1) or neither (0) for one attack roll.
func _mode(a, t, ranged: bool, far: bool) -> int:
	var adv := false
	var dis := false
	for x in a.conditions:
		var v: int = COND.get(x.id, {}).get("atk", 0)
		adv = adv or v > 0
		dis = dis or v < 0
	for x in t.conditions:
		var v: int = COND.get(x.id, {}).get("def", 0)
		adv = adv or v > 0
		dis = dis or v < 0
	if t.has("prone"):
		if dist(a.pos, t.pos) <= 5:
			adv = true
		else:
			dis = true
	if t.dodging and can_act(t):
		dis = true
	if t.reckless or (a.reckless and not ranged):
		adv = true
	if ranged:
		dis = dis or far or all.any(func(o): return o.side != a.side and can_act(o) and dist(o.pos, a.pos) <= 5)
	return int(adv) - int(dis)

# Armour class right now, with spells that raise it.
func ac_of(t) -> int:
	var v: int = t.ac
	if t.has("mage-armored"):
		v = max(v, 13 + t.mod("dex"))
	return v + (2 if t.has("shielded") else 0)

# free = true skips the turn and action cost (opportunity attacks, bonus-action strikes).
# One Attack action covers `multi` swings (Extra Attack, Multiattack).
func attack(a, t, i := 0, free := false) -> Dictionary:
	if not free:
		if a != current():
			return err("not this creature's turn")
		if a.actions < 1 and a.attacks_left < 1:
			return err("no action left")
	if i >= a.attacks.size():
		return err("no such attack")
	if t.dead or not can_act(a):
		return err("invalid attacker or target")
	var w: Dictionary = a.attacks[i]
	var d := dist(a.pos, t.pos)
	if d > (w.long if w.ranged else w.reach):
		return err("out of range")
	var mode := _mode(a, t, w.ranged, w.ranged and d > w.range)
	if not free:
		if a.attacks_left > 0:
			a.attacks_left -= 1
		else:
			a.actions -= 1
			a.attacks_left = a.multi - 1
	var r: Dictionary = dice.d20(mode)
	var crit: bool = r.roll >= a.crit_min
	var bonus: int = w.bonus + (dice.die(4) if a.has("blessed") else 0)
	var hit: bool = crit or (r.roll != 1 and r.roll + bonus >= ac_of(t))
	if hit and d <= 5 and flag(t, "crit_melee"):
		crit = true
	var e := emit({"type": "attack", "who": a.name, "target": t.name, "weapon": w.name, "roll": r.roll,
		"rolls": r.rolls, "total": r.roll + bonus, "ac": ac_of(t), "mode": mode, "hit": hit, "crit": crit, "damage": 0})
	if not hit:
		return e
	var parts := []
	for p in w.damage:
		parts.append([dice.roll(p.dice, crit), p.type])
	if a.has("raging") and not w.ranged and w.get("abil", "str") == "str":
		parts[0][0] += a.rage_bonus
	if t.conditions.any(func(x): return x.id == "marked" and x.get("by") == a):  # Hunter's Mark
		parts[0][0] += dice.roll("1d6", crit)
	# Divine Smite: the lowest slot, 2d8 radiant, +1d8 per slot level above 1st and against undead and fiends.
	if a.smite and not w.ranged:
		var slot := 0
		for k in a.slots:
			if a.slots[k] > 0 and (slot == 0 or k < slot):
				slot = k
		if slot > 0:
			a.slots[slot] -= 1
			e["smite"] = dice.roll("%dd8" % (1 + slot + (1 if t.kind in ["undead", "fiend"] else 0)), crit)
			parts.append([e.smite, "radiant"])
	# Sneak Attack: once a turn, finesse or ranged weapon, with advantage or an ally next to the target.
	if a.sneak_dice > 0 and not a.sneak_used and (w.ranged or w.finesse) and mode >= 0 and (mode > 0 \
			or all.any(func(o): return o != a and o.side == a.side and can_act(o) and dist(o.pos, t.pos) <= 5)):
		a.sneak_used = true
		e["sneak"] = dice.roll("%dd6" % a.sneak_dice, crit)
		parts[0][0] += e.sneak
	for p in parts:
		e.damage += damage(t, p[0], p[1], crit)
	e["target_hp"] = t.hp
	return e

# ---- movement ---------------------------------------------------------------

# path: the cells to step through, each next to the one before. Leaving an enemy's reach
# without Disengage gives it an opportunity attack.
func move(c, path: Array) -> Dictionary:
	if c != current():
		return err("not this creature's turn")
	var e := {"type": "move", "who": c.name, "from": c.pos, "path": []}
	for cell in path:
		if not active(c):
			break
		if dist(c.pos, cell) != 5 or blocked.has(cell) or at(cell) != null:
			return _moved(e, c, "cannot enter %s" % cell)
		var cost := 10 if difficult.has(cell) else 5
		if c.has("prone"):  # standing up costs half speed
			if c.move_left < c.speed / 2 + cost:
				return _moved(e, c, "not enough movement to stand up")
			c.move_left -= c.speed / 2
			remove_condition(c, "prone")
		if c.move_left < cost:
			return _moved(e, c, "not enough movement")
		if not c.disengaged:
			for o in all:
				if o.side != c.side and can_act(o) and o.reaction and not o.attacks.is_empty() \
						and not o.attacks[0].ranged and dist(o.pos, c.pos) <= o.attacks[0].reach \
						and dist(o.pos, cell) > o.attacks[0].reach:
					o.reaction = false
					emit({"type": "opportunity_attack", "who": o.name, "target": c.name})
					attack(o, c, 0, true)
		if not active(c):
			break
		c.move_left -= cost
		c.pos = cell
		e.path.append(cell)
	return _moved(e, c, "")

func _moved(e: Dictionary, c, problem: String) -> Dictionary:
	e["to"] = c.pos
	e["stopped"] = problem
	if not e.path.is_empty():
		emit(e)
	return err(problem) if problem != "" else e.merged({"ok": true})

# ---- other actions ----------------------------------------------------------

# Takes the action (or the bonus action, for rogues with Cunning Action). "" when paid.
func _pay(c, as_bonus := false) -> String:
	if c != current() or not can_act(c):
		return "not this creature's turn"
	if as_bonus:
		if not c.bonus:
			return "no bonus action left"
		c.bonus = false
	else:
		if c.actions < 1:
			return "no action left"
		c.actions -= 1
	return ""

func _simple(c, what: String, as_bonus: bool) -> Dictionary:
	if as_bonus and not "cunning-action" in c.features:
		return err("needs Cunning Action")
	var p := _pay(c, as_bonus)
	if p != "":
		return err(p)
	match what:
		"dash":
			c.move_left += 0 if flag(c, "speed0") else c.speed
		"dodge":
			c.dodging = true
		"disengage":
			c.disengaged = true
	return emit({"type": what, "who": c.name})

func dash(c, as_bonus := false) -> Dictionary:
	return _simple(c, "dash", as_bonus)

func disengage(c, as_bonus := false) -> Dictionary:
	return _simple(c, "disengage", as_bonus)

func dodge(c) -> Dictionary:
	return _simple(c, "dodge", false)

func second_wind(c) -> Dictionary:
	if c.res.get("second_wind", 0) < 1:
		return err("Second Wind not available")
	var p := _pay(c, true)
	if p != "":
		return err(p)
	c.res["second_wind"] -= 1
	return emit({"type": "second_wind", "who": c.name, "healed": heal(c, dice.roll("1d10") + c.level)})

func action_surge(c) -> Dictionary:
	if c != current() or c.res.get("action_surge", 0) < 1:
		return err("Action Surge not available")
	c.res["action_surge"] -= 1
	c.actions += 1
	return emit({"type": "action_surge", "who": c.name})

# ---- class features ---------------------------------------------------------

func rage(c) -> Dictionary:
	if c.res.get("rage", 0) < 1 or c.has("raging"):
		return err("Rage not available")
	var p := _pay(c, true)
	if p != "":
		return err(p)
	c.res["rage"] -= 1
	add_condition(c, "raging", 10)
	return emit({"type": "rage", "who": c.name})

# Advantage on melee attacks this turn; attacks against the barbarian have advantage until its next turn.
func reckless(c) -> Dictionary:
	if c != current() or not "reckless-attack" in c.features or c.reckless:
		return err("Reckless Attack not available")
	c.reckless = true
	return emit({"type": "reckless_attack", "who": c.name})

# Monk: one unarmed strike as a bonus action, or two for a ki point (Flurry of Blows).
func bonus_strike(c, t, flurry := false) -> Dictionary:
	var i: int = c.attacks.find_custom(func(w): return w.get("unarmed", false))
	if i < 0 or (flurry and c.res.get("ki", 0) < 1):
		return err("not available")
	if t.dead or dist(c.pos, t.pos) > 5:
		return err("out of range")
	var p := _pay(c, true)
	if p != "":
		return err(p)
	if flurry:
		c.res["ki"] -= 1
	var e := attack(c, t, i, true)
	if flurry and not t.dead and can_act(c):
		e = attack(c, t, i, true)
	return e

func lay_on_hands(c, t) -> Dictionary:
	var pool: int = c.res.get("lay_on_hands", 0)
	if pool < 1 or t.dead or t.hp >= t.max_hp:
		return err("nothing to heal")
	if dist(c.pos, t.pos) > 5:
		return err("out of range")
	var p := _pay(c)
	if p != "":
		return err(p)
	var amount: int = min(pool, t.max_hp - t.hp)
	c.res["lay_on_hands"] -= amount
	return emit({"type": "lay_on_hands", "who": c.name, "target": t.name, "healed": heal(t, amount)})

# Channel Divinity: undead within 30 ft that fail a Wisdom save are turned for a minute or until hurt.
func turn_undead(c) -> Dictionary:
	if c.res.get("channel_divinity", 0) < 1 or c.cls != "cleric":
		return err("Channel Divinity not available")
	var p := _pay(c)
	if p != "":
		return err(p)
	c.res["channel_divinity"] -= 1
	var e := emit({"type": "turn_undead", "who": c.name, "turned": []})
	for t in all:
		if t.kind == "undead" and active(t) and dist(c.pos, t.pos) <= 30 and not save(t, "wis", c.spell_dc()).success:
			add_condition(t, "turned", 10, {"wake": true})
			e.turned.append(t.name)
	return e

# shortcut: only the healing potion exists; add an item table when loot arrives.
func use_item(c, item: String, t = null) -> Dictionary:
	if item != "potion-of-healing" or c.items.get(item, 0) < 1:
		return err("no such item")
	t = t if t != null else c
	if dist(c.pos, t.pos) > 5:
		return err("out of range")
	var p := _pay(c)
	if p != "":
		return err(p)
	c.items[item] -= 1
	return emit({"type": "item", "who": c.name, "item": item, "target": t.name, "healed": heal(t, dice.roll("2d4+2"))})

# ---- spells -----------------------------------------------------------------

func _spell_range(sp: Dictionary) -> int:
	if sp.range == "Touch":
		return 5
	return int(sp.range) if sp.range.ends_with("feet") else -1  # -1: self or special, no check

# Spells whose effect is not a plain damage roll or heal in the data.
func _special(c, sp: Dictionary, targets: Array, slot: int) -> bool:
	match sp.index:
		"sleep":  # weakest first, until the hit point pool runs out
			var pool: int = dice.roll("%dd8" % (5 + 2 * (slot - 1)))
			targets.sort_custom(func(a, b): return a.hp < b.hp)
			for t in targets:
				if active(t) and t.hp <= pool and t.kind != "undead" and not t.has("unconscious"):
					pool -= t.hp
					add_condition(t, "unconscious", 10, {"wake": true})
		"hold-person":
			c.conc = sp.index
			for t in targets.slice(0, slot - 1):
				if t.kind == "humanoid" and not save(t, "wis", c.spell_dc()).success:
					add_condition(t, "paralyzed", 10, {"save": "wis", "dc": c.spell_dc(), "by": c})
		"bless":
			c.conc = sp.index
			for t in targets.slice(0, 2 + slot):
				add_condition(t, "blessed", 10, {"by": c})
		"shield-of-faith":
			c.conc = sp.index
			add_condition(targets[0], "shielded", 100, {"by": c})
		"mage-armor":
			add_condition(targets[0], "mage-armored")
		"hunters-mark":
			c.conc = sp.index
			add_condition(targets[0], "marked", -1, {"by": c})
		_:
			return false
	return true

const SPECIAL = ["sleep", "hold-person", "bless", "shield-of-faith", "mage-armor", "hunters-mark"]

# Which of a spell list the engine can resolve. The rest need code before they can be offered.
func castable(index: String) -> bool:
	var sp: Dictionary = srd.t.spells[index]
	var known: bool = index in SPECIAL or sp.has("heal_at_slot_level") or (sp.has("damage") \
		and (sp.damage[0].has("damage_at_slot_level") or sp.damage[0].has("damage_at_character_level")))
	return known and sp.casting_time in ["1 action", "1 bonus action"]

# targets: for area spells the board decides who is inside and passes them all.
func cast(c, index: String, targets: Array, slot := 0) -> Dictionary:
	if not index in c.spells:
		return err("spell not prepared")
	if not castable(index):
		return err("spell has no automated effect yet")
	var sp: Dictionary = srd.t.spells[index]
	var lvl := int(sp.level)
	if lvl > 0:
		slot = max(slot, lvl)
		if c.slots.get(slot, 0) < 1:
			return err("no spell slot of level %d" % slot)
	var as_bonus: bool = sp.casting_time == "1 bonus action"
	# A bonus-action spell allows only a cantrip with the action that turn, and the reverse.
	if (as_bonus and c.cast_leveled_action) or (not as_bonus and lvl > 0 and c.cast_bonus_spell):
		return err("already cast a spell this turn")
	var reach := _spell_range(sp)
	for t in targets:
		if t.dead or (reach >= 0 and dist(c.pos, t.pos) > reach):
			return err("invalid target or out of range")
	if targets.is_empty():
		return err("no target")
	var p := _pay(c, as_bonus)
	if p != "":
		return err(p)
	if lvl > 0:
		c.slots[slot] -= 1
		c.cast_leveled_action = not as_bonus
	c.cast_bonus_spell = c.cast_bonus_spell or as_bonus
	if sp.concentration:
		break_concentration(c)
	var e := emit({"type": "cast", "who": c.name, "spell": sp.name, "slot": slot if lvl > 0 else 0, "results": []})
	if _special(c, sp, targets, slot):
		return e

	if sp.has("heal_at_slot_level"):
		var expr: String = sp.heal_at_slot_level[str(slot)].replace("MOD", str(c.mod(c.cast_abil)))
		for t in targets:
			var extra := 2 + slot if "disciple-of-life" in c.features else 0
			e.results.append({"target": t.name, "healed": heal(t, dice.roll(expr) + extra)})
		return e

	var d: Dictionary = sp.damage[0]
	var expr := ""
	if d.has("damage_at_slot_level"):
		expr = d.damage_at_slot_level[str(slot)]
	else:
		for k in d.damage_at_character_level:  # cantrips grow with character level
			if int(k) <= c.level:
				expr = d.damage_at_character_level[k]
	var type: String = d.get("damage_type", {}).get("index", "")
	if sp.has("attack_type"):
		for t in targets:
			var r: Dictionary = dice.d20(_mode(c, t, sp.attack_type == "ranged", false))
			var crit: bool = r.roll == 20
			var hit: bool = crit or (r.roll != 1 and r.roll + c.spell_attack() >= ac_of(t))
			e.results.append({"target": t.name, "roll": r.roll, "total": r.roll + c.spell_attack(), "hit": hit,
				"crit": crit, "damage": damage(t, dice.roll(expr, crit), type, crit) if hit else 0})
	elif sp.has("dc"):
		var rolled: int = dice.roll(expr)  # one roll for everyone in the area
		for t in targets:
			# Sculpt Spells: an evoker's allies are untouched by their evocations.
			if "sculpt-spells" in c.features and sp.school.index == "evocation" and t.side == c.side:
				e.results.append({"target": t.name, "saved": true, "damage": 0})
				continue
			var ok: bool = save(t, sp.dc.dc_type.index, c.spell_dc()).success
			var amount: int = rolled if not ok else (rolled / 2 if sp.dc.dc_success == "half" else 0)
			e.results.append({"target": t.name, "saved": ok, "damage": damage(t, amount, type)})
	else:
		# Automatic hit (Magic Missile). shortcut: all darts go to the first target; split when the UI can ask.
		e.results.append({"target": targets[0].name, "damage": damage(targets[0], dice.roll(expr), type)})
	return e
