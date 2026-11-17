extends RefCounted
# The battle interface, built from Baldur's Gate 3's own interface art (assets/bg3/ui, exported by
# tools/bg3/ui_export.sh): ornate portrait rings, the turn-order cards, the long hotbar with its end
# caps, the glowing End Turn orb, action and bonus-action pips. Spell, action and weapon icons come
# from assets/bg3/icons. Everything degrades to plain boxes if the art is missing.

const Ui = preload("res://ui/ui.gd")
const DIR := "res://assets/bg3/ui/"
const SKILLS := "res://assets/bg3/icons/skills/"
const ITEMS := "res://assets/bg3/icons/items/"

const ALLY := Color("5b8fd6")
const FOE := Color("d0523f")
const ACTION_GREEN := Color("5fd36a")
const BONUS_ORANGE := Color("ff9a3c")
const SLOT_PURPLE := Color("b48cff")

static var _tex := {}
static var _skill_names: Array = []
static var _item_names: Array = []

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		var f := DIR + path + ".png"
		_tex[path] = load(f) if ResourceLoader.exists(f) else null
	return _tex[path]

static func _list(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			out.append(f.trim_suffix(".png"))
	return out

# The first icon of the folder whose name contains every keyword (shortest name wins), or null.
static func _find(names: Array, dir: String, words: Array, prefix := "") -> Texture2D:
	var best := ""
	for n in names:
		if prefix != "" and not n.begins_with(prefix):
			continue
		var ok := true
		for w in words:
			if not (w in n):
				ok = false
				break
		if ok and (best == "" or n.length() < best.length()):
			best = n
	return load(dir + best + ".png") if best != "" else null

static func skill_icon(words: Array) -> Texture2D:
	if _skill_names.is_empty():
		_skill_names = _list(SKILLS)
	return _find(_skill_names, SKILLS, words)

static func item_icon(words: Array) -> Texture2D:
	if _item_names.is_empty():
		_item_names = _list(ITEMS)
	return _find(_item_names, ITEMS, words, "item_wpn_")

# Words that find the icon of an action, a class feature or a weapon by its game name.
const ACTION_WORDS = {"Dash": ["action_dash"], "Disengage": ["action_disengage"], "Dodge": ["uncannydodge"],
	"Dash (bonus)": ["action_dash_bonus"], "Disengage (bonus)": ["action_disengage_bonus"], "Second Wind": ["skill_fighter_secondwind"],
	"Action Surge": ["skill_fighter_actionsurge"], "Rage": ["action_barbarian_rage"], "Reckless": ["action_barbarian_recklessattack"],
	"Smite": ["action_paladin_divinesmite"], "Lay on Hands": ["action_paladin_layonhands_smallheal"], "Turn Undead": ["spell_cleric_turnundead"],
	"Unarmed": ["action_monk_freeunarmedstrike"], "Flurry": ["action_monk_flurryofblows"], "Unarmed Strike": ["action_unarmedattack"],
	"Help": ["action_help"], "Hide": ["action_hide_regular"], "Hide (bonus)": ["action_hide_regular"], "Shove": ["action_shove"], "Jump": ["action_jump"], "Move": ["action_jump"]}

# An icon for a button: tries the action table, then the weapon name, then the spell name.
static func icon_for(label: String, spell := false) -> Texture2D:
	var base := label.split(" (")[0].split(" x")[0]
	if base.begins_with("Potion"):
		return load(ITEMS + "item_cons_potion_healing_a.png")
	for key in [label, base]:
		if ACTION_WORDS.has(key):
			var t := skill_icon(ACTION_WORDS[key])
			if t != null:
				return t
	if spell:
		var flat := base.to_lower().replace(" ", "").replace("'", "").replace("-", "")
		for words in [["spell_", flat], [flat]]:
			var t := skill_icon(words)
			if t != null:
				return t
	else:
		var t := item_icon([base.to_lower().replace(" ", "").replace(",", "").replace("light", "").replace("heavy", "")])
		if t != null:
			return t
		var parts := base.to_lower().replace(",", "").split(" ")
		t = item_icon([parts[0]])
		if t != null:
			return t
	return Ui.icon("crossed-swords")

# Condition and effect icons, found by BG3 skill-icon name words; anything not listed gets a generic mark.
const COND_ICON = {"blinded": ["spell_necromancy_blindness"], "stunned": ["action_monk_stunningstrike"], "restrained": ["spell_conjuration_entangled"],
	"poisoned": ["spell_conjuration_poisonspray"], "prone": ["action_monk_waterwhip_prone"], "frightened": ["spell_illusion_fear"],
	"invisible": ["passivefeature_generic_invisibility"], "faerie-fire": ["spell_evocation_faeriefire"], "blurred": ["spell_illusion_blur"],
	"raging": ["action_barbarian_rage"], "marked": ["spell_divination_huntersmark"], "blessed": ["spell_enchantment_bless"],
	"shielded": ["spell_evocation_fireshield_warm"], "mage-armored": ["spell_abjuration_magearmor"], "helped": ["action_help"],
	"hidden": ["action_hide_regular"], "turned": ["spell_illusion_fear"], "paralyzed": ["action_monk_stunningstrike"], "grappled": ["spell_conjuration_entangled"],
	"charmed": ["action_bard_countercharm"], "asleep": ["spell_enchantment_sleep"]}

# A row of small condition icons for a creature, each with its name and what is left of it on hover.
static func cond_row(c, side := 24.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for x in c.conditions:
		var t: Texture2D = skill_icon(COND_ICON.get(x.id, ["action_help"]))
		var r := TextureRect.new()
		r.texture = t
		r.custom_minimum_size = Vector2(side, side)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var left: int = x.get("rounds", -1)
		r.tooltip_text = str(x.id).replace("-", " ").capitalize() + (" (%d rounds)" % left if left > 0 else "")
		row.add_child(r)
	return row

# ---- round portraits ---------------------------------------------------------

static func _circle_clip(d: float) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("120e0b")
	sb.set_corner_radius_all(int(d / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func _fill(t: TextureRect, c) -> void:
	var img: Texture2D
	if c is String:
		img = await Game.bust_of(c)
	elif c is Dictionary:  # an assembled person: {race, sex, cls, look, hair, hair_color, beard}
		img = await Game.bust_spec(c)
	else:
		img = await Game.portrait(c)
	if img != null and is_instance_valid(t):
		t.texture = img
		t.modulate.a = 0.0
		t.create_tween().tween_property(t, "modulate:a", 1.0, 0.35)

# A creature's face in a circle with a ring around it. d is the size of the whole thing.
static func round_portrait(c, d: float, ring := "combatants/btn_small_round_d", tint := Color.WHITE) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(d, d)
	var r := TextureRect.new()  # the ring art has a dark centre, so it goes underneath the face
	r.texture = tex(ring)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	var inner := d * 0.8
	var disc := _circle_clip(inner)
	disc.position = Vector2(d - inner, d - inner) / 2.0
	root.add_child(disc)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(t)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fill(t, c)
	return root

static func hp_bar(c, w: float, h := 6.0) -> Control:
	var b := Ui.bar(c.hp, c.max_hp, Ui.hp_color(c), int(h))
	b.custom_minimum_size = Vector2(w, h)
	return b

# One card of the turn order along the top.
static func turn_card(c, now: bool) -> Control:
	var s := 1.0 if not now else 1.28
	var size := Vector2(50, 72) * s
	var root := Control.new()
	root.custom_minimum_size = size
	var card := TextureRect.new()
	card.texture = tex("combatants/default_d")
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var clip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("120e0b")
	sb.set_corner_radius_all(4)
	clip.add_theme_stylebox_override("panel", sb)
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip.position = Vector2(5, 5) * s
	clip.size = size - Vector2(10, 22) * s
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(t)
	_fill(t, c)
	var side: Color = ALLY if c.side == "party" else FOE
	var sel := TextureRect.new()  # the white outline of the card, tinted by team; brighter for the one acting
	sel.texture = tex("combatants/default_selected")
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sel.modulate = Ui.GOLD if now else side
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sel)
	var hp := hp_bar(c, size.x - 14 * s, 4.0)
	hp.position = Vector2(7, size.y - 14 * s)
	root.add_child(hp)
	root.tooltip_text = "%s  %d/%d" % [c.name, c.hp, c.max_hp]
	return root

# ---- the hotbar -----------------------------------------------------------------

const SLOT := 46.0

# One square on the hotbar. e = {icon: Texture2D, tip, on: Callable, enabled, lit, count: String}
static func slot(e: Dictionary) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(SLOT, SLOT)
	var enabled: bool = e.get("enabled", true)
	var lit: bool = e.get("lit", false)
	var b := Button.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = e.get("tip", "")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := Ui.flat(Color("0d0b0a") if state != "hover" else Color("231a10"), Color(0.55, 0.45, 0.27, 0.9), 1, 3, 0)
		if lit:
			sb.border_color = Ui.GOLD
			sb.set_border_width_all(2)
		if state == "hover":
			sb.border_color = Ui.GOLD
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 3
		b.add_theme_stylebox_override(state, sb)
	b.disabled = not enabled
	if enabled:
		b.pressed.connect(func(): Game.sound("UI_DefaultButton_Click", "metal_click", 0.02, -8.0))
		b.pressed.connect(e.on)
	root.add_child(b)
	var ic := TextureRect.new()
	ic.texture = e.get("icon")
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 3
	ic.offset_top = 3
	ic.offset_right = -3
	ic.offset_bottom = -3
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled:
		ic.modulate = Color(0.35, 0.35, 0.38, 0.85)
	root.add_child(ic)
	if e.get("count", "") != "":
		var l := Ui.label(e.count, 11, Ui.INK)
		l.position = Vector2(SLOT - 15, SLOT - 17)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
	return root

# A resource marker drawn the way the game does it: a round green one for the action,
# an orange triangle for the bonus action. Dark when spent.
class Pip extends Control:
	var color := Color.WHITE
	var on := true
	var tri := false

	func _init(c: Color, enabled: bool, triangle: bool) -> void:
		color = c
		on = enabled
		tri = triangle
		custom_minimum_size = Vector2(24, 24)

	func _draw() -> void:
		var mid := size / 2.0
		var fill: Color = color if on else Color("1c1916")
		var edge: Color = color.lightened(0.45) if on else Color("4a4238")
		if on:  # soft glow
			draw_circle(mid, 11.0, Color(color, 0.18))
		if tri:
			var pts := PackedVector2Array([mid + Vector2(0, -9), mid + Vector2(9, 7), mid + Vector2(-9, 7)])
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, edge, 1.6, true)
		else:
			draw_circle(mid, 8.0, fill)
			draw_arc(mid, 8.0, 0, TAU, 28, edge, 1.6, true)
			if on:
				draw_circle(mid + Vector2(-2, -2), 3.0, Color(1, 1, 1, 0.25))

static func pip(color: Color, on: bool, triangle := false) -> Control:
	return Pip.new(color, on, triangle)

# The movement bar over the hotbar: gold on dark, with the feet left.
static func move_bar(left: int, total: int) -> Control:
	var v := HBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var b := Ui.bar(left, total, Ui.GOLD, 9)
	b.custom_minimum_size = Vector2(150, 9)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	v.add_child(Ui.label("%d ft" % left, 13, Ui.INK if left >= 5 else Ui.DIM))
	return v

# The End Turn orb: three BG3 states, a label across it.
static func end_turn_orb(on: Callable, d := 84.0) -> Control:
	var b := TextureButton.new()
	b.texture_normal = tex("bottombar/btn_endturn_scaled_d")
	b.texture_hover = tex("bottombar/btn_endturn_scaled_h")
	b.texture_pressed = tex("bottombar/btn_endturn_scaled_p")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = Vector2(d, d)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "End your turn"
	b.pressed.connect(func(): Game.sound("UI_DefaultButton_Click", "metal_click", 0.02, -8.0))
	b.pressed.connect(on)
	var l := Ui.title("END\nTURN", 14, Color("cfe8ff"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color", Color(0, 0.1, 0.2, 0.9))
	b.add_child(l)
	return b

# The hotbar frame: left end cap (portrait ring), body, right end cap (the orb). Returns
# {root, portrait_at (centre of the ring in root coordinates), orb_at, body (Control to put slots in)}.
static func hotbar_frame(width: float, height: float) -> Dictionary:
	var k := height / 320.0 * 1.0   # scale of the 452x320 end caps
	var cap_w := 452.0 * k
	var root := Control.new()
	root.custom_minimum_size = Vector2(width, height)
	var body_h := height * 0.7
	var body := NinePatchRect.new()
	body.texture = tex("bottombar/bar_body")
	body.patch_margin_left = 40
	body.patch_margin_right = 40
	body.patch_margin_top = 40
	body.patch_margin_bottom = 40
	body.position = Vector2(cap_w * 0.8, height - body_h - 4)
	body.size = Vector2(width - cap_w * 0.8 * 2, body_h)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var left := TextureRect.new()
	left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left.texture = tex("bottombar/bar_body_portrait")
	left.custom_minimum_size = Vector2(cap_w, height)
	left.size = Vector2(cap_w, height)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.z_index = 1
	root.add_child(left)
	var right := TextureRect.new()
	right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	right.texture = tex("bottombar/bar_body_buttongroup")
	right.custom_minimum_size = Vector2(cap_w, height)
	right.size = Vector2(cap_w, height)
	right.position = Vector2(width - cap_w, 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.z_index = 1
	root.add_child(right)
	return {"root": root, "body": body, "cap_w": cap_w, "k": k,
		"portrait_at": Vector2(297.0, 160.0) * k, "portrait_d": 226.0 * k, "small_left": Vector2(58.0, 160.0) * k, "small_right": Vector2(width - cap_w + 396.0 * k, 160.0 * k), "small_d": 112.0 * k,
		"orb_at": Vector2(width - cap_w + 155.0 * k, 160.0 * k), "orb_d": 226.0 * k}
