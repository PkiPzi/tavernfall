extends VBoxContainer
# The choices of the party creator that shape a hero beyond race and class: looks (hair, colour, beard, outfit), the six
# ability scores by point buy, the class's skill proficiencies, a fighting style, and cantrips and spells for casters.
# Works on one slot of the creator (`s`), keeping its picks in s.extra, and emits `changed` after every pick.

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")
const Assemble = preload("res://board/assemble.gd")
const Combat = preload("res://rules/combat.gd")

signal changed

const ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]
const COST = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
const POINTS = 27
# cantrips and level 1 spells a class picks at level 1 (what the rules allow, spellbook and prepared lists merged into one pick)
const SPELL_COUNTS = {"wizard": [3, 6], "sorcerer": [4, 2], "bard": [2, 4], "cleric": [3, 4], "druid": [2, 4], "warlock": [2, 2]}
const STYLES = {"fighter": ["defense", "dueling", "archery", "great-weapon-fighting", "two-weapon"], "paladin": ["defense", "dueling", "great-weapon-fighting"],
	"ranger": ["archery", "defense", "dueling", "two-weapon"]}
const STYLE_TIPS = {"defense": "+1 armour class while wearing armour", "dueling": "+2 damage with a one-handed melee weapon and nothing in the other hand",
	"archery": "+2 to attack rolls with ranged weapons", "great-weapon-fighting": "reroll 1s and 2s on the damage of two-handed melee weapons",
	"two-weapon": "add your ability modifier to the damage of the off-hand weapon"}

var s: Dictionary
var _castable := {}

func show_slot(slot: Dictionary) -> void:
	s = slot
	if not s.has("extra"):
		s["extra"] = {}
	for ch in get_children():
		ch.queue_free()
	add_theme_constant_override("separation", 6)
	_appearance()
	_abilities()
	_skills()
	_style()
	_spells()

func _ex(key: String, fallback):
	return s.extra.get(key, fallback)

func _put(key: String, value) -> void:
	s.extra[key] = value
	changed.emit()
	show_slot(s)

func _head(text: String, note := "") -> void:
	add_child(Ui.rule())
	var h := HBoxContainer.new()
	h.add_child(Ui.label(text, 16, Ui.GOLD))
	if note != "":
		var n := Ui.label("  " + note, 13, Ui.DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
	add_child(h)

# ---- looks ----------------------------------------------------------------------------------------------------

func _stepper(label: String, value: String, on_prev: Callable, on_next: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := Ui.label(label, 14, Ui.DIM)
	l.custom_minimum_size.x = 62
	row.add_child(l)
	row.add_child(Ui.button("<", on_prev))
	var v := Ui.label(value, 14, Ui.INK)
	v.custom_minimum_size.x = 150
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(v)
	row.add_child(Ui.button(">", on_next))
	return row

func _cycle(list: Array, cur: String, d: int) -> String:
	var i := list.find(cur)
	return list[posmod(i + d, list.size())]

func _appearance() -> void:
	_head("Looks")
	var sex := "f" if s.gender == "woman" else "m"
	var d := Assemble.default_look(int(s.seed), sex)
	var styles: Array = Assemble.HAIR_F if sex == "f" else Assemble.HAIR_M
	var hair: String = _ex("hair", d.hair)
	add_child(_stepper("Hair", hair.replace("_", " "), func(): _put("hair", _cycle(styles, hair, -1)), func(): _put("hair", _cycle(styles, hair, 1))))
	var cur_col: String = _ex("hair_color", d.hair_color)
	var sw := HFlowContainer.new()
	sw.add_theme_constant_override("h_separation", 4)
	sw.add_theme_constant_override("v_separation", 4)
	for cname in Assemble.HAIR_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(24, 24)
		b.tooltip_text = cname
		var c: Color = Assemble.HAIR_COLORS[cname]
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, Ui.flat(c, Ui.GOLD if cname == cur_col else Color(0, 0, 0, 0.6), 3 if cname == cur_col else 1, 12, 0))
		b.pressed.connect(func(): _put("hair_color", cname))
		sw.add_child(b)
	add_child(sw)
	if sex == "m":
		var beards: Array = [""] + Assemble.BEARDS
		var beard: String = _ex("beard", d.beard)
		add_child(_stepper("Beard", "none" if beard == "" else beard.replace("_", " "), func(): _put("beard", _cycle(beards, beard, -1)), func(): _put("beard", _cycle(beards, beard, 1))))
	add_child(_stepper("Outfit", "Look %d" % (int(s.variant) + 1), func(): s.variant = 1 - int(s.variant); changed.emit(); show_slot(s), func(): s.variant = 1 - int(s.variant); changed.emit(); show_slot(s)))

# ---- ability scores -------------------------------------------------------------------------------------------

func _scores() -> Dictionary:
	return _ex("abilities", Game.PRESETS[s.cls].abilities).duplicate()

func _spent(a: Dictionary) -> int:
	var n := 0
	for k in ABILITIES:
		n += COST.get(int(a[k]), 0)
	return n

func _abilities() -> void:
	var a := _scores()
	var left := POINTS - _spent(a)
	_head("Ability scores", "%d points left" % left)
	var bonus := {}
	for src in [Game.srd.t.races[s.race], Game.srd.t.subraces.get(s.get("subrace", ""), {})]:
		for b in src.get("ability_bonuses", []):
			bonus[b.ability_score.index] = int(bonus.get(b.ability_score.index, 0)) + int(b.bonus)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	for k in ABILITIES:
		var v: int = int(a[k])
		var total: int = v + int(bonus.get(k, 0))
		var l := Ui.label(k.to_upper(), 14, Ui.GOLD)
		l.custom_minimum_size.x = 36
		grid.add_child(l)
		var minus := Ui.button("-", func(): _bump(a, k, -1), v > 8)
		grid.add_child(minus)
		var val := Ui.label(str(v), 16, Ui.INK)
		val.custom_minimum_size.x = 26
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(val)
		var cost_next: int = COST.get(v + 1, 99) - COST.get(v, 0)
		grid.add_child(Ui.button("+", func(): _bump(a, k, 1), v < 15 and cost_next <= left))
		var rb := Ui.label("%+d" % bonus[k] if bonus.has(k) else "", 13, Color("7fd8e8"))
		rb.custom_minimum_size.x = 26
		grid.add_child(rb)
		var tl := Ui.label("= %d (%+d)" % [total, int(floor((total - 10) / 2.0))], 14, Ui.INK)
		tl.custom_minimum_size.x = 84
		grid.add_child(tl)
	add_child(grid)
	add_child(Ui.button("Reset to the class's usual scores", func(): s.extra.erase("abilities"); changed.emit(); show_slot(s)))

func _bump(a: Dictionary, k: String, d: int) -> void:
	a[k] = int(a[k]) + d
	_put("abilities", a)

# ---- skills ---------------------------------------------------------------------------------------------------

func _class_skills() -> Array:
	var c: Dictionary = Game.srd.t.classes[s.cls]
	var pc: Dictionary = c.proficiency_choices[0]
	var opts := []
	for o in pc["from"]["options"]:
		opts.append(str(o["item"]["index"]).trim_prefix("skill-"))
	return [int(pc["choose"]), opts]

func _skills() -> void:
	var cs := _class_skills()
	var want: int = cs[0]
	var chosen: Array = _ex("skills", Game.PRESETS[s.cls].skills).filter(func(k): return k in cs[1])
	_head("Skills", "%d of %d chosen" % [chosen.size(), want])
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for k in cs[1]:
		var on: bool = k in chosen
		var b := Ui.button(str(k).replace("-", " ").capitalize(), func():
			var now: Array = chosen.duplicate()
			if on:
				now.erase(k)
			elif now.size() < want:
				now.append(k)
			else:
				now.pop_front()
				now.append(k)
			_put("skills", now))
		var sk = Game.srd.t.skills[k]
		b.tooltip_text = "%s (%s)" % [sk.name, str(sk.ability_score.index).to_upper()]
		if on:
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, Ui.flat(Color("2c3a22"), Ui.GOLD, 2, 5, 8))
		grid.add_child(b)
	add_child(grid)
	if s.cls == "rogue":
		var ex: Array = _ex("expertise", Game.PRESETS.rogue.get("expertise", [])).filter(func(k): return k in chosen)
		add_child(Ui.label("Expertise (double bonus), pick two:", 13, Ui.DIM))
		var eg := HFlowContainer.new()
		eg.add_theme_constant_override("h_separation", 4)
		for k in chosen:
			var on2: bool = k in ex
			var b2 := Ui.button(str(k).replace("-", " ").capitalize(), func():
				var now: Array = ex.duplicate()
				if on2:
					now.erase(k)
				else:
					now.append(k)
					if now.size() > 2:
						now.pop_front()
				_put("expertise", now))
			if on2:
				for st in ["normal", "hover", "pressed"]:
					b2.add_theme_stylebox_override(st, Ui.flat(Color("3a2c12"), Ui.GOLD, 2, 5, 8))
			eg.add_child(b2)
		add_child(eg)

# ---- fighting style -------------------------------------------------------------------------------------------

func _style() -> void:
	if not STYLES.has(s.cls):
		return
	_head("Fighting style")
	var cur: String = _ex("style", Game.PRESETS[s.cls].get("style", STYLES[s.cls][0]))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for st in STYLES[s.cls]:
		var b := Ui.button(str(st).replace("-", " ").capitalize(), func(): _put("style", st))
		b.tooltip_text = STYLE_TIPS.get(st, "")
		if st == cur:
			for state in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(state, Ui.flat(Color("2c3a22"), Ui.GOLD, 2, 5, 8))
		grid.add_child(b)
	add_child(grid)

# ---- spells ---------------------------------------------------------------------------------------------------

func _pool(level: int) -> Array:
	var cb := Combat.new(Game.dice, Game.srd)
	var out := []
	for sp in Game.srd.t.spells.values():
		if int(sp.level) == level and sp.classes.any(func(c): return c.index == s.cls) and cb.selectable(sp.index):
			out.append(sp)
	out.sort_custom(func(a, b): return a.name < b.name)
	return out

func _spells() -> void:
	if not SPELL_COUNTS.has(s.cls):
		return
	var counts: Array = SPELL_COUNTS[s.cls]
	var preset: Array = Game.PRESETS[s.cls].get("spells", [])
	var picked: Array = _ex("spells", preset)
	for lvl in [0, 1]:
		var pool := _pool(lvl)
		var want: int = counts[lvl]
		var mine: Array = picked.filter(func(x): return pool.any(func(p): return p.index == x))
		_head("Cantrips" if lvl == 0 else "First level spells", "%d of %d chosen" % [mine.size(), want])
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		for sp in pool:
			var on: bool = sp.index in mine
			grid.add_child(Ui.icon_button("", "", _tip(sp), func(): _toggle_spell(picked, sp.index, pool, want), true, on, 46, Hud.icon_for(sp.name, true)))
		add_child(grid)
		var names := []
		for x in mine:
			names.append(Game.srd.t.spells[x].name)
		var sl := Ui.label(", ".join(names) if not names.is_empty() else "none yet", 13, Ui.INK)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(sl)

func _toggle_spell(picked: Array, index: String, pool: Array, want: int) -> void:
	var now: Array = picked.duplicate()
	if index in now:
		now.erase(index)
	else:
		var same: Array = now.filter(func(x): return pool.any(func(p): return p.index == x))
		if same.size() >= want:
			now.erase(same[0])
		now.append(index)
	_put("spells", now)

func _tip(sp: Dictionary) -> String:
	var t: String = "%s  (%s)\n%s, %s" % [sp.name, sp.school.name, sp.casting_time, sp.range]
	if sp.has("damage") and sp.damage[0].has("damage_type"):
		t += "\n" + str(sp.damage[0].damage_type.name) + " damage"
	return t + "\n\n" + str(sp.desc[0]).left(260)
