extends RefCounted
# The inventory screen (press I): the hero on the left with worn gear slots, the backpack grid in the
# middle, and the picked item described on the right. Inventory.open(layer, creature, on_use) puts it over everything.
# on_use(item_id) is called for a consumable the player drinks from here; leave it empty to make items read only.

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")

const SLOT := 62.0

static func open(layer: CanvasLayer, c, on_use := Callable()) -> Control:
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
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(300, 0)
	detail.add_theme_constant_override("separation", 6)
	var ctx := {"c": c, "detail": detail, "root": root, "on_use": on_use}
	var items := _items(c)
	cols.add_child(_left(c, items, ctx))
	cols.add_child(_bag(items, ctx))
	cols.add_child(detail)
	_describe(ctx, {})
	return root

# Everything the creature carries: {id, name, kind (armour|shield|weapon|potion|item), icon, equipped, count, slot}.
const ARMOUR_ICON := {"chain-mail": "generated_arm_chainmail", "leather-armor": "generated_arm_camp_leather_a", "studded-leather-armor": "generated_arm_camp_leather_a_black",
	"scale-mail": "generated_arm_scalemail_1_magic", "breastplate": "generated_arm_breastplate_2_magic", "half-plate-armor": "generated_arm_halfplate_2_magic",
	"plate-armor": "generated_arm_plate_2_magic"}

static func _items(c) -> Array:
	var out := []
	var spec: Dictionary = c.spec
	var eq: Dictionary = Game.srd.t.equipment
	if spec.get("armor", "") != "":
		out.append({"id": spec.armor, "name": eq[spec.armor].name, "kind": "armour", "icon": _armour_icon(spec.armor), "equipped": true, "count": 1})
	if spec.get("shield", false):
		out.append({"id": "shield", "name": "Shield", "kind": "shield", "icon": load(Hud.ITEMS + "item_uni_gob_priest_shield.png"), "equipped": true, "count": 1})
	for wi in spec.get("weapons", []):
		out.append({"id": wi, "name": eq[wi].name, "kind": "weapon", "icon": Hud.icon_for(eq[wi].name), "equipped": true, "count": 1})
	for item in c.items:
		if c.items[item] > 0:
			var nm: String = str(item).replace("-", " ").capitalize()
			out.append({"id": item, "name": nm, "kind": "potion" if "potion" in item else "item",
				"icon": Hud.icon_for("Potion") if "potion" in item else Ui.icon("health-potion"), "equipped": false, "count": c.items[item]})
	return out

static func _armour_icon(id: String) -> Texture2D:
	var f: String = Hud.ITEMS + "%s.png" % ARMOUR_ICON.get(id, "gen_armor")
	return load(f) if ResourceLoader.exists(f) else Ui.icon("checked-shield")

static func _slot_box(it: Dictionary, ctx: Dictionary) -> Control:
	var e := {"icon": it.get("icon"), "enabled": true, "on": func(): _describe(ctx, it), "tip": it.get("name", ""),
		"count": "" if it.get("count", 1) <= 1 else str(it.count)}
	var s := Hud.slot(e)
	s.custom_minimum_size = Vector2(SLOT, SLOT)
	return s

static func _empty(label := "") -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.add_theme_stylebox_override("panel", Ui.flat(Color(0.06, 0.05, 0.04, 0.8), Color(0.35, 0.28, 0.16, 0.7), 1, 4, 0))
	if label != "":
		var l := Ui.label(label, 11, Ui.DIM)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	return p

static func _left(c, items: Array, ctx: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(260, 0)
	v.add_theme_constant_override("separation", 6)
	var face := Hud.round_portrait(c, 150.0, "combatants/btn_small_round_d")
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(face)
	var n := Ui.title(c.name, 22)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	v.add_child(Ui.rule())
	# Worn gear: one frame per slot, filled when the hero has something for it.
	var want := [["Armour", "armour"], ["Shield", "shield"], ["Melee", "melee"], ["Ranged", "ranged"]]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for w in want:
		var found := {}
		for it in items:
			if not it.equipped:
				continue
			var ranged: bool = it.kind == "weapon" and Game.srd.t.equipment[it.id].weapon_range == "Ranged"
			if (w[1] == "armour" and it.kind == "armour") or (w[1] == "shield" and it.kind == "shield") \
					or (w[1] == "melee" and it.kind == "weapon" and not ranged) or (w[1] == "ranged" and ranged):
				found = it
				break
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		cell.add_child(_slot_box(found, ctx) if not found.is_empty() else _empty())
		var cap := Ui.label(w[0], 11, Ui.DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(cap)
		grid.add_child(cell)
	v.add_child(grid)
	v.add_child(Ui.rule())
	var weight := 0.0
	for it in items:
		var d: Dictionary = Game.srd.t.equipment.get(it.id, {})
		weight += float(d.get("weight", 0)) * it.count
	v.add_child(Ui.label("Armour class   %d" % c.ac, 15))
	v.add_child(Ui.label("Carrying   %.1f lb  of  %d lb" % [weight, int(c.abil.str) * 15], 15, Ui.DIM))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	v.add_child(Ui.button("Close", func(): ctx.root.queue_free()))
	return v

static func _bag(items: Array, ctx: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.add_child(Ui.title("Backpack", 15, Ui.GOLD))
	v.add_child(Ui.rule())
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var carried := items.filter(func(it): return not it.equipped)
	for i in 20:
		grid.add_child(_slot_box(carried[i], ctx) if i < carried.size() else _empty())
	v.add_child(grid)
	v.add_child(Ui.label("Worn and held gear is on the left.", 13, Ui.DIM))
	return v

static func _describe(ctx: Dictionary, it: Dictionary) -> void:
	var d: VBoxContainer = ctx.detail
	for ch in d.get_children():
		ch.queue_free()
	d.add_child(Ui.title("Item", 15, Ui.GOLD))
	d.add_child(Ui.rule())
	if it.is_empty():
		var hint := Ui.label("Pick an item to read about it.", 15, Ui.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_child(hint)
		return
	d.add_child(Ui.title(it.name, 22))
	var eq: Dictionary = Game.srd.t.equipment.get(it.id, {})
	var lines: Array = []
	match it.kind:
		"weapon":
			lines.append("%s %s, %s" % [eq.weapon_category, "ranged" if eq.weapon_range == "Ranged" else "melee", eq.damage.damage_type.name.to_lower()])
			lines.append("Damage   %s" % eq.damage.damage_dice)
			var props: Array = eq.properties.map(func(p): return p.name)
			if not props.is_empty():
				lines.append(", ".join(props))
		"armour":
			lines.append("%s" % eq.get("armor_category", "Armour"))
			lines.append("Armour class   %d%s" % [int(eq.armor_class.base), " + Dexterity" if eq.armor_class.dex_bonus else ""])
			if eq.get("stealth_disadvantage", false):
				lines.append("Disadvantage on Stealth")
		"shield":
			lines.append("+2 armour class while held")
		"potion":
			lines.append("Drink it: regain 2d4 + 2 hit points.")
	if eq.has("weight"):
		lines.append("Weight   %s lb" % str(eq.weight))
	if eq.has("cost"):
		lines.append("Worth   %s %s" % [str(int(eq.cost.quantity)), str(eq.cost.unit)])
	for ln in lines:
		var l := Ui.label(ln, 15, Ui.INK if ln == lines[0] else Ui.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_child(l)
	if it.kind == "potion" and ctx.on_use.is_valid():
		d.add_child(Ui.button("Drink", func(): ctx.on_use.call(it.id); ctx.root.queue_free()))
