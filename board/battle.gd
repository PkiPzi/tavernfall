extends Node3D
# The 3D tabletop. It never decides rules: it calls rules/combat.gd and then
# plays back the events that came out, one after another.
#
# Test hooks (environment): TAVERN_SEED, TAVERN_AUTOPLAY=1 (AI plays the party too),
# TAVERN_SHOT=file.png with TAVERN_SHOT_AT=seconds (save a screenshot and quit),
# TAVERN_CLICKS="m 4,3;m foe;a foe" (on the player's turns, click those squares with real mouse-button events:
# m = move there, a = attack there with the first weapon, "foe" = the nearest foe, "e now" = end the turn, "p 7,3" = put the nearest foe there; prints the outcome),
# TAVERN_ZOOM=5 (camera distance), TAVERN_FX=1 (fire one spell effect at the first foe after 3 s), TAVERN_OVERLAY=sheet|bag|levelup|cond (open it after 4 s),
# TAVERN_ENC="forest:ogre=1,goblin=2" and TAVERN_PARTY="barbarian,monk@5" (pick the place, foes and heroes).

const Dice = preload("res://rules/dice.gd")
const Srd = preload("res://rules/srd.gd")
const Creature = preload("res://rules/creature.gd")
const Combat = preload("res://rules/combat.gd")
const AI = preload("res://rules/ai.gd")
const Scenery = preload("res://board/scenery.gd")
const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")
const DiceRoll = preload("res://ui/diceroll.gd")
const Sheet = preload("res://ui/sheet.gd")
const Inventory = preload("res://ui/inventory.gd")
const LevelUp = preload("res://ui/levelup.gd")
const Pause = preload("res://ui/pause.gd")

const W := Scenery.W
const H := Scenery.H
const TYPE_COLOR = {"fire": Color("ff7a1a"), "radiant": Color("ffe9a0"), "force": Color("b48cff"),
	"cold": Color("8fd8ff"), "lightning": Color("9db8ff"), "poison": Color("7ec850"),
	"necrotic": Color("7a5c99"), "acid": Color("b6e04a"), "thunder": Color("cfd8e8"), "heal": Color("6dffa0")}

var srd
var dice
var cb
var minis := {}   # creature name -> {node, c, info, ap}
var walls := {}   # cells nobody can enter
var rough := {}   # cells that cost double
var torches := []
var hover_key = null
var lit := []
var astar := AStarGrid2D.new()
var shown := 0
var busy := true
var mode := "move"  # move, attack, cast
var pick = 0        # weapon number or spell id for the current mode
var menu := "main"
var path := []
var autoplay := OS.get_environment("TAVERN_AUTOPLAY") != ""
var clicks: Array = Array(OS.get_environment("TAVERN_CLICKS").split(";", false))
var fake_mouse = null  # test hook: stands in for the pointer position

var pivot: Node3D
var cam: Camera3D
var yaw := 0.5
var pitch := -0.8
var zoom := 17.0
var zoom_to := 17.0   # where the wheel wants the camera; zoom eases toward it
const ZOOM_MIN := 3.2
const ZOOM_MAX := 52.0
var ring: MeshInstance3D
var strip: HBoxContainer
var party_col: VBoxContainer
var hb: Dictionary          # the hotbar frame (see Hud.hotbar_frame)
var hb_root: Control
var hb_face: Control        # the acting hero's portrait in the left ring
var hb_slots: GridContainer
var hb_tabs: HBoxContainer
var hb_info: HBoxContainer  # name, hit points, action pips, movement above the hotbar
var pending := []           # slot entries collected while _update_bar runs
var ui_layer: CanvasLayer
var hurt_on := false
var hurt: TextureRect   # red edges that breathe when the acting hero is badly hurt
var hint: Label
var target_panel: PanelContainer   # the creature under the pointer: portrait, hit points, armour, conditions
var target_key = null
var hit_tag: PanelContainer   # follows the pointer over a foe: chance to hit
var hit_label: Label
var logbox: RichTextLabel
var banner: Label
var hi_mat := mat(Color("ffd866"), 1.0, 0.45)
var bad_mat := mat(Color("ff4a3a"), 1.2, 0.5)

func _ready() -> void:
	srd = Game.srd
	var s := OS.get_environment("TAVERN_SEED")
	dice = Dice.new(int(s) if s != "" else null)
	var enc: Dictionary = Game.encounter if Game.encounter != null else {"template": "dungeon", "monsters": [{"index": "skeleton", "count": 3}]}
	var test := OS.get_environment("TAVERN_ENC")  # test hook: "forest:ogre=1,goblin=2"
	if test != "":
		enc = {"template": test.get_slice(":", 0), "monsters": Array(test.get_slice(":", 1).split(",")).map(
			func(m): return {"index": m.get_slice("=", 0), "count": int(m.get_slice("=", 1))})}
	_build_world(enc.get("template", "dungeon"))
	_build_ui()
	if OS.get_environment("TAVERN_FX") != "":
		_fx_test()
	if OS.get_environment("TAVERN_OVERLAY") != "":  # screenshots: open "sheet", "bag" or "levelup" for the acting hero after 4 s
		get_tree().create_timer(4.0).timeout.connect(_overlay_test)
	var home: float = float(OS.get_environment("TAVERN_ZOOM")) if OS.get_environment("TAVERN_ZOOM") != "" else zoom  # (TAVERN_ZOOM: a closer camera for screenshots)
	# the camera settles in from high above, like the game's arrival
	zoom = home * 1.9
	zoom_to = zoom
	create_tween().tween_property(self, "zoom_to", home, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if OS.get_environment("TAVERN_ZOOM") != "":  # screenshots: look at the first hero from that close
		get_tree().create_timer(6.0).timeout.connect(func(): pivot.position = world(cb.order.filter(func(o): return o.is_pc)[0].pos))
	var all := []
	var heroes: Array = Game.party if not Game.party.is_empty() else Game.demo_party()
	test = OS.get_environment("TAVERN_PARTY")  # test hook: "barbarian,monk@5" = classes, all at level 5
	if test != "":
		heroes = []
		for cls in test.get_slice("@", 0).split(","):
			var h = Game.make_hero(cls.capitalize(), "human", cls)
			h.gain_xp(srd, h.XP_FOR_LEVEL[int(test.get_slice("@", 1))])
			Game.learn(h)
			h.refill()
			heroes.append(h)
	heroes = heroes.filter(func(p): return not p.dead)
	for i in heroes.size():
		heroes[i].side = "party"
		heroes[i].pos = Vector2i(2, 1 + i * 2 + (4 - heroes.size()))
		all.append(heroes[i])
	var n := 0
	for m in enc.monsters:
		for k in int(m.count):
			var label: String = srd.t.monsters[m.index].name
			var mon = Creature.make_monster(srd, m.index, "%s %d" % [label, k + 1] if int(m.count) > 1 else label)
			mon.pos = Vector2i(W - 3 + (n / 4), 1 + (n % 4) * 2 + (n / 4))
			n += 1
			all.append(mon)
	for c in all:
		_add_mini(c)
	cb = Combat.new(dice, srd)
	cb.blocked = walls
	cb.difficult = rough
	cb.start(all)
	Game.music("battle")
	Game.sound("UI_Gameplay_Combat_Start", "power_up_1")
	_play()

# ---- world ------------------------------------------------------------------

static func mat(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	return Scenery.mat(color, glow, alpha)

func world(cell: Vector2i) -> Vector3:
	return Scenery.world(cell)

func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	return Scenery.box(self, size, pos, m)

func _build_world(template: String) -> void:
	var made := Scenery.build(self, template, dice.rng)
	walls = made.walls
	rough = made.rough
	torches = made.torches
	Game.ambience_for(template, made.get("mood", ""))
	Scenery.character_lights(self)

	pivot = Node3D.new()
	pivot.position = Vector3(W * Scenery.CELL / 2.0, 0, H * Scenery.CELL / 2.0)
	add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 50
	pivot.add_child(cam)

	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.44
	tm.outer_radius = 0.52
	ring.mesh = tm
	ring.material_override = mat(Color("ffd866"), 2.5)
	ring.scale = Vector3(Scenery.CELL, 0.25, Scenery.CELL)
	var pulse := create_tween().set_loops()  # a slow breath, so the acting hero is easy to find
	pulse.tween_property(ring, "scale", Vector3(Scenery.CELL * 1.1, 0.25, Scenery.CELL * 1.1), 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(ring, "scale", Vector3(Scenery.CELL, 0.25, Scenery.CELL), 0.9).set_trans(Tween.TRANS_SINE)
	add_child(ring)


	astar.region = Rect2i(0, 0, W, H)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.update()

func _add_mini(c) -> void:
	minis[c.name] = Scenery.character(self, c, minis.size())

# Play an animation once, then go back to standing.
func _anim(who: String, anim: String, then := "Idle") -> void:
	var ap: AnimationPlayer = minis[who].ap
	if ap.has_animation(anim):
		ap.play(anim, 0.15)
		if then != "":
			ap.queue(then)

func _face(who: String, at: Vector3) -> void:
	var n: Node3D = minis[who].node
	var d := at - n.position
	if d.length() > 0.01:
		n.rotation.y = atan2(d.x, d.z)

func _process(dt: float) -> void:
	var pan := Vector2(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO and pivot != null:  # slide the view over the field, relative to how the camera is turned
		var move := Vector3(pan.x, 0, pan.y).rotated(Vector3.UP, yaw) * dt * (6.0 + zoom * 0.35)
		pivot.position.x = clampf(pivot.position.x + move.x, 0.0, W * Scenery.CELL)
		pivot.position.z = clampf(pivot.position.z + move.z, 0.0, H * Scenery.CELL)
	if hurt != null:
		hurt.modulate.a = (0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.005)) if hurt_on else lerpf(hurt.modulate.a, 0.0, 0.1)
	if hit_tag != null and hit_tag.visible:
		hit_tag.position = get_viewport().get_mouse_position() + Vector2(22, 14)
	var keys := int(Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD)) - int(Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT))
	if keys != 0:
		zoom_to = clampf(zoom_to * pow(0.4, dt * keys), ZOOM_MIN, ZOOM_MAX)
	var tilt := int(Input.is_key_pressed(KEY_R)) - int(Input.is_key_pressed(KEY_F))
	if tilt != 0:  # R raises the camera toward a top-down view, F lowers it toward the characters' eye level
		pitch = clampf(pitch - tilt * dt * 0.9, -1.45, -0.18)
	zoom = lerpf(zoom, zoom_to, 1.0 - exp(-12.0 * dt))
	pivot.rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, zoom)
	Scenery.flicker(torches)
	if not busy and cb.winner() == "":
		_hover()

func _refresh() -> void:
	for m in minis.values():
		var c = m.c
		var conds: Array = c.conditions.map(func(x): return x.id)
		var shown: Array = conds.slice(0, 2)  # the full list is in the target panel and the party card icons
		var more := " +%d" % (conds.size() - 2) if conds.size() > 2 else ""
		m.info.text = "%s  %d/%d%s" % [c.name, c.hp, c.max_hp, ("\n" + ", ".join(shown) + more) if not conds.is_empty() else ""]
		m.info.modulate = Color("8fd0ff") if c.side == "party" else Color("ff9a8a")
		m.info.visible = not c.dead
	for x in W:
		for y in H:
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, cb.blocked.has(cell) or cb.at(cell) != null)
	for box in [strip, party_col]:
		for child in box.get_children():
			child.queue_free()
	for c in cb.order:  # initiative order across the top, the one acting is larger
		if not c.dead:
			var card := Hud.turn_card(c, c == cb.current())
			card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			strip.add_child(card)
	for c in cb.all:
		if c.is_pc:
			party_col.add_child(_party_card(c))

# A party member on the left: ringed portrait, health, name. The acting one is lit.
func _party_card(c) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var now: bool = c == cb.current()
	var face := Hud.round_portrait(c, 66.0, "combatants/btn_small_round_h" if now else "combatants/btn_small_round_d",
		Color.WHITE if not c.dead else Color(0.5, 0.5, 0.5))
	face.tooltip_text = Ui.sheet(c) + "\n(click for the full sheet)"
	face.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: Sheet.open(ui_layer, c))
	if c.dead or c.hp == 0:
		face.modulate = Color(0.5, 0.45, 0.45)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(face)
	var hp := Hud.hp_bar(c, 56.0, 5.0)
	hp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(hp)
	var l := Ui.label(c.name, 12, Ui.GOLD if now else Ui.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if not c.conditions.is_empty():
		var cr := Hud.cond_row(c, 18.0)
		cr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(cr)
	return v

# ---- interface --------------------------------------------------------------
# Laid out like Baldur's Gate 3: turn order on top, the party down the left, the acting hero
# in the ring of a long hotbar at the bottom with the End Turn orb at its right end, a small log.

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
	add_child(layer)
	Ui.vignette(layer, 0.55)  # dark corners pull the eye to the middle of the board, like the game's frame
	strip = HBoxContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.offset_top = 8
	strip.add_theme_constant_override("separation", 5)
	layer.add_child(strip)

	party_col = VBoxContainer.new()
	party_col.position = Vector2(14, 110)
	party_col.add_theme_constant_override("separation", 10)
	layer.add_child(party_col)

	hb = Hud.hotbar_frame(940.0, 136.0)
	hb_root = hb.root
	hb_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hb_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hb_root.offset_bottom = -6
	layer.add_child(hb_root)
	hb_face = Control.new()
	hb_root.add_child(hb_face)
	hb_face.z_index = 0
	var margin := MarginContainer.new()  # the slots sit inside the body of the bar
	margin.position = hb.body.position + Vector2(hb.cap_w * 0.2 + 6, 12)
	margin.size = hb.body.size - Vector2(hb.cap_w * 0.4 + 12, 24)
	hb_root.add_child(margin)
	hb_slots = GridContainer.new()
	hb_slots.columns = 12
	hb_slots.add_theme_constant_override("h_separation", 4)
	hb_slots.add_theme_constant_override("v_separation", 4)
	margin.add_child(hb_slots)
	var orb := Hud.end_turn_orb(func(): _do(cb.end_turn()), hb.orb_d)
	orb.position = hb.orb_at - Vector2(hb.orb_d, hb.orb_d) / 2.0
	orb.z_index = 2
	hb_root.add_child(orb)
	hb_info = HBoxContainer.new()  # name, health, pips and movement above the bar, on a dark pill so it reads over any ground
	hb_info.add_theme_constant_override("separation", 10)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", Ui.flat(Color(0.05, 0.04, 0.03, 0.72), Color(0.5, 0.4, 0.2, 0.6), 1, 14, 5))
	pill.position = Vector2(hb.cap_w * 0.92, -42)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(hb_info)
	hb_root.add_child(pill)
	hb_tabs = HBoxContainer.new()
	hb_tabs.position = Vector2(hb.cap_w * 0.95, 2)
	hb_tabs.z_index = 3
	hb_root.add_child(hb_tabs)
	hint = Ui.label("", 15, Ui.INK)
	hint.position = Vector2(hb.cap_w * 0.8, -62)
	hint.size = Vector2(hb.body.size.x, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long hint wraps inside its pill instead of running off the edge
	hint.add_theme_stylebox_override("normal", Ui.flat(Color(0.04, 0.03, 0.025, 0.62), Color(0.5, 0.4, 0.2, 0.0), 0, 12, 5))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb_root.add_child(hint)

	var side := Ui.panel(0.55)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -300
	side.offset_top = -210
	side.offset_bottom = -8
	side.offset_right = -8
	layer.add_child(side)
	logbox = RichTextLabel.new()
	logbox.bbcode_enabled = true
	logbox.scroll_following = true
	logbox.add_theme_font_size_override("normal_font_size", 13)
	side.add_child(logbox)

	target_panel = Ui.panel(0.9)
	target_panel.anchor_left = 1.0
	target_panel.anchor_right = 1.0
	target_panel.offset_left = -270
	target_panel.offset_right = -12
	target_panel.offset_top = 14
	target_panel.visible = false
	layer.add_child(target_panel)

	hurt = TextureRect.new()
	var hg := Gradient.new()
	hg.colors = PackedColorArray([Color(0.6, 0.02, 0.02, 0.0), Color(0.6, 0.02, 0.02, 0.0), Color(0.7, 0.03, 0.03, 0.55)])
	hg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var hgt := GradientTexture2D.new()
	hgt.gradient = hg
	hgt.fill = GradientTexture2D.FILL_RADIAL
	hgt.fill_from = Vector2(0.5, 0.5)
	hgt.fill_to = Vector2(1.0, 1.0)
	hurt.texture = hgt
	hurt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hurt.modulate.a = 0.0
	layer.add_child(hurt)
	layer.move_child(hurt, 0)

	hit_tag = Ui.panel(0.92)
	hit_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_tag.visible = false
	hit_tag.z_index = 20
	hit_label = Ui.label("", 22, Ui.INK)
	hit_label.add_theme_font_override("font", Ui.font(Ui.TITLE_FONT, 700))
	hit_tag.add_child(hit_label)
	layer.add_child(hit_tag)

	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_font_size_override("font_size", 56)
	banner.add_theme_color_override("font_color", Ui.GOLD)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 12)
	banner.visible = false
	layer.add_child(banner)

# Adds one square to the hotbar. spell picks the spell icon set; tip is the hover text.
func _button(text: String, on: Callable, enabled := true, lit := false, spell := false, tip := "", count := "") -> void:
	pending.append({"icon": Hud.icon_for(text, spell), "tip": tip if tip != "" else text, "on": on, "enabled": enabled, "lit": lit, "count": count})

var aims := []   # Magic Missile and Scorching Ray: the creature each dart or ray is aimed at so far

func _set_mode(m: String, p = 0) -> void:
	aims = []
	mode = m
	pick = p
	_update_bar()

# Runs a rules call; shows the refusal reason or plays what happened.
func _do(result: Dictionary) -> void:
	mode = "move"
	menu = "main"
	if not result.ok:
		_update_bar()
		hint.text = "Cannot do that: " + result.error
		return
	_play()

func _weapon_tip(a: Dictionary) -> String:
	var dmg: Array = a.damage.map(func(d): return "%s %s" % [d.dice, d.type])
	return "%s\n%+d to hit   %s   %s" % [a.name, a.bonus, ", ".join(dmg), "range %d ft" % a.range if a.ranged else "melee"]

func _spell_tip(d: Dictionary) -> String:
	var desc: String = d.desc[0] if d.get("desc") is Array and not d.desc.is_empty() else ""
	return "%s   (level %d)\n%s   %s\n%s" % [d.name, d.level, d.casting_time, d.range, desc.substr(0, 220)]

func _tab(text: String, key: String) -> void:
	var b := Ui.text_button(text, func(): menu = key; mode = "move"; _update_bar(), 15)
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.custom_minimum_size.x = 90
	b.add_theme_color_override("font_color", Ui.GOLD if menu == key else Color("cfc3a8"))
	b.add_theme_color_override("font_hover_color", Ui.GOLD)
	b.add_theme_color_override("font_outline_color", Color.BLACK)  # reads over any ground
	b.add_theme_constant_override("outline_size", 6)
	hb_tabs.add_child(b)

func _update_bar() -> void:
	for box in [hb_slots, hb_tabs, hb_info, hb_face]:
		for child in box.get_children():
			child.queue_free()
	pending = []
	_clear_lit()
	if busy or cb.winner() != "":
		hint.text = ""
		return
	var c = cb.current()
	hurt_on = c.hp * 4 <= c.max_hp
	var d: float = hb.portrait_d
	var face := Hud.round_portrait(c, d * 1.05, "combatants/btn_small_round_d", Color(1, 1, 1, 0))
	face.position = hb.portrait_at - face.custom_minimum_size / 2.0
	face.z_index = -1  # under the ring of the end cap
	hb_face.add_child(face)
	var emblem := TextureRect.new()
	emblem.texture = Ui.icon(Ui.CLASS_ICON.get(c.cls, "death-skull"))
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(hb.small_d * 0.62, hb.small_d * 0.62)
	emblem.size = emblem.custom_minimum_size
	emblem.position = hb.small_left - emblem.size / 2.0
	emblem.modulate = Ui.GOLD
	emblem.z_index = 3  # above the end cap art
	hb_face.add_child(emblem)
	var rd := Ui.title(str(cb.round_no), 20)
	rd.position = hb.small_right - Vector2(8, 14)
	rd.z_index = 3
	hb_face.add_child(rd)
	hb_info.add_child(Ui.title(c.name, 17))
	var hpb := Hud.hp_bar(c, 110.0, 8.0)
	hpb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb_info.add_child(hpb)
	hb_info.add_child(Ui.label("%d/%d   AC %d" % [c.hp, c.max_hp, c.ac], 13))
	hb_info.add_child(Hud.pip(Hud.ACTION_GREEN, c.actions > 0))
	hb_info.add_child(Hud.pip(Hud.BONUS_ORANGE, c.bonus, true))
	for k in c.slots_max:
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 2)
		pips.add_child(Ui.label("L%d" % k, 12, Hud.SLOT_PURPLE))
		for i in c.slots_max[k]:
			var sq := ColorRect.new()
			sq.custom_minimum_size = Vector2(9, 9)
			sq.color = Hud.SLOT_PURPLE if i < c.slots.get(k, 0) else Color("2a2234")
			var holder := Control.new()
			holder.custom_minimum_size = Vector2(9, 22)
			sq.position = Vector2(0, 7)
			holder.add_child(sq)
			pips.add_child(holder)
		hb_info.add_child(pips)
	hb_info.add_child(Hud.move_bar(c.move_left, c.speed))
	hint.text = ""
	if not c.spells.is_empty():
		_tab("Actions", "main")
		_tab("Spells", "spells")
	if menu == "spells" and c.spells.is_empty():
		menu = "main"
	if menu == "spells":
		for sp in c.spells:
			var sd: Dictionary = srd.t.spells[sp]
			var is_bonus: bool = sd.casting_time == "1 bonus action"
			var has_slot: bool = sd.level == 0 or c.slots.keys().any(func(k): return k >= sd.level and c.slots[k] > 0)
			_button(sd.name + (" (bonus)" if is_bonus else ""), _set_mode.bind("cast", sp),
				cb.castable(sp) and has_slot and (c.bonus if is_bonus else c.actions > 0), mode == "cast" and pick == sp, true, _spell_tip(sd),
				"" if sd.level == 0 else str(int(sd.level)))
		_layout_slots()
		_hint_text(c)
		return
	var act: bool = c.actions > 0
	_button("Move", _set_mode.bind("move"), c.move_left >= 5, mode == "move", false, "Move\nClick a square. %d ft left." % c.move_left)
	for i in c.attacks.size():  # a second swing from Extra Attack stays lit after the action is spent
		_button(c.attacks[i].name + (" x2" if c.multi > 1 else ""), _set_mode.bind("attack", i), act or c.attacks_left > 0,
			mode == "attack" and pick == i, false, _weapon_tip(c.attacks[i]))
	_button("Dash", func(): _do(cb.dash(c)), act, false, false, "Dash\nDouble your movement this turn.")
	_button("Dodge", func(): _do(cb.dodge(c)), act, false, false, "Dodge\nAttacks against you have disadvantage until your next turn.")
	_button("Disengage", func(): _do(cb.disengage(c)), act, false, false, "Disengage\nYour movement provokes no opportunity attacks.")
	_button("Help", _set_mode.bind("act", "help"), act, mode == "act" and pick == "help", false, "Help\nGive an ally advantage on their next attack.")
	_button("Hide", func(): _do(cb.hide(c)), act, false, false, "Hide\nStealth against the foes' passive Perception. Your next attack has advantage.")
	_button("Shove", _set_mode.bind("act", "shove"), act, mode == "act" and pick == "shove", false, "Shove\nAthletics against a foe next to you: knock it prone.")
	if cb.offhand_index(c) >= 0:
		_button("Off-hand (bonus)", _set_mode.bind("act", "offhand"), c.bonus, mode == "act" and pick == "offhand", false,
			"Two-weapon fighting\nBonus action: strike with your second light weapon (no ability bonus to damage).")
	if "cunning-action" in c.features:
		_button("Hide (bonus)", func(): _do(cb.hide(c, true)), c.bonus, false, false, "Cunning Action: Hide\nBonus action.")
		_button("Dash (bonus)", func(): _do(cb.dash(c, true)), c.bonus)
		_button("Disengage (bonus)", func(): _do(cb.disengage(c, true)), c.bonus)
	if c.res_max.has("second_wind"):
		_button("Second Wind", func(): _do(cb.second_wind(c)), c.bonus and c.res.second_wind > 0, false, false, "Second Wind\nBonus action: heal 1d10 + level.")
	if c.res_max.has("action_surge"):
		_button("Action Surge", func(): _do(cb.action_surge(c)), c.res.action_surge > 0, false, false, "Action Surge\nTake one more action this turn.", str(c.res.action_surge))
	if c.res_max.has("rage"):
		_button("Rage", func(): _do(cb.rage(c)), c.bonus and c.res.get("rage", 0) > 0 and not c.has("raging"), c.has("raging"),
			false, "Rage\nBonus action: advantage on Strength checks and saves, bonus damage, resistance to weapon damage.", str(c.res.get("rage", 0)))
	if "reckless-attack" in c.features:
		_button("Reckless", func(): _do(cb.reckless(c)), not c.reckless, c.reckless, false, "Reckless Attack\nAdvantage on your attacks, enemies get advantage on you.")
	if "divine-smite" in c.features:
		_button("Smite", func(): c.smite = not c.smite; _update_bar(), true, c.smite, false, "Divine Smite\nSpend a spell slot on a hit for radiant damage. %s" % ("On" if c.smite else "Off"))
	if c.res_max.has("lay_on_hands"):
		_button("Lay on Hands", _set_mode.bind("act", "lay"), act and c.res.get("lay_on_hands", 0) > 0, mode == "act" and pick == "lay",
			false, "Lay on Hands\nTouch an ally to restore hit points from your pool.", str(c.res.get("lay_on_hands", 0)))
	if c.cls == "cleric" and c.res_max.has("channel_divinity"):
		_button("Turn Undead", func(): _do(cb.turn_undead(c)), act and c.res.get("channel_divinity", 0) > 0, false, true, "Turn Undead\nUndead within 30 ft must save or flee.")
	if "martial-arts" in c.features:
		_button("Unarmed (bonus)", _set_mode.bind("act", "strike"), c.bonus, mode == "act" and pick == "strike", false, "Unarmed Strike\nBonus action martial arts attack.")
		if c.res_max.has("ki"):
			_button("Flurry", _set_mode.bind("act", "flurry"), c.bonus and c.res.get("ki", 0) > 0, mode == "act" and pick == "flurry",
				false, "Flurry of Blows\nSpend 1 ki: two unarmed strikes.", str(c.res.get("ki", 0)))
	if c.items.get("potion-of-healing", 0) > 0:
		_button("Potion of Healing", func(): _do(cb.use_item(c, "potion-of-healing")), act, false, false,
			"Potion of Healing\nDrink it: regain 2d4 + 2 hit points.", str(c.items.get("potion-of-healing", 0)))
	_layout_slots()
	_hint_text(c)

func _layout_slots() -> void:
	for e in pending:
		hb_slots.add_child(Hud.slot(e))

func _hint_text(c) -> void:
	match mode:
		"attack":
			hint.text = "Click a target for %s" % c.attacks[pick].name
		"cast":
			hint.text = "Click a target for %s" % srd.t.spells[pick].name
		"act":
			hint.text = "Click %s" % {"lay": "an ally next to you to heal", "strike": "a foe next to you", "flurry": "a foe next to you"}[pick]
		_:
			hint.text = "Click a square to move.   WASD pan, Q/E turn, wheel or +/- zoom, R/F tilt, Space recentre, C sheet, I bag."

# ---- mouse ------------------------------------------------------------------

func _cell_under_mouse() -> Vector2i:
	var mp: Vector2 = fake_mouse if fake_mouse != null else get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var hit = null
	var y := 0.0
	for i in 3:  # hills: meet the ground plane, read the height there, meet the plane at that height, twice
		hit = Plane(Vector3.UP, y).intersects_ray(o, d)
		if hit == null:
			break
		y = Scenery.height_at(hit.x, hit.z)
	return Scenery.cell_of(hit) if hit != null else Vector2i(-9, -9)

func _clear_lit() -> void:
	for q in lit:
		q.queue_free()
	lit = []
	hover_key = null

func _light(cell: Vector2i, m: Material) -> void:
	if astar.is_in_boundsv(cell) and not walls.has(cell):
		lit.append(_box(Vector3(0.92 * Scenery.CELL, 0.02, 0.92 * Scenery.CELL), world(cell) + Vector3(0, Scenery.lift(), 0), m))

# A glowing ring on the ground round a creature or square: the target marker.
func _ring_at(cell: Vector2i, color: Color, radius := 0.62, thick := 0.05) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * Scenery.CELL * 0.5 - thick
	tm.outer_radius = radius * Scenery.CELL * 0.5
	mi.mesh = tm
	mi.material_override = mat(color, 2.2)
	mi.scale.y = 0.2
	mi.position = world(cell) + Vector3(0, Scenery.lift() + 0.01, 0)
	add_child(mi)
	lit.append(mi)

# Footstep dots along the planned path and a distance tag at its end, like the game's movement preview.
func _path_marks(steps: Array, cost_ft: int) -> void:
	var from: Vector3 = world(cb.current().pos)
	for i in steps.size():
		var cell: Vector2i = steps[i]
		var last: bool = i == steps.size() - 1
		var dot := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2 if last else 0.11
		cm.bottom_radius = cm.top_radius
		cm.height = 0.02
		dot.mesh = cm
		dot.material_override = mat(Color("ffd866"), 2.5)
		dot.position = world(cell) + Vector3(0, Scenery.lift(), 0)
		add_child(dot)
		lit.append(dot)
		var prev: Vector3 = from if i == 0 else world(steps[i - 1])
		if not last:  # a second dot between squares so the line reads as a path
			var mid := dot.duplicate()
			mid.position = (world(cell) + prev * 0.0 + world(steps[i + 1])) / 2.0 + Vector3(0, Scenery.lift(), 0)
			add_child(mid)
			lit.append(mid)
	if not steps.is_empty():
		var tag := Label3D.new()
		tag.text = "%d ft" % cost_ft
		tag.font = Ui.font(Ui.TITLE_FONT, 700, 1)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font_size = 56
		tag.pixel_size = 0.006
		tag.outline_size = 16
		tag.modulate = Color("ffe9a6")
		tag.position = world(steps[-1]) + Vector3(0, 0.9, 0)
		add_child(tag)
		lit.append(tag)

# The cheapest walk to a square within `want` squares of t: {"path": [...], "cost": feet}; empty path = no way there.
func _approach(c, t, want: int) -> Dictionary:
	var best := []
	var best_cost := 1 << 30
	astar.set_point_solid(c.pos, false)  # the mover stands on a solid square, and no path can start from one
	for dx in range(-want, want + 1):
		for dy in range(-want, want + 1):
			var cell: Vector2i = t.pos + Vector2i(dx, dy)
			if cell == t.pos or not astar.is_in_boundsv(cell) or astar.is_point_solid(cell):
				continue
			var full: Array = astar.get_id_path(c.pos, cell).slice(1)
			if full.is_empty():
				continue
			var cost := 0
			for step in full:
				cost += 10 if cb.difficult.has(step) else 5
			if cost < best_cost:
				best = full
				best_cost = cost
	astar.set_point_solid(c.pos, true)
	return {"path": best, "cost": best_cost}

# Squares a weapon walks up to: melee its reach, a bow its normal range (so it keeps no disadvantage).
func _weapon_want(c, i: int) -> int:
	var w: Dictionary = c.attacks[i]
	return (w.range if w.ranged else w.reach) / 5

# When the click is on a lone target out of reach of what is picked: {"want": squares to walk up to}. Empty when it can act from here.
func _reach(c, ts: Array) -> Dictionary:
	var t = ts[0]
	if ts.size() != 1 or t == c:
		return {}
	var d: int = cb.dist(c.pos, t.pos)
	match mode:
		"attack":
			var w: Dictionary = c.attacks[pick]
			if t.side != c.side and d > (w.long if w.ranged else w.reach):
				return {"want": _weapon_want(c, pick)}
		"act":
			var ft := 30 if pick == "help" else 5
			if d > ft:
				return {"want": ft / 5}
		"cast":
			var sp: Dictionary = srd.t.spells[pick]
			var r: int = cb._spell_range(sp)
			if r >= 0 and not sp.has("area_of_effect") and not pick in cb.VOLLEYS and d > r:
				return {"want": r / 5}
	return {}

# Walks toward t until `want` squares away, when the movement left allows it, then does `then`.
func _approach_then(c, t, want: int, then: Callable) -> void:
	var a := _approach(c, t, want)
	if a.path.is_empty():
		hint.text = "There is no way through to it."
		return
	if a.cost > c.move_left:
		hint.text = "Out of range: it is %d ft of walking away and you have %d ft of movement left." % [a.cost, c.move_left]
		return
	var r: Dictionary = cb.move(c, a.path)
	if not r.ok:
		hint.text = "Cannot do that: " + r.error
		return
	await _play()  # the pick (mode, pick) stays as it was, so `then` still knows what to do
	if cb.winner() == "" and cb.current() == c and cb.active(c):
		then.call()

func _hover() -> void:
	var c = cb.current()
	var cell := _cell_under_mouse()
	_show_target(cell)
	if hover_key == [cell, mode]:
		return  # nothing changed since the last frame
	hit_tag.visible = false
	_clear_lit()
	hover_key = [cell, mode]
	path = []
	if mode == "move":
		if astar.is_in_boundsv(cell) and not astar.is_point_solid(cell):
			astar.set_point_solid(c.pos, false)  # no path can start from a solid square, and the mover stands on one
			var full: Array = astar.get_id_path(c.pos, cell).slice(1)
			astar.set_point_solid(c.pos, true)
			var cost := 0
			for step in full:  # only as far as the movement allows
				var price: int = 10 if cb.difficult.has(step) else 5
				if cost + price > c.move_left:
					break
				cost += price
				path.append(step)
			_path_marks(path, cost)
		if cb.at(cell) != null and not cb.at(cell).dead:  # pointing at someone: a ring under them
			_ring_at(cell, Color("ff7a6a") if cb.at(cell).side != "party" else Color("7ab4ff"), 0.7, 0.04)
	else:
		for t in _targets(c, cell):
			_ring_at(t.pos, Color("ff4a3a"))
		if lit.is_empty():
			_ring_at(cell, Color("ffd866"), 0.5)
		var foe = cb.at(cell)
		if mode == "attack" and foe != null and foe.side != c.side:
			var h: Dictionary = cb.hit_chance(c, foe, pick)
			var far := ""
			var reachable: bool = h.in_range
			if not h.in_range:
				var a := _approach(c, foe, _weapon_want(c, pick))
				reachable = not a.path.is_empty() and a.cost <= c.move_left
				far = "  walk %d ft, then attack" % a.cost if reachable else "  out of range"
			hit_label.text = "%d%%%s%s" % [h.pct, " ▲" if h.mode > 0 else (" ▼" if h.mode < 0 else ""), far]
			hit_label.add_theme_color_override("font_color", Color("ff6b5a") if not reachable or h.pct < 40 else (Color("ffc24a") if h.pct < 70 else Color("7ddc6a")))
			hit_tag.visible = true

# Fills the target panel for whoever stands on `cell`, or hides it.
func _show_target(cell: Vector2i) -> void:
	var who = cb.at(cell)
	if who == null or who.dead:
		target_panel.visible = false
		target_key = null
		return
	if target_key == who and target_panel.visible:
		return
	target_key = who
	for ch in target_panel.get_children():
		ch.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	target_panel.add_child(row)
	row.add_child(Hud.round_portrait(who, 62.0, "combatants/btn_small_round_d", Color("ff8a78") if who.side != "party" else Color.WHITE))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	col.add_child(Ui.title(who.name, 17, Ui.GOLD if who.side == "party" else Color("ff8a78")))
	var hpb := Hud.hp_bar(who, 150.0, 8.0)
	col.add_child(hpb)
	col.add_child(Ui.label("%d / %d   AC %d" % [who.hp, who.max_hp, cb.ac_of(who)], 14))
	if not who.conditions.is_empty():
		col.add_child(Hud.cond_row(who, 26.0))
	if not who.resist.is_empty():
		col.add_child(Ui.label("Resists " + ", ".join(who.resist), 12, Ui.DIM))
	target_panel.visible = true

# Who a click on `cell` would affect in the current mode.
func _targets(c, cell: Vector2i) -> Array:
	var t = cb.at(cell)
	if mode in ["attack", "act"]:
		return [t] if t != null else []
	var sp: Dictionary = srd.t.spells[pick]
	if pick in ["spirit-guardians", "expeditious-retreat"]:  # these work on the caster alone, wherever you click
		return [c]
	if pick in ["bless", "bane"]:  # up to three allies (Bless) or foes (Bane), the ones nearest the click
		var pool: Array = cb.all.filter(func(o): return (o.side == c.side) == (pick == "bless") and not o.dead and cb.dist(c.pos, o.pos) <= 30)
		pool.sort_custom(func(a, b): return a.pos.distance_squared_to(cell) < b.pos.distance_squared_to(cell))
		return pool.slice(0, 3)
	if not sp.has("area_of_effect"):
		return [t] if t != null else []
	var size := int(sp.area_of_effect.size)
	if sp.range == "Self":  # cone or line from the caster toward the click
		var dir := Vector2(cell - c.pos).normalized()
		return cb.all.filter(func(o): return o != c and not o.dead and cb.dist(c.pos, o.pos) <= size \
			and Vector2(o.pos - c.pos).normalized().dot(dir) > 0.7)
	return cb.all.filter(func(o): return not o.dead and cb.dist(cell, o.pos) <= size)

func _unique(list: Array) -> Array:
	var out := []
	for x in list:
		if not out.has(x):
			out.append(x)
	return out

# The wheel zooms toward the pointer; the combat log keeps its own scrolling. A touchpad pinch zooms too.
func _input(ev: InputEvent) -> void:
	if pivot == null:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var over := get_viewport().gui_get_hovered_control()
		if over != null and (over is RichTextLabel or over is ScrollContainer):
			return
		_zoom_by(0.86 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.86, ev.button_index == MOUSE_BUTTON_WHEEL_UP)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(ev.factor, 0.2), false)

func _zoom_by(factor: float, toward_pointer: bool) -> void:
	if toward_pointer:  # slide the view a little way toward what the pointer is over
		var o := cam.project_ray_origin(get_viewport().get_mouse_position())
		var d := cam.project_ray_normal(get_viewport().get_mouse_position())
		var hit = Plane(Vector3.UP, 0).intersects_ray(o, d)
		if hit != null:
			var t := pivot.position.lerp(hit, 0.18)
			pivot.position = Vector3(clampf(t.x, 0.0, W * Scenery.CELL), pivot.position.y, clampf(t.z, 0.0, H * Scenery.CELL))
	zoom_to = clampf(zoom_to * factor, ZOOM_MIN, ZOOM_MAX)

# Does what the picked action says to the targets the click chose (after any walk up to them).
func _commit(c, ts: Array) -> void:
	if mode == "attack":
		_do(cb.attack(c, ts[0], pick))
	elif mode == "act":
		match pick:
			"lay":
				_do(cb.lay_on_hands(c, ts[0]))
			"help":
				_do(cb.help(c, ts[0]))
			"shove":
				_do(cb.shove(c, ts[0]))
			"offhand":
				_do(cb.offhand(c, ts[0]))
			_:
				_do(cb.bonus_strike(c, ts[0], pick == "flurry"))
	else:
		var lvl := int(srd.t.spells[pick].level)
		var slot := 0
		for k in c.slots:  # shortcut: always the lowest slot that works; add a picker for upcasting
			if k >= lvl and c.slots[k] > 0 and (slot == 0 or k < slot):
				slot = k
		if pick in cb.VOLLEYS:  # one click per dart or ray, each can go to a different foe; Enter sends the rest after the last aim
			aims.append(ts[0])
			var n: int = cb.volley_size(pick, slot)
			if aims.size() < n:
				hint.text = "%s: %d of %d aimed (last at %s). Click the next target, or press Enter to send the rest the same way." % [srd.t.spells[pick].name, aims.size(), n, ts[0].name]
				return
			var shots := aims.duplicate()
			aims = []
			_do(cb.cast(c, pick, _unique(shots), slot, shots))
		else:
			_do(cb.cast(c, pick, ts, slot))

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= ev.relative.x * 0.006
		pitch = clampf(pitch - ev.relative.y * 0.004, -1.45, -0.35)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT and not busy and cb.winner() == "":
			var c = cb.current()
			var cell := _cell_under_mouse()
			if mode == "move":
				if not path.is_empty():
					_do(cb.move(c, path))
			elif mode == "cast" and pick in cb.CELL_SPELLS:  # Misty Step: any free square
				_do(cb.misty_step(c, cell))
			else:
				var ts := _targets(c, cell)
				if ts.is_empty():
					hint.text = "Nobody there."
				else:
					var reach := _reach(c, ts)
					if reach.is_empty():
						_commit(c, ts)
					else:
						_approach_then(c, ts[0], reach.want, func(): _commit(c, ts))
	elif ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ENTER and not aims.is_empty() and cb.current() != null and not busy:  # fire the rest of the volley at the last target
			var c = cb.current()
			var slot := 0
			for k in c.slots:
				if k >= int(srd.t.spells[pick].level) and c.slots[k] > 0 and (slot == 0 or k < slot):
					slot = k
			var shots := aims.duplicate()
			aims = []
			_do(cb.cast(c, pick, _unique(shots), slot, shots))
		elif ev.keycode == KEY_C and cb.current() != null:
			Sheet.open(ui_layer, cb.current())
		elif ev.keycode == KEY_I and cb.current() != null:  # the bag; a potion can be drunk from it on that hero's own turn
			var who = cb.current()
			Inventory.open(ui_layer, who, func(item): if who == cb.current() and who.actions > 0: _do(cb.use_item(who, item)))
		elif ev.keycode == KEY_ESCAPE:
			Pause.open(ui_layer, func(): Game.go(Game.MENU, "town"))
		elif ev.keycode == KEY_SPACE and cb.current() != null:  # back to whoever is acting
			create_tween().tween_property(pivot, "position", world(cb.current().pos), 0.4).set_trans(Tween.TRANS_SINE)
		elif ev.keycode == KEY_Q:
			yaw += 0.2
		elif ev.keycode == KEY_E:
			yaw -= 0.2

# ---- playback ---------------------------------------------------------------

func _say(text: String, color := "d8d2c4") -> void:
	logbox.append_text("[color=#%s]%s[/color]\n" % [color, text])

func _wait(t: float) -> void:
	await get_tree().create_timer(t * (0.25 if autoplay else 1.0)).timeout

func _float(who: String, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Ui.font(Ui.TITLE_FONT, 800, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	var big := text.begins_with("CRIT")
	l.font_size = 96 if big else 64
	l.outline_size = 22
	l.outline_modulate = Color(0.05, 0.02, 0.0, 0.95)
	l.modulate = Color("ffd866") if big else color
	l.position = minis[who].node.position + Vector3(randf_range(-0.25, 0.25), 2.3, 0)
	l.scale = Vector3.ONE * 0.4
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * (1.35 if big else 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y + 0.9, 0.85).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.85).set_delay(0.4)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.85).set_delay(0.4)
	tw.tween_callback(l.queue_free)
	if big:
		_shake(0.18)

# A short camera shake for big moments.
func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 5:
		tw.tween_property(cam, "h_offset", randf_range(-amount, amount), 0.035)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-amount, amount), 0.035)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)

func _overlay_test() -> void:
	var c = cb.current()
	if c == null:
		return
	var which := OS.get_environment("TAVERN_OVERLAY")
	if which == "cond":  # put a few conditions on everyone
		for o in cb.all:
			for id in ["blessed", "poisoned", "faerie-fire", "prone"]:
				cb.add_condition(o, id, 3)
		_refresh()
		_update_bar()
	elif which == "bag":
		Inventory.open(ui_layer, c)
	elif which == "pause":
		Pause.open(ui_layer, func(): pass)
	elif which == "levelup":  # a made-up level-up, to look at the screen
		LevelUp.open(ui_layer, [{"c": c, "from": c.level, "to": c.level + 1, "hp": 7, "spells": c.spells.slice(0, 3), "features": c.features.slice(0, 2)}])
	else:
		Sheet.open(ui_layer, c)

func _fx_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var foe: String = cb.all.filter(func(c): return c.side != "party")[0].name
	var me: String = cb.all.filter(func(c): return c.side == "party")[0].name
	_bolt(me, foe, Color("ff7a1a"))

func _roll_die(n: int, title := "", detail := "", outcome := "", good := true) -> void:
	await DiceRoll.play(ui_layer, n, title, detail, outcome, good, 3.0 if autoplay else 1.0)

# A soft round glow, additive and unshaded: the look of the game's spell lights and sparks.
var _glow_tex: GradientTexture2D
func _glow_mat(color: Color) -> StandardMaterial3D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = _glow_tex
	m.disable_receive_shadows = true
	return m

func _particles(at: Vector3, color: Color, amount: int, life: float, speed: Vector2, size: float, gravity := Vector3.ZERO, spread := 180.0, one_shot := true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = at
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = gravity
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.colors = PackedColorArray([color.lightened(0.5), color, Color(color, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _glow_mat(Color.WHITE)
	p.draw_pass_1 = q
	add_child(p)
	p.emitting = true
	return p

# The impact of a blow or spell: a flash of light, a spray of sparks, a ring that spreads over the ground.
func _burst(at: Vector3, color: Color, big := false) -> void:
	var n := 1.6 if big else 1.0
	var p := _particles(at + Vector3(0, 0.7, 0), color, int(48 * n), 0.7, Vector2(1.5, 4.0) * n, 0.22 * n, Vector3(0, -4, 0))
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	var flash := OmniLight3D.new()
	flash.position = at + Vector3(0, 1.0, 0)
	flash.light_color = color
	flash.light_energy = 7.0 * n
	flash.omni_range = 6.0
	add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.45)
	ft.tween_callback(flash.queue_free)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	ring.material_override = mat(color, 3.0, 0.85)
	ring.scale = Vector3(0.3, 0.12, 0.3)
	ring.position = at + Vector3(0, 0.08, 0)
	add_child(ring)
	var rt := create_tween()
	rt.tween_property(ring, "scale", Vector3(2.2 * n, 0.12, 2.2 * n), 0.4).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring, "material_override:albedo_color:a", 0.0, 0.4)
	rt.tween_callback(ring.queue_free)

# A glowing orb with a trail that flies on a short arc from one creature to another.
const IMPACT = {"fire": "Spell_Impact_Damage_Fire_FireBolt", "lightning": "Spell_Impact_Damage_Lightning_ShockingGrasp_L0",
	"radiant": "Spell_Impact_Damage_Radiant_SacredFlame_L1to3", "necrotic": "Spell_Impact_Damage_Necrotic_ChillTouch_L1to3",
	"force": "Spell_Impact_Damage_Force_MagicMissile", "poison": "Spell_Impact_Damage_Poison_PoisonSpray_L0",
	"acid": "Spell_Impact_Damage_Acid_AcidSplash", "psychic": "Spell_Impact_Damage_Psychic_ViciousMockery_L1to3"}

func _bolt(from: String, to: String, color: Color, impact := "") -> void:
	var orb := Node3D.new()
	var start: Vector3 = minis[from].node.position + Vector3(0, 1.2, 0)
	var end: Vector3 = minis[to].node.position + Vector3(0, 1.0, 0)
	orb.position = start
	add_child(orb)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	core.mesh = sm
	core.material_override = mat(color.lightened(0.6), 6.0)
	orb.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 5.0
	orb.add_child(light)
	var trail := _particles(Vector3.ZERO, color, 140, 0.35, Vector2(0.05, 0.3), 0.26, Vector3.ZERO, 180.0, false)
	remove_child(trail)
	orb.add_child(trail)
	var dur := 0.18 + start.distance_to(end) * 0.018
	var tw := create_tween()
	tw.tween_method(func(t: float): orb.position = start.lerp(end, t) + Vector3(0, sin(t * PI) * 0.7, 0), 0.0, 1.0, dur)
	await tw.finished
	trail.emitting = false
	orb.queue_free()
	if impact != "":
		Game.sound(impact, "zap_1")
	else:
		Game.sfx("zap_1")
	_burst(minis[to].node.position, color, true)

func _play() -> void:
	busy = true
	_update_bar()
	while shown < cb.events.size():
		await _show(cb.events[shown])
		shown += 1
		_refresh()
	if cb.winner() != "":
		if cb.events[-1].type != "end":
			cb.end_turn()
			_play()
			return
		banner.text = "Victory!  %d XP each" % cb.events[-1].xp_each if cb.winner() == "party" else "The party has fallen"
		banner.visible = true
		ring.visible = false
		hb_root.visible = false  # nothing to do on the hotbar any more, and End Turn must not be pressed after the last foe is down
		target_panel.visible = false
		Game.sfx("power_up_3" if cb.winner() == "party" else "low_down")
		for m in minis.values():
			if m.c.side == cb.winner() and cb.active(m.c):
				_anim(m.c.name, "Cheer")
		await _wait(1.2)
		Game.battle_result = {"won": cb.winner() == "party", "xp_each": cb.events[-1].xp_each, "rounds": cb.round_no,
			"fallen": cb.all.filter(func(c): return c.is_pc and c.dead).map(func(c): return c.name)}
		if autoplay and Game.story.is_empty():
			return
		_update_bar()
		# the hotbar is empty once the fight is won, so the way on is a real button under the banner
		var go := Ui.button("Continue" if not Game.story.is_empty() else "Fight again", Game.after_battle)
		go.add_theme_font_size_override("font_size", 26)
		go.set_anchors_preset(Control.PRESET_CENTER)
		go.offset_left = -130
		go.offset_right = 130
		go.offset_top = 70
		go.offset_bottom = 130
		banner.get_parent().add_child(go)
		if autoplay:
			Game.after_battle()
		return
	var c = cb.current()
	if c.side != "party" or autoplay:
		await _wait(0.4)
		AI.take_turn(cb, c)
		_play()
		return
	busy = false
	_update_bar()
	_auto_click()

# Test hook: plays the scripted clicks as real mouse-button events through the normal input path.
# The pointer position is fed in directly, because a program cannot move the real pointer on Wayland.
func _auto_click() -> void:
	var todo := clicks
	clicks = []
	if not todo.is_empty():
		await get_tree().create_timer(0.5).timeout  # let the camera settle before projecting squares
	for click in todo:
		while busy:
			await get_tree().process_frame
		var step: PackedStringArray = click.split(" ")
		if step[0] == "p":  # "p 7,3": put the nearest foe on that square (test setup)
			var me = cb.current()
			var foes: Array = cb.all.filter(func(o): return o.side != me.side and not o.dead)
			foes.sort_custom(func(x, y): return cb.dist(me.pos, x.pos) < cb.dist(me.pos, y.pos))
			foes[0].pos = Vector2i(int(step[1].get_slice(",", 0)), int(step[1].get_slice(",", 1)))
			minis[foes[0].name].node.position = world(foes[0].pos)
			_refresh()
			continue
		if step[0] == "e":  # "e now": end the turn and let the foes act
			cb.end_turn()
			_play()
			await get_tree().create_timer(5.0).timeout
			while busy:
				await get_tree().process_frame
			print("END TURN -> now %s, foes at %s" % [cb.current().name, cb.all.filter(func(o): return not o.is_pc).map(func(o): return o.pos)])
			continue
		var cell := Vector2i(int(step[1].get_slice(",", 0)), int(step[1].get_slice(",", 1)))
		if step[1] == "foe":  # the square of the nearest foe, or next to it for a move
			var me = cb.current()
			var foes: Array = cb.all.filter(func(o): return o.side != me.side and not o.dead)
			foes.sort_custom(func(x, y): return cb.dist(me.pos, x.pos) < cb.dist(me.pos, y.pos))
			cell = foes[0].pos + (Vector2i(-1, 0) if step[0] == "m" else Vector2i.ZERO)
		if step[0] == "a":
			_set_mode("attack", 0)
		await get_tree().create_timer(1.0).timeout  # the camera eases toward whoever acts; aim once it has settled
		fake_mouse = cam.unproject_position(world(cell))
		await get_tree().create_timer(0.2).timeout
		var press := InputEventMouseButton.new()
		press.position = fake_mouse
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().create_timer(2.5).timeout
		var c = cb.order.filter(func(o): return o.is_pc)[0]
		print("CLICK %s -> %s at %s, foes hp %s, hint: %s" % [click, c.name, c.pos,
			cb.all.filter(func(o): return not o.is_pc).map(func(o): return o.hp), hint.text])
	if not todo.is_empty() and OS.get_environment("TAVERN_SHOT") == "":  # with a screenshot pending, that quits instead
		get_tree().quit()

func _show(e: Dictionary) -> void:
	match e.type:
		"initiative":
			_say("Initiative: " + ", ".join(e.order), "e8c15a")
		"turn":
			ring.position = world(minis[e.who].c.pos) + Vector3(0, Scenery.lift(), 0)
			var mid := Vector3(W * Scenery.CELL / 2.0, 0, H * Scenery.CELL / 2.0)
			var glide := create_tween()  # the view eases toward whoever acts, without losing the field
			glide.tween_property(pivot, "position", mid.lerp(world(minis[e.who].c.pos), 0.28), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_say("Round %d: %s" % [e.round, e.who], "e8c15a")
		"move":
			var n: Node3D = minis[e.who].node
			_anim(e.who, "Running_A", "")
			for cell in e.path:
				_face(e.who, world(cell))
				var tw := create_tween()
				tw.tween_property(n, "position", world(cell), 0.18 if not autoplay else 0.05)
				Game.sound("Movement_Footstep", "footstep_%d" % (randi() % 5), 0.1, -12.0)
				ring.position = world(cell) + Vector3(0, Scenery.lift(), 0)
				await tw.finished
			_anim(e.who, "Idle", "")
		"opportunity_attack":
			_say("%s gets an opportunity attack on %s" % [e.who, e.target], "ffb060")
		"attack":
			var shot: bool = minis[e.who].c.attacks.any(func(w): return w.name == e.weapon and w.ranged)
			_face(e.who, minis[e.target].node.position)
			_anim(e.who, "2H_Ranged_Shoot" if shot else "1H_Melee_Attack_Chop")
			var bonus: int = e.total - e.roll
			await _roll_die(e.roll, "%s: Attack Roll" % e.weapon, "%d %s %d = %d  vs AC %d" % [e.roll, "+" if bonus >= 0 else "-", absi(bonus), e.total, e.ac],
				("CRITICAL HIT" if e.crit else "HIT") if e.hit else "MISS", e.hit)
			var how: String = " with advantage" if e.mode > 0 else (" with disadvantage" if e.mode < 0 else "")
			if e.get("cover", 0) > 0:
				how += " (%s cover)" % ("half" if e.cover == 2 else "three-quarters")
			var dtype := "Slashing"
			for w in minis[e.who].c.attacks:
				if w.name == e.weapon:
					dtype = str(w.damage[0].type).capitalize()
			if not dtype in ["Slashing", "Piercing", "Bludgeoning"]:
				dtype = "Slashing"
			if e.hit:
				Game.sound("Impact_Blood_Red_%s%s" % [dtype, "_Critical" if e.crit else ""], "chop" if e.crit else "knife_slice")
			else:
				Game.sound("Action_Cast_Slash", "metal_pot_%d" % (1 + randi() % 3))
			if e.hit:
				_burst(minis[e.target].node.position, Color("d83a2a"))
				if e.target_hp > 0:
					_anim(e.target, "Hit_A")
					Game.voice(minis[e.target].c, 0)
				else:
					Game.voice(minis[e.target].c, 1)
				_float(e.target, ("CRIT -%d" if e.crit else "-%d") % e.damage, Color("ff5a4a"))
				_say("%s hits %s with %s%s (%d vs AC %d) for %d%s" % [e.who, e.target, e.weapon, how, e.total, e.ac,
					e.damage, ", sneak attack" if e.has("sneak") else (", divine smite" if e.has("smite") else "")])
			else:
				_float(e.target, "miss", Color("cfcfcf"))
				_say("%s misses %s with %s%s (%d vs AC %d)" % [e.who, e.target, e.weapon, how, e.total, e.ac], "9a948a")
			await _wait(0.3)
		"cast":
			_say("%s casts %s" % [e.who, e.spell], "b48cff")
			_face(e.who, minis[e.results[0].target].node.position if not e.results.is_empty() else minis[e.who].node.position)
			_anim(e.who, "Spellcast_Shoot")
			if e.spell in ["Cure Wounds", "Healing Word"]:
				Game.sound("Spell_Cast_Healing_CureWounds_L1to3", "phaser_up_1")
			else:
				Game.sfx("phaser_up_1")
			await _wait(0.35)
			var sp_type := "force"
			for sp in srd.t.spells.values():
				if sp.name == e.spell and sp.has("damage"):
					sp_type = sp.damage[0].get("damage_type", {}).get("index", "force")
			for r in e.results:
				if r.has("healed"):
					await _bolt(e.who, r.target, TYPE_COLOR.heal, "Items_Inventory_Potion_Heal_Consume")
				else:
					for i in int(r.get("darts", 1)):  # Magic Missile: one bolt per dart
						await _bolt(e.who, r.target, TYPE_COLOR.get(sp_type, Color.WHITE), IMPACT.get(sp_type, ""))
						if i < int(r.get("darts", 1)) - 1:
							await _wait(0.12)
					if r.has("hit"):  # a spell attack (Fire Bolt, each ray of Scorching Ray)
						await _roll_die(r.roll, "%s: Spell attack" % e.who, "%d vs %s" % [r.total, r.target], "CRITICAL HIT" if r.crit else ("HIT" if r.hit else "MISS"), r.hit)
					elif r.has("roll"):
						await _roll_die(r.roll, "%s: Saving Throw" % r.target, "", "SAVED" if r.get("saved", false) else "FAILED", not r.get("saved", false))
					_float(r.target, "-%d" % r.damage if r.damage > 0 else ("miss" if r.get("hit", true) == false else "no effect"), Color("ff5a4a"))
					_say("  %s %s" % [r.target, ("takes %d%s" % [r.damage, " (saved)" if r.get("saved", false) else ""]) if r.get("hit", true) else "is missed"] + (" (%d darts)" % r.darts if r.has("darts") else ""))
			await _wait(0.3)
		"help":
			_say("%s helps %s: advantage on the next attack" % [e.who, e.target], "7ddc6a")
			_float(e.target, "helped", Color("7ddc6a"))
		"hide":
			await _roll_die(e.roll, "%s: Stealth" % e.who, "%d vs the watch's %d" % [e.total, e.dc], "HIDDEN" if e.success else "SPOTTED", e.success)
			_say("%s %s" % [e.who, "slips out of sight" if e.success else "is spotted"], "9a948a")
		"shove":
			await _roll_die(e.roll, "%s shoves %s" % [e.who, e.target], "%d vs %d" % [e.total, e.dc], "KNOCKED DOWN" if e.success else "HELD", e.success)
			_say("%s %s %s" % [e.who, "knocks down" if e.success else "fails to shove", e.target], "ffb060")
			if e.success:
				_anim(e.target, "Hit_A")
		"heal":
			Game.sfx("power_up_1")
			_float(e.who, "+%d" % e.amount, TYPE_COLOR.heal)
			_say("%s recovers %d hit points" % [e.who, e.amount], "6dffa0")
		"save":
			_say("  %s %s save: %d vs DC %d, %s" % [e.who, e.ability.to_upper(), e.total, e.dc,
				"success" if e.success else "fail"], "9a948a")
		"check":
			_say("%s %s check: %d vs DC %d, %s" % [e.who, e.skill if e.skill != "" else e.ability, e.total, e.dc,
				"success" if e.success else "fail"])
		"death_save":
			await _roll_die(e.roll, "%s: Death Saving Throw" % e.who, "", "SUCCESS" if e.roll >= 10 else "FAILURE", e.roll >= 10)
			_say("%s death save: %d (%d good, %d bad)" % [e.who, e.roll, e.successes, e.failures], "ffb060")
		"down":
			Game.sfx("low_down")
			_anim(e.who, "Death_A", "")
			_say("%s falls unconscious!" % e.who, "ff5a4a")
		"dead":
			_anim(e.who, "Death_A", "")
			minis[e.who].node.get_node("disc").visible = false
			_say("%s dies." % e.who, "ff5a4a")
			await _wait(0.2)
		"condition":
			_say("  %s is %s %s" % [e.who, "now" if e.on else "no longer", e.condition], "9a948a")
			if e.condition == "unconscious" and not e.on and not minis[e.who].c.dead:
				_anim(e.who, "Lie_StandUp")
		"teleport":
			Game.sfx("phaser_up_1")
			_burst(minis[e.who].node.position, TYPE_COLOR.force)
			minis[e.who].node.position = world(e.to)
			_burst(world(e.to), TYPE_COLOR.force)
			_say("%s steps through the mist" % e.who, "b48cff")
			await _wait(0.3)
		"aura":
			_say("%s's %s burns %s for %d%s" % [e.who, e.spell, e.target, e.damage, " (saved)" if e.saved else ""], "b48cff")
			_float(e.target, "-%d" % e.damage if e.damage > 0 else "no effect", Color("ffe08a"))
		"stable":
			_say("%s is stabilised" % e.who, "6dffa0")
		"concentration_lost":
			_say("%s loses concentration on %s" % [e.who, e.spell], "ffb060")
		"dodge":
			_anim(e.who, "Block")
			_say("%s dodges" % e.who, "9a948a")
		"item":
			_anim(e.who, "Use_Item")
			_say("%s uses %s" % [e.who, e.item.replace("-", " ")], "9a948a")
		"rage":
			Game.sfx("three_tone_1")
			_float(e.who, "RAGE", Color("ff7a1a"))
			_say("%s flies into a rage!" % e.who, "ff7a1a")
		"turn_undead":
			Game.sfx("phaser_up_1")
			_burst(minis[e.who].node.position, TYPE_COLOR.radiant)
			_say("%s presents a holy symbol. Turned: %s" % [e.who, ", ".join(e.turned) if not e.turned.is_empty() else "nobody"], "ffe9a0")
		"lay_on_hands":
			_say("%s lays hands on %s" % [e.who, e.target], "6dffa0")
		"end":
			pass
		_:
			_say("%s: %s" % [e.who, e.type.replace("_", " ")], "9a948a")
