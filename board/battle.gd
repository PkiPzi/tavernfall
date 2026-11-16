extends Node3D
# The 3D tabletop. It never decides rules: it calls rules/combat.gd and then
# plays back the events that came out, one after another.
#
# Test hooks (environment): TAVERN_SEED, TAVERN_AUTOPLAY=1 (AI plays the party too),
# TAVERN_SHOT=file.png with TAVERN_SHOT_AT=seconds (save a screenshot and quit),
# TAVERN_CLICKS="m 4,3;m foe;a foe" (on the player's turns, click those squares with real mouse-button events:
# m = move there, a = attack there with the first weapon, "foe" = the nearest foe; prints the outcome),
# TAVERN_ENC="forest:ogre=1,goblin=2" and TAVERN_PARTY="barbarian,monk@5" (pick the place, foes and heroes).

const Dice = preload("res://rules/dice.gd")
const Srd = preload("res://rules/srd.gd")
const Creature = preload("res://rules/creature.gd")
const Combat = preload("res://rules/combat.gd")
const AI = preload("res://rules/ai.gd")
const Scenery = preload("res://board/scenery.gd")
const Ui = preload("res://ui/ui.gd")

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
var zoom := 11.5
var ring: MeshInstance3D
var die: MeshInstance3D
var die_label: Label3D
var strip: HBoxContainer
var party_col: VBoxContainer
var me_box: HBoxContainer
var bar: HFlowContainer
var hint: Label
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

	pivot = Node3D.new()
	pivot.position = Vector3(W / 2.0, 0, H / 2.0)
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
	ring.scale.y = 0.25
	add_child(ring)

	# shortcut: the die is a tumbling low-poly ball that shows the result, not a physics die.
	die = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	sm.radial_segments = 5
	sm.rings = 3
	die.mesh = sm
	die.material_override = mat(Color("b8862b"))
	die.position = Vector3(-4.2, -1.3, -6)
	die.visible = false
	cam.add_child(die)
	die_label = Label3D.new()
	die_label.font_size = 64
	die_label.outline_size = 16
	die_label.no_depth_test = true
	die_label.position = die.position + Vector3(0, 0, 0.5)
	die_label.visible = false
	cam.add_child(die_label)

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

func _process(_dt: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, zoom)
	Scenery.flicker(torches)
	if not busy and cb.winner() == "":
		_hover()

func _refresh() -> void:
	for m in minis.values():
		var c = m.c
		var conds: Array = c.conditions.map(func(x): return x.id)
		m.info.text = "%s  %d/%d%s" % [c.name, c.hp, c.max_hp, ("\n" + ", ".join(conds)) if not conds.is_empty() else ""]
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
		if c.dead:
			continue
		var now: bool = c == cb.current()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		v.add_child(Ui.portrait(c, Vector2(62, 74) if now else Vector2(46, 55),
			Ui.GOLD if now else (Color("3f6fb0") if c.side == "party" else Color("a03a2e")), 3 if now else 2))
		v.add_child(Ui.bar(c.hp, c.max_hp, Ui.hp_color(c), 4))
		strip.add_child(v)
	for c in cb.all:
		if c.is_pc:
			party_col.add_child(Ui.hero_card(c, 60))

# ---- interface --------------------------------------------------------------
# Laid out like a party CRPG: turn order on top, the party down the left side,
# the acting hero and the action bar at the bottom, the combat log on the right.

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	strip = HBoxContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.offset_top = 8
	strip.add_theme_constant_override("separation", 6)
	layer.add_child(strip)

	party_col = VBoxContainer.new()
	party_col.position = Vector2(12, 96)
	party_col.add_theme_constant_override("separation", 8)
	layer.add_child(party_col)

	var bottom := Ui.panel(0.9)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -10
	layer.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bottom.add_child(row)
	me_box = HBoxContainer.new()
	me_box.add_theme_constant_override("separation", 10)
	row.add_child(me_box)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	hint = Ui.label("", 14, Ui.DIM)
	col.add_child(hint)
	bar = HFlowContainer.new()
	bar.custom_minimum_size.x = 620
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	col.add_child(bar)

	var side := Ui.panel(0.7)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -300
	side.offset_top = 96
	side.offset_bottom = -150
	side.offset_right = -10
	layer.add_child(side)
	logbox = RichTextLabel.new()
	logbox.bbcode_enabled = true
	logbox.scroll_following = true
	logbox.add_theme_font_size_override("normal_font_size", 13)
	side.add_child(logbox)

	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_font_size_override("font_size", 56)
	banner.add_theme_color_override("font_color", Ui.GOLD)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 12)
	banner.visible = false
	layer.add_child(banner)

func _button(text: String, on: Callable, enabled := true) -> void:
	var b := Ui.button(text, on, enabled)
	b.custom_minimum_size = Vector2(0, 38)
	bar.add_child(b)

func _set_mode(m: String, p = 0) -> void:
	mode = m
	pick = p
	menu = "main"
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

func _update_bar() -> void:
	for box in [bar, me_box]:
		for child in box.get_children():
			child.queue_free()
	_clear_lit()
	if busy or cb.winner() != "":
		hint.text = ""
		return
	var c = cb.current()
	me_box.add_child(Ui.portrait(c, Vector2(84, 100)))
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 150
	stats.add_child(Ui.label(c.name, 18, Ui.GOLD))
	stats.add_child(Ui.bar(c.hp, c.max_hp, Ui.hp_color(c), 8))
	stats.add_child(Ui.label("HP %d/%d    AC %d" % [c.hp, c.max_hp, c.ac], 13))
	stats.add_child(Ui.label("Move %d ft" % c.move_left, 13, Ui.INK if c.move_left >= 5 else Ui.DIM))
	var pips := HBoxContainer.new()
	pips.add_child(Ui.label("Action", 13, Color("7ddc6a") if c.actions > 0 else Color("4a4640")))
	pips.add_child(Ui.label("Bonus", 13, Color("ffa64a") if c.bonus else Color("4a4640")))
	for k in c.slots_max:
		pips.add_child(Ui.label("L%d %d/%d" % [k, c.slots.get(k, 0), c.slots_max[k]], 13, Color("b48cff")))
	stats.add_child(pips)
	me_box.add_child(stats)
	hint.text = ""
	if menu == "spells":
		for sp in c.spells:
			var d: Dictionary = srd.t.spells[sp]
			var is_bonus: bool = d.casting_time == "1 bonus action"
			var has_slot: bool = d.level == 0 or c.slots.keys().any(func(k): return k >= d.level and c.slots[k] > 0)
			_button(d.name + (" (bonus)" if is_bonus else ""), _set_mode.bind("cast", sp),
				cb.castable(sp) and has_slot and (c.bonus if is_bonus else c.actions > 0))
		_button("Back", _set_mode.bind("move"))
		return
	var act: bool = c.actions > 0
	_button("Move", _set_mode.bind("move"), c.move_left >= 5)
	for i in c.attacks.size():  # a second swing from Extra Attack stays lit after the action is spent
		_button(c.attacks[i].name + (" x2" if c.multi > 1 else ""), _set_mode.bind("attack", i), act or c.attacks_left > 0)
	if not c.spells.is_empty():
		_button("Cast", func(): menu = "spells"; _update_bar())
	_button("Dash", func(): _do(cb.dash(c)), act)
	_button("Dodge", func(): _do(cb.dodge(c)), act)
	_button("Disengage", func(): _do(cb.disengage(c)), act)
	if "cunning-action" in c.features:
		_button("Dash (bonus)", func(): _do(cb.dash(c, true)), c.bonus)
		_button("Disengage (bonus)", func(): _do(cb.disengage(c, true)), c.bonus)
	if c.res_max.has("second_wind"):
		_button("Second Wind", func(): _do(cb.second_wind(c)), c.bonus and c.res.second_wind > 0)
	if c.res_max.has("action_surge"):
		_button("Action Surge", func(): _do(cb.action_surge(c)), c.res.action_surge > 0)
	if c.res_max.has("rage"):
		_button("Rage (%d)" % c.res.get("rage", 0), func(): _do(cb.rage(c)), c.bonus and c.res.get("rage", 0) > 0 and not c.has("raging"))
	if "reckless-attack" in c.features:
		_button("Reckless", func(): _do(cb.reckless(c)), not c.reckless)
	if "divine-smite" in c.features:
		_button("Smite: on" if c.smite else "Smite: off", func(): c.smite = not c.smite; _update_bar())
	if c.res_max.has("lay_on_hands"):
		_button("Lay on Hands (%d)" % c.res.get("lay_on_hands", 0), _set_mode.bind("act", "lay"), act and c.res.get("lay_on_hands", 0) > 0)
	if c.cls == "cleric" and c.res_max.has("channel_divinity"):
		_button("Turn Undead", func(): _do(cb.turn_undead(c)), act and c.res.get("channel_divinity", 0) > 0)
	if "martial-arts" in c.features:
		_button("Unarmed (bonus)", _set_mode.bind("act", "strike"), c.bonus)
		if c.res_max.has("ki"):
			_button("Flurry (%d ki)" % c.res.get("ki", 0), _set_mode.bind("act", "flurry"), c.bonus and c.res.get("ki", 0) > 0)
	if c.items.get("potion-of-healing", 0) > 0:
		_button("Potion", func(): _do(cb.use_item(c, "potion-of-healing")), act)
	_button("End Turn", func(): _do(cb.end_turn()))
	match mode:
		"attack":
			hint.text = "Click a target for %s" % c.attacks[pick].name
		"cast":
			hint.text = "Click a target for %s" % srd.t.spells[pick].name
		"act":
			hint.text = "Click %s" % {"lay": "an ally next to you to heal", "strike": "a foe next to you", "flurry": "a foe next to you"}[pick]
		_:
			hint.text = "Click a square to move. Right-drag or Q/E turns the camera, wheel zooms."

# ---- mouse ------------------------------------------------------------------

func _cell_under_mouse() -> Vector2i:
	var mp: Vector2 = fake_mouse if fake_mouse != null else get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 0).intersects_ray(cam.project_ray_origin(mp), cam.project_ray_normal(mp))
	return Vector2i(floori(hit.x), floori(hit.z)) if hit != null else Vector2i(-9, -9)

func _clear_lit() -> void:
	for q in lit:
		q.queue_free()
	lit = []
	hover_key = null

func _light(cell: Vector2i, m: Material) -> void:
	if astar.is_in_boundsv(cell) and not walls.has(cell):
		lit.append(_box(Vector3(0.92, 0.02, 0.92), world(cell) + Vector3(0, 0.05, 0), m))

func _hover() -> void:
	var c = cb.current()
	var cell := _cell_under_mouse()
	if hover_key == [cell, mode]:
		return  # nothing changed since the last frame
	_clear_lit()
	hover_key = [cell, mode]
	path = []
	if mode == "move":
		if astar.is_in_boundsv(cell) and not astar.is_point_solid(cell):
			astar.set_point_solid(c.pos, false)  # no path can start from a solid square, and the mover stands on one
			var full: Array = astar.get_id_path(c.pos, cell).slice(1)
			astar.set_point_solid(c.pos, true)
			var left: int = c.move_left
			for step in full:  # only as far as the movement allows
				left -= 10 if cb.difficult.has(step) else 5
				if left < 0:
					break
				path.append(step)
			for step in path:
				_light(step, hi_mat)
	else:
		for t in _targets(c, cell):
			_light(t.pos, bad_mat)
		if lit.is_empty():
			_light(cell, hi_mat)

# Who a click on `cell` would affect in the current mode.
func _targets(c, cell: Vector2i) -> Array:
	var t = cb.at(cell)
	if mode in ["attack", "act"]:
		return [t] if t != null else []
	var sp: Dictionary = srd.t.spells[pick]
	if pick == "bless":  # up to three allies, the ones nearest the click
		var friends: Array = cb.all.filter(func(o): return o.side == c.side and not o.dead and cb.dist(c.pos, o.pos) <= 30)
		friends.sort_custom(func(a, b): return a.pos.distance_squared_to(cell) < b.pos.distance_squared_to(cell))
		return friends.slice(0, 3)
	if not sp.has("area_of_effect"):
		return [t] if t != null else []
	var size := int(sp.area_of_effect.size)
	if sp.range == "Self":  # cone or line from the caster toward the click
		var dir := Vector2(cell - c.pos).normalized()
		return cb.all.filter(func(o): return o != c and not o.dead and cb.dist(c.pos, o.pos) <= size \
			and Vector2(o.pos - c.pos).normalized().dot(dir) > 0.7)
	return cb.all.filter(func(o): return not o.dead and cb.dist(cell, o.pos) <= size)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= ev.relative.x * 0.006
		pitch = clampf(pitch - ev.relative.y * 0.004, -1.45, -0.35)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = max(6.0, zoom - 1.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = min(26.0, zoom + 1.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT and not busy and cb.winner() == "":
			var c = cb.current()
			var cell := _cell_under_mouse()
			if mode == "move":
				if not path.is_empty():
					_do(cb.move(c, path))
			else:
				var ts := _targets(c, cell)
				if ts.is_empty():
					hint.text = "Nobody there."
				elif mode == "attack":
					_do(cb.attack(c, ts[0], pick))
				elif mode == "act":
					_do(cb.lay_on_hands(c, ts[0]) if pick == "lay" else cb.bonus_strike(c, ts[0], pick == "flurry"))
				else:
					var lvl := int(srd.t.spells[pick].level)
					var slot := 0
					for k in c.slots:  # shortcut: always the lowest slot that works; add a picker for upcasting
						if k >= lvl and c.slots[k] > 0 and (slot == 0 or k < slot):
							slot = k
					_do(cb.cast(c, pick, ts, slot))
	elif ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_Q:
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
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 72
	l.outline_size = 16
	l.modulate = color
	l.position = minis[who].node.position + Vector3(0, 1.7, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", 2.9, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)

func _roll_die(n: int) -> void:
	Game.sfx("drop_leather")
	die.visible = true
	die_label.visible = false
	var tw := create_tween()
	tw.tween_property(die, "rotation", die.rotation + Vector3(7, 9, 5), 0.35)
	await tw.finished
	die_label.text = str(n)
	die_label.modulate = Color("7dff8a") if n == 20 else (Color("ff6a5a") if n == 1 else Color.WHITE)
	die_label.visible = true
	await _wait(0.35)

func _burst(at: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.position = at + Vector3(0, 0.6, 0)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 60
	p.lifetime = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -3, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := mat(color, 4.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

func _bolt(from: String, to: String, color: Color) -> void:
	var b := _box(Vector3(0.18, 0.18, 0.18), minis[from].node.position + Vector3(0, 0.8, 0), mat(color, 5.0))
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.0
	b.add_child(light)
	var tw := create_tween()
	tw.tween_property(b, "position", minis[to].node.position + Vector3(0, 0.6, 0), 0.25)
	await tw.finished
	b.queue_free()
	Game.sfx("zap_1")
	_burst(minis[to].node.position, color)

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
		_button("Continue" if not Game.story.is_empty() else "Fight again", Game.after_battle)
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
		var cell := Vector2i(int(step[1].get_slice(",", 0)), int(step[1].get_slice(",", 1)))
		if step[1] == "foe":  # the square of the nearest foe, or next to it for a move
			var me = cb.current()
			var foes: Array = cb.all.filter(func(o): return o.side != me.side and not o.dead)
			foes.sort_custom(func(x, y): return cb.dist(me.pos, x.pos) < cb.dist(me.pos, y.pos))
			cell = foes[0].pos + (Vector2i(-1, 0) if step[0] == "m" else Vector2i.ZERO)
		if step[0] == "a":
			_set_mode("attack", 0)
		fake_mouse = cam.unproject_position(world(cell))
		await get_tree().create_timer(0.3).timeout
		var press := InputEventMouseButton.new()
		press.position = fake_mouse
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().create_timer(2.5).timeout
		var c = cb.order.filter(func(o): return o.is_pc)[0]
		print("CLICK %s -> %s at %s, foes hp %s, hint: %s" % [click, c.name, c.pos,
			cb.all.filter(func(o): return not o.is_pc).map(func(o): return o.hp), hint.text])
	if not todo.is_empty():
		get_tree().quit()

func _show(e: Dictionary) -> void:
	match e.type:
		"initiative":
			_say("Initiative: " + ", ".join(e.order), "e8c15a")
		"turn":
			ring.position = world(minis[e.who].c.pos) + Vector3(0, 0.05, 0)
			_say("Round %d: %s" % [e.round, e.who], "e8c15a")
		"move":
			var n: Node3D = minis[e.who].node
			_anim(e.who, "Running_A", "")
			for cell in e.path:
				_face(e.who, world(cell))
				var tw := create_tween()
				tw.tween_property(n, "position", world(cell), 0.18 if not autoplay else 0.05)
				Game.sfx("footstep_%d" % (randi() % 5), 0.15)
				ring.position = world(cell) + Vector3(0, 0.05, 0)
				await tw.finished
			_anim(e.who, "Idle", "")
		"opportunity_attack":
			_say("%s gets an opportunity attack on %s" % [e.who, e.target], "ffb060")
		"attack":
			var shot: bool = minis[e.who].c.attacks.any(func(w): return w.name == e.weapon and w.ranged)
			_face(e.who, minis[e.target].node.position)
			_anim(e.who, "2H_Ranged_Shoot" if shot else "1H_Melee_Attack_Chop")
			await _roll_die(e.roll)
			var how: String = " with advantage" if e.mode > 0 else (" with disadvantage" if e.mode < 0 else "")
			Game.sfx(("chop" if e.crit else "knife_slice") if e.hit else "metal_pot_%d" % (1 + randi() % 3))
			if e.hit:
				_burst(minis[e.target].node.position, Color("d83a2a"))
				if e.target_hp > 0:
					_anim(e.target, "Hit_A")
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
			Game.sfx("phaser_up_1")
			await _wait(0.35)
			var sp_type := "force"
			for sp in srd.t.spells.values():
				if sp.name == e.spell and sp.has("damage"):
					sp_type = sp.damage[0].get("damage_type", {}).get("index", "force")
			for r in e.results:
				if r.has("healed"):
					await _bolt(e.who, r.target, TYPE_COLOR.heal)
				else:
					await _bolt(e.who, r.target, TYPE_COLOR.get(sp_type, Color.WHITE))
					if r.has("roll"):
						await _roll_die(r.roll)
					_float(r.target, "-%d" % r.damage if r.damage > 0 else "no effect", Color("ff5a4a"))
					_say("  %s takes %d%s" % [r.target, r.damage, " (saved)" if r.get("saved", false) else ""])
			await _wait(0.3)
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
			await _roll_die(e.roll)
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
