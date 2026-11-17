extends RefCounted
# Shared look for the 2D interface, in the manner of a modern party CRPG:
# near-black leather panels, bronze trim, engraved capitals for titles, a book serif for text.

const GOLD := Color("d9b566")
const BRONZE := Color("7a6236")
const INK := Color("e9dfc8")
const DIM := Color("94897a")
const DARK := Color("120e0b")
const RED := Color("b4402f")
const GREEN := Color("5f9a4c")

const TITLE_FONT = preload("res://assets/fonts/Cinzel.ttf")
const BODY_FONT = preload("res://assets/fonts/EBGaramond.ttf")
const ITALIC_FONT = preload("res://assets/fonts/EBGaramond-Italic.ttf")

const CLASS_ICON = {"barbarian": "barbarian", "bard": "lyre", "cleric": "ankh", "druid": "oak-leaf", "fighter": "crossed-swords",
	"monk": "meditation", "paladin": "winged-shield", "ranger": "pocket-bow", "rogue": "hood", "sorcerer": "fire-ray",
	"warlock": "warlock-eye", "wizard": "wizard-staff"}

static func font(base: Font, weight: int, spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {"wght": weight}
	f.spacing_glyph = spacing
	return f

static func icon(id: String) -> Texture2D:
	return load("res://assets/icons/%s.svg" % id)

static func flat(bg: Color, border := BRONZE, width := 1, radius := 3, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

# A stylebox from a BG3 interface image (assets/bg3/ui/<path>.png), stretched by its corners.
# Null when the art is missing, so callers keep the flat box.
static func tex_box(path: String, margin: Vector4, content := Vector4(14, 8, 14, 8)) -> StyleBoxTexture:
	var f := "res://assets/bg3/ui/%s.png" % path
	if not ResourceLoader.exists(f):
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = load(f)
	sb.texture_margin_left = margin.x
	sb.texture_margin_top = margin.y
	sb.texture_margin_right = margin.z
	sb.texture_margin_bottom = margin.w
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb

# The theme every screen inherits. Set once on the window by game.gd.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(BODY_FONT, 500)
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", _panel_box(0.9))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBox = tex_box("cc/btnnormal_" + {"normal": "d", "hover": "h", "pressed": "p", "disabled": "disabled", "focus": "d"}[state],
			Vector4(34, 20, 34, 20), Vector4(24, 8, 24, 8))
		if sb == null or state == "focus":  # no BG3 art on this machine, or the focus ring: plain boxes
			var flat_sb := flat({"normal": Color("1d1711"), "hover": Color("3a2c17"), "pressed": Color("54401c"),
				"disabled": Color("151210"), "focus": Color(0, 0, 0, 0)}[state],
				{"normal": BRONZE, "hover": GOLD, "pressed": GOLD, "disabled": Color("2c261d"), "focus": Color(0, 0, 0, 0)}[state], 1, 3, 7)
			flat_sb.content_margin_left = 16
			flat_sb.content_margin_right = 16
			sb = flat_sb
		for kind in ["Button", "OptionButton"]:
			t.set_stylebox(state, kind, sb)
	for kind in ["Button", "OptionButton"]:
		t.set_font("font", kind, font(TITLE_FONT, 600, 1))
		t.set_font_size("font_size", kind, 16)
		t.set_color("font_color", kind, INK)
		t.set_color("font_hover_color", kind, GOLD)
		t.set_color("font_pressed_color", kind, GOLD)
		t.set_color("font_disabled_color", kind, Color("5a5347"))
	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, flat(Color("0c0a08"), Color("4a3d25"), 1, 3, 8))
		t.set_stylebox("focus", kind, flat(Color("0c0a08"), GOLD, 1, 3, 8))
		t.set_color("font_color", kind, INK)
		t.set_color("font_placeholder_color", kind, Color("6a6154"))
		t.set_color("caret_color", kind, GOLD)
	t.set_stylebox("panel", "PopupMenu", flat(Color("15110d"), BRONZE, 1, 3, 6))
	t.set_stylebox("hover", "PopupMenu", flat(Color("3a2c17"), Color(0, 0, 0, 0), 0, 2, 4))
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", flat(Color("0f0c09"), GOLD, 1, 3, 10))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_font("normal_font", "RichTextLabel", font(BODY_FONT, 500))
	t.set_font("bold_font", "RichTextLabel", font(BODY_FONT, 700))
	t.set_font("italics_font", "RichTextLabel", font(ITALIC_FONT, 500))
	t.set_color("default_color", "RichTextLabel", INK)
	return t

static func _panel_box(alpha: float) -> StyleBox:
	var art := tex_box("cc/appearancepane", Vector4(34, 34, 34, 34), Vector4(30, 26, 30, 26))  # the painted frame is about 34 px thick: text must stay inside it
	if art != null:
		art.modulate_color = Color(1, 1, 1, clampf(alpha + 0.1, 0.0, 1.0))
		return art
	var sb := flat(Color(0.065, 0.052, 0.042, alpha), Color(0.48, 0.38, 0.2, 0.95), 1, 4, 14)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	return sb

static func panel(alpha := 0.9) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_box(alpha))
	return p

static func label(text: String, size := 18, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# Engraved capitals, for headings.
static func title(text: String, size := 28, color := GOLD) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", font(TITLE_FONT, 600, 1))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

# A thin bronze line with a brighter middle, to part sections.
static func rule() -> Control:
	var r := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(GOLD, 0.0))
	g.set_color(1, Color(GOLD, 0.0))
	g.add_point(0.5, Color(GOLD, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.height = 2
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size.y = 2
	return r

static func button(text: String, on: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Game.sound("UI_DefaultButton_Click", "metal_click", 0.02, -8.0))
	b.mouse_entered.connect(func(): if not b.disabled: Game.bg3("UI_DefaultButton_Hover", 0.03, -16.0))
	b.pressed.connect(on)
	return b

# A line of plain text that lights up under the pointer: menu entries and dialogue answers.
static func text_button(text: String, on: Callable, size := 20, enabled := true) -> Button:
	var b := button(text, on, enabled)
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", size)
	for state in ["normal", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4))
	var hover := flat(Color(GOLD, 0.1), Color(0, 0, 0, 0), 0, 2, 4)
	hover.border_width_left = 2
	hover.border_color = GOLD
	b.add_theme_stylebox_override("hover", hover)
	return b

# A square action button: an icon, a tooltip, and a small caption underneath.
# lit marks the one that is armed (the chosen attack or spell).
static func icon_button(icon_id: String, caption: String, tip: String, on: Callable, enabled := true, lit := false, side := 54, tex: Texture2D = null) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var b := button("", on, enabled)
	b.icon = tex if tex != null else icon(icon_id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(side, side)
	b.tooltip_text = tip
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := flat({"normal": Color("1a1510"), "hover": Color("33270f"), "pressed": Color("54401c"), "disabled": Color("12100e")}[state],
			GOLD if lit or state in ["hover", "pressed"] else (Color("2a241c") if state == "disabled" else BRONZE), 2 if lit else 1, 5, 7)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("icon_normal_color", GOLD if lit else INK)
	b.add_theme_color_override("icon_hover_color", GOLD)
	b.add_theme_color_override("icon_pressed_color", GOLD)
	b.add_theme_color_override("icon_disabled_color", Color("4a443b"))
	v.add_child(b)
	var l := label(caption, 12, DIM if enabled else Color("4a443b"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = side + 8
	l.clip_text = true
	v.add_child(l)
	return v

# A framed painted portrait of a creature. Shows its class emblem until the picture arrives.
static func portrait(c, size: Vector2, border := GOLD, width := 2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := flat(Color("17120e"), border, width, 6, width)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	p.tooltip_text = c.name
	var emblem := TextureRect.new()
	emblem.texture = icon(CLASS_ICON.get(c.cls, "death-skull"))
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.modulate = Color(BRONZE, 0.8)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(emblem)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(t)
	_fill(t, emblem, c)
	return p

static func _fill(t: TextureRect, emblem: Control, c) -> void:
	var tex: Texture2D = await Game.portrait(c)
	if tex != null and is_instance_valid(t):
		t.texture = tex
		emblem.visible = false

# Any generated picture in a frame (scenes, people the heroes meet). Stays empty until it arrives.
static func picture(prompt: String, size: Vector2, w := 512, h := 288) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(Color("0d0a08"), BRONZE, 1, 4, 2))
	p.custom_minimum_size = size
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	p.add_child(t)
	_fill_picture(t, prompt, w, h)
	return p

static func _fill_picture(t: TextureRect, prompt: String, w: int, h: int) -> void:
	var tex: Texture2D = await Game.picture(prompt, w, h)
	if tex != null and is_instance_valid(t):
		t.texture = tex
		t.modulate.a = 0.0
		t.create_tween().tween_property(t, "modulate:a", 1.0, 0.8)

static func bar(value: float, top: float, color: Color, height := 6) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = max(top, 1)
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size.y = height
	b.add_theme_stylebox_override("fill", flat(color, color, 0, 2, 0))
	b.add_theme_stylebox_override("background", flat(Color("0b0908"), Color("2c261d"), 1, 2, 0))
	return b

static func hp_color(c) -> Color:
	return RED if c.hp * 2 < c.max_hp else GREEN

static func sheet(c) -> String:
	var slots: Array = c.slots_max.keys().map(func(k): return "L%d %d/%d" % [k, c.slots.get(k, 0), c.slots_max[k]])
	var potions: int = c.items.get("potion-of-healing", 0)
	return "%s\n%s %s, level %d\nHit points %d/%d   Armour class %d   XP %d%s%s%s" % [c.name, c.spec.race.capitalize(),
		c.cls.capitalize(), c.level, c.hp, c.max_hp, c.ac, c.xp,
		"\nSpell slots  " + "  ".join(slots) if not slots.is_empty() else "",
		"\nHealing potions %d" % potions if potions > 0 else "", "\nDead" if c.dead else ""]

# Portrait, name and health for the party column on the left of every screen. Hover for the sheet.
static func hero_card(c, big := 76) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var face := portrait(c, Vector2(big, big * 1.25), Color("4a4136") if c.dead else GOLD)
	if c.is_pc:
		face.tooltip_text = sheet(c)
	if c.dead or c.hp == 0:
		face.modulate = Color(0.45, 0.4, 0.4)
	v.add_child(face)
	v.add_child(bar(c.hp, c.max_hp, hp_color(c)))
	var l := label("%s  %d/%d" % [c.name, c.hp, c.max_hp], 14, INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v

# Darkens the corners of the screen so the eye stays on the middle.
static func vignette(layer: CanvasLayer, strength := 0.75) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, strength))
	g.set_offset(0, 0.45)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	layer.move_child(r, 0)

# A slowly circling camera over a place, for menus and the story screen.
static func orbit_camera(parent: Node3D, center: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = center
	pivot.rotation = Vector3(-0.5, 0.6, 0)
	parent.add_child(pivot)
	var cam := Camera3D.new()
	cam.fov = 38
	cam.position = Vector3(0, 0, 21.0)
	var blur := CameraAttributesPractical.new()  # soft background, sharp where the heroes stand
	blur.dof_blur_far_enabled = true
	blur.dof_blur_far_distance = 26.0
	blur.dof_blur_far_transition = 12.0
	blur.dof_blur_amount = 0.06
	cam.attributes = blur
	pivot.add_child(cam)
	return pivot
