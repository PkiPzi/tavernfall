extends RefCounted
# The level-up screen shown after a fight that raised heroes a level: one card per hero with the
# new level, hit points, spells and features gained. LevelUp.open(layer, Game.levelups).

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")

static func open(layer: CanvasLayer, ups: Array) -> Control:
	Game.sound("UI_HUD_Level_Up", "power_up_3")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 60
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.7)
	root.add_child(shade)
	var panel := Ui.panel(0.97)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := Ui.title("LEVEL UP", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Ui.rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for u in ups:
		row.add_child(_card(u))
	var ok := Ui.button("Continue", func(): root.queue_free())
	ok.custom_minimum_size = Vector2(240, 0)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ok)
	# the panel eases in from a little below, like the game's banners
	panel.modulate.a = 0.0
	var tw := root.create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
	return root

static func _card(u: Dictionary) -> Control:
	var c = u.c
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(230, 0)
	v.add_theme_constant_override("separation", 5)
	var face := Hud.round_portrait(c, 130.0, "combatants/btn_small_round_d")
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(face)
	var n := Ui.title(c.name, 22)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var lv := Ui.label("Level %d  ->  %d" % [u.from, u.to], 18, Ui.GOLD)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lv)
	v.add_child(Ui.rule())
	v.add_child(Ui.label("+%d hit points" % u.hp, 16, Ui.GREEN))
	if not u.spells.is_empty():
		v.add_child(Ui.label("New spells", 14, Ui.DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		for sp in u.spells:
			var d: Dictionary = Game.srd.t.spells[sp]
			var s := Hud.slot({"icon": Hud.icon_for(d.name, true), "enabled": true, "on": func(): pass, "tip": d.name})
			flow.add_child(s)
		v.add_child(flow)
	if not u.features.is_empty():
		v.add_child(Ui.label("New features", 14, Ui.DIM))
		var f := Ui.label(", ".join(u.features.map(func(x): return str(x).replace("-", " ").capitalize())), 15)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(f)
	return v
