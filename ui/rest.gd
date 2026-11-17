extends RefCounted
# The rest menu, as in BG3: pick a short rest (spend hit dice, recover some abilities) or a long rest (everything back).
# Rest.open(layer, on_done) where on_done(kind, lines) is called after the rest is applied.

const Ui = preload("res://ui/ui.gd")
const ICON := "res://assets/bg3/ui/restmenu/%s.png"

static func open(layer: CanvasLayer, on_done: Callable) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 55
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	shade.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: root.queue_free())
	root.add_child(shade)
	var panel := Ui.panel(0.97)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(620, 0)
	panel.add_child(v)
	var t := Ui.title("Rest", 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Ui.rule())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(_choice("short", "Short rest", "About an hour. Each hero may spend hit dice to heal; a wizard recovers some spell slots.", on_done, root))
	row.add_child(_choice("long", "Long rest", "A night's sleep. Hit points, spell slots and abilities all return.", on_done, root))
	var party := Game.party.filter(func(c): return not c.dead)
	var worn := party.filter(func(c): return c.hp < c.max_hp).size()
	var info := Ui.label("%d of %d heroes are hurt." % [worn, party.size()], 15, Ui.DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	var close := Ui.button("Not now", func(): root.queue_free())
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(200, 0)
	v.add_child(close)
	return root

static func _choice(kind: String, name: String, blurb: String, on_done: Callable, root: Control) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(270, 0)
	col.add_theme_constant_override("separation", 6)
	var b := TextureButton.new()
	var f := ICON % ("c_ico_%srest_d" % kind)
	var h := ICON % ("c_ico_%srest_h" % kind)
	if ResourceLoader.exists(f):
		b.texture_normal = load(f)
		b.texture_hover = load(h) if ResourceLoader.exists(h) else null
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(120, 120)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Game.sound("UI_HUD_CC_Accept_Click", "metal_click")
		root.queue_free()
		on_done.call(kind, apply(kind)))
	col.add_child(b)
	var n := Ui.title(name, 20)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var d := Ui.label(blurb, 14, Ui.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(d)
	return col

# Applies the rest to the living party; returns lines for the player.
static func apply(kind: String) -> Array:
	var notes := []
	for c in Game.party:
		if c.dead:
			continue
		var before: int = c.hp
		if kind == "short":
			c.short_rest(Game.dice, c.hit_dice)
		else:
			c.long_rest()
		if c.hp > before:
			notes.append("%s recovers %d hit points." % [c.name, c.hp - before])
	notes.push_front("The party takes a %s rest." % kind)
	return notes
