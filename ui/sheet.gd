extends RefCounted
# The character sheet, laid out in three columns like the game's: face and level on the left,
# abilities, saves and skills in the middle, gear, spells and features on the right.
# Sheet.open(layer, creature) puts it over everything; Escape, a click outside or Close removes it.

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")
const Inventory = preload("res://ui/inventory.gd")

const ABIL = ["str", "dex", "con", "int", "wis", "cha"]
const SKILLS = {"acrobatics": "dex", "animal-handling": "wis", "arcana": "int", "athletics": "str", "deception": "cha",
	"history": "int", "insight": "wis", "intimidation": "cha", "investigation": "int", "medicine": "wis", "nature": "int",
	"perception": "wis", "performance": "cha", "persuasion": "cha", "religion": "int", "sleight-of-hand": "dex",
	"stealth": "dex", "survival": "wis"}

static func open(layer: CanvasLayer, c) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 50
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	shade.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: root.queue_free())
	root.add_child(shade)
	var panel := Ui.panel(0.97)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	panel.add_child(cols)
	cols.add_child(_left(c, root))
	cols.add_child(_middle(c))
	cols.add_child(_right(c))
	return root

static func _col(width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override("separation", 5)
	return v

static func _head(text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.add_child(Ui.title(text, 15, Ui.GOLD))
	v.add_child(Ui.rule())
	return v

static func _left(c, root: Control) -> Control:
	var v := _col(230)
	v.add_child(Hud.round_portrait(c, 180.0, "combatants/btn_small_round_d"))
	var face: Control = v.get_child(0)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var n := Ui.title(c.name, 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var sub := Ui.label("%s %s, level %d" % [c.spec.get("race", "").capitalize(), c.cls.capitalize(), c.level], 16, Ui.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Ui.rule())
	v.add_child(Ui.label("Hit points   %d / %d" % [c.hp, c.max_hp], 16))
	v.add_child(Hud.hp_bar(c, 220.0, 10.0))
	var next := 0
	if c.level < c.XP_FOR_LEVEL.size() - 1:
		next = c.XP_FOR_LEVEL[c.level + 1]
	v.add_child(Ui.label("Experience   %d%s" % [c.xp, " / %d" % next if next > 0 else ""], 15, Ui.DIM))
	if next > 0:
		v.add_child(Ui.bar(c.xp, next, Hud.SLOT_PURPLE, 6))
	var stat := GridContainer.new()
	stat.columns = 2
	stat.add_theme_constant_override("h_separation", 16)
	for pair in [["Armour class", str(c.ac)], ["Speed", "%d ft" % c.speed], ["Proficiency", "+%d" % c.prof], ["Hit die", "d%d" % c.hit_die]]:
		stat.add_child(Ui.label(pair[0], 15, Ui.DIM))
		stat.add_child(Ui.label(pair[1], 15, Ui.INK))
	v.add_child(stat)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var layer := root.get_parent()
	v.add_child(Ui.button("Bag", func(): root.queue_free(); Inventory.open(layer, c)))
	v.add_child(Ui.button("Close", func(): root.queue_free()))
	return v

static func _middle(c) -> Control:
	var v := _col(330)
	v.add_child(_head("Abilities"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for k in ABIL:
		var box := Ui.panel(0.7)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var l1 := Ui.label(k.to_upper(), 11, Ui.DIM)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l2 := Ui.title(str(c.abil[k]), 20, Ui.INK)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l3 := Ui.label("%+d" % c.mod(k), 12, Ui.GOLD)
		l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l1)
		col.add_child(l2)
		col.add_child(l3)
		box.add_child(col)
		row.add_child(box)
	v.add_child(row)
	v.add_child(_head("Saving throws"))
	var saves := GridContainer.new()
	saves.columns = 3
	saves.add_theme_constant_override("h_separation", 14)
	for k in ABIL:
		var on: bool = k in c.save_profs
		saves.add_child(Ui.label("%s %s %+d" % ["●" if on else "○", k.to_upper(), c.mod(k) + (c.prof if on else 0)], 14, Ui.GOLD if on else Ui.DIM))
	v.add_child(saves)
	v.add_child(_head("Skills"))
	var sk := GridContainer.new()
	sk.columns = 2
	sk.add_theme_constant_override("h_separation", 18)
	sk.add_theme_constant_override("v_separation", 0)
	for name in SKILLS:
		var lvl: int = c.skills.get(name, 0)
		var bonus: int = c.mod(SKILLS[name]) + c.prof * lvl
		sk.add_child(Ui.label("%s %s %+d" % ["◆" if lvl > 1 else ("●" if lvl == 1 else "○"), name.replace("-", " ").capitalize(), bonus], 13,
			Ui.GOLD if lvl > 0 else Ui.DIM))
	v.add_child(sk)
	return v

static func _line(icon: Texture2D, text: String, sub := "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var slot := Hud.slot({"icon": icon, "enabled": true, "on": func(): pass, "tip": text})
	slot.custom_minimum_size = Vector2(38, 38)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(Ui.label(text, 15))
	if sub != "":
		col.add_child(Ui.label(sub, 12, Ui.DIM))
	h.add_child(col)
	return h

static func _right(c) -> Control:
	var v := _col(330)
	v.add_child(_head("Equipment"))
	var spec: Dictionary = c.spec
	if spec.get("armor", "") != "":
		v.add_child(_line(Ui.icon("checked-shield"),
			str(spec.armor).replace("-", " ").capitalize(), "Armour class %d" % c.ac))
	if spec.get("shield", false):
		v.add_child(_line(Ui.icon("shield"), "Shield", "+2 armour class"))
	for a in c.attacks:
		var dmg: Array = a.damage.map(func(d): return "%s %s" % [d.dice, d.type])
		v.add_child(_line(Hud.icon_for(a.name), a.name, "%+d to hit   %s" % [a.bonus, ", ".join(dmg)]))
	for item in c.items:
		if c.items[item] > 0:
			v.add_child(_line(Hud.icon_for("Potion") if "potion" in item else Ui.icon("health-potion"), str(item).replace("-", " ").capitalize(), "x%d" % c.items[item]))
	if not c.spells.is_empty():
		v.add_child(_head("Spells"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		for sp in c.spells:
			var d: Dictionary = Game.srd.t.spells[sp]
			flow.add_child(Hud.slot({"icon": Hud.icon_for(d.name, true), "enabled": true, "on": func(): pass,
				"tip": "%s (level %d)" % [d.name, int(d.level)], "count": "" if d.level == 0 else str(int(d.level))}))
		v.add_child(flow)
		var slot_line := ""
		for k in c.slots_max:
			slot_line += "L%d  %d/%d     " % [k, c.slots.get(k, 0), c.slots_max[k]]
		if slot_line != "":
			v.add_child(Ui.label("Spell slots   " + slot_line, 14, Hud.SLOT_PURPLE))
	if not c.features.is_empty():
		v.add_child(_head("Features"))
		var f := Ui.label(", ".join(c.features.map(func(x): return str(x).replace("-", " ").capitalize())), 14)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(f)
	return v
