extends RefCounted
# Shared look for the 2D interface: dark panels, warm gold accents.

const GOLD := Color("e8c15a")
const INK := Color("e6dfd0")
const DIM := Color("9a948a")

static func panel(alpha := 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.062, 0.055, alpha)
	sb.border_color = Color(0.42, 0.33, 0.16, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p

static func label(text: String, size := 16, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, on: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("2b241c"), "hover": Color("4a3a1e"), "pressed": Color("6b5320"), "disabled": Color("1c1917")}[state]
		sb.border_color = Color("6b5320") if state != "disabled" else Color("2b241c")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): Game.sfx("metal_click"))
	b.pressed.connect(on)
	return b

# A framed painted portrait of a creature. Shows its initial until the picture arrives.
static func portrait(c, size: Vector2, border := GOLD, width := 2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1917")
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(width)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	p.tooltip_text = c.name
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(t)
	var l := label(c.name.substr(0, 1), int(size.y * 0.5), DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	_fill(t, l, c)
	return p

static func _fill(t: TextureRect, l: Label, c) -> void:
	var tex: Texture2D = await Game.portrait(c)
	if tex != null and is_instance_valid(t):
		t.texture = tex
		l.visible = false

static func bar(value: float, top: float, color: Color, height := 6) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = max(top, 1)
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size.y = height
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color("120f0d")
	back.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", back)
	return b

static func hp_color(c) -> Color:
	return Color("b8382c") if c.hp * 2 < c.max_hp else Color("4f9a4a")

# Portrait, name and health for the party column on the left of every screen.
static func hero_card(c, big := 76) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var face := portrait(c, Vector2(big, big * 1.2), DIM if c.dead else GOLD)
	if c.dead or c.hp == 0:
		face.modulate = Color(0.45, 0.4, 0.4)
	v.add_child(face)
	v.add_child(bar(c.hp, c.max_hp, hp_color(c)))
	var l := label("%s  %d/%d" % [c.name, c.hp, c.max_hp], 12, INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v

# A slowly circling camera over a place, for menus and the story screen.
static func orbit_camera(parent: Node3D, center: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = center
	pivot.rotation = Vector3(-0.62, 0.6, 0)
	parent.add_child(pivot)
	var cam := Camera3D.new()
	cam.fov = 45
	cam.position = Vector3(0, 0, 13)
	pivot.add_child(cam)
	return pivot
