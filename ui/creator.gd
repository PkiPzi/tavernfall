extends Control
# Party creation in the manner of Baldur's Gate 3's character creator: the hero turns on a lit dais in
# the middle, race and class pickers on the left (BG3's own race and class icons), the character sheet on
# the right, a second step for the story. Emits `finished` with the party, or `cancelled`.

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")
const Scenery = preload("res://board/scenery.gd")
const BuildPanel = preload("res://ui/build_panel.gd")
const Assemble = preload("res://board/assemble.gd")

const RACES = ["human", "dwarf", "elf", "halfling", "dragonborn", "gnome", "half-elf", "half-orc", "tiefling"]
const CLASSES = ["fighter", "rogue", "cleric", "wizard", "barbarian", "bard", "druid", "monk", "paladin", "ranger", "sorcerer", "warlock"]
const RACE_ICON = {"human": "human", "dwarf": "dwarf", "elf": "elf", "halfling": "halfling", "dragonborn": "dragonborn",
	"gnome": "gnome", "half-elf": "halfelf", "half-orc": "halforc", "tiefling": "tiefling"}
const DEFAULTS = [["Brakka", "human", "fighter", "man", "scarred, short beard"], ["Sly", "halfling", "rogue", "man", "sharp grin, curly hair"],
	["Odessa", "dwarf", "cleric", "woman", "red braids, kind eyes"], ["Wren", "elf", "wizard", "woman", "silver hair, thoughtful"]]
const ABIL_NAMES = {"str": "STR", "dex": "DEX", "con": "CON", "int": "INT", "wis": "WIS", "cha": "CHA"}

signal finished(party: Array, hints: String, source: String, slot: int)
signal cancelled

var slots := []      # {on, name, race, cls, gender, look, seed, hero}
var sel := 0
var vp: SubViewport
var turntable: Node3D
var model: Node3D
var spin := 0.0
var left_panel: PanelContainer
var right_panel: PanelContainer
var story_panel: PanelContainer
var tabs_row: HBoxContainer
var name_edit: LineEdit
var look_edit: LineEdit
var include: CheckBox
var race_grid: GridContainer
var class_grid: GridContainer
var gender_row: HBoxContainer
var build_panel: VBoxContainer
var left_scroll: ScrollContainer
var sheet_box: VBoxContainer
var hints: TextEdit
var source: TextEdit
var slot_pick: OptionButton
var status: Label
var building := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 4:
		var d: Array = DEFAULTS[i]
		slots.append({"on": true, "name": d[0], "race": d[1], "cls": d[2], "gender": d[3], "look": d[4], "seed": randi() % 100000, "variant": 0, "hero": null})
	_build_stage()
	_build_left()
	_build_right()
	_build_story()
	story_panel.visible = false
	var test := OS.get_environment("TAVERN_CREATE")  # screenshots: "wizard,elf,woman,1200" = class, race, sex, how far to scroll the left panel
	if test != "":
		var t := test.split(",")
		slots[0].cls = t[0]
		slots[0].race = t[1]
		slots[0].gender = t[2]
		slots[0].name = t[0].capitalize()
		_select(0)
		await get_tree().create_timer(1.0).timeout
		left_scroll.scroll_vertical = int(t[3]) if t.size() > 3 else 0
		return
	_select(0)

# ---- the stage: a dais, a warm key light, a cool rim, a little haze ------------------------

func _build_stage() -> void:
	var c := SubViewportContainer.new()
	c.stretch = true
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	c.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0908")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a3548")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color("c9b8a0")
	env.volumetric_fog_emission = Color("120d0a")
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	var cam := Camera3D.new()
	cam.fov = 32
	cam.environment = env
	vp.add_child(cam)
	cam.position = Vector3(0.0, 1.35, 5.1)
	cam.look_at(Vector3(0, 0.98, 0))
	var floor_mat := StandardMaterial3D.new()
	var marble := "res://assets/bg3/terrain/tt_paving_dungeon_marble_c_bma.png"
	if ResourceLoader.exists(marble):
		floor_mat.albedo_texture = load(marble)
		floor_mat.uv1_scale = Vector3(1.3, 1.3, 1.3)
	floor_mat.albedo_color = Color("8c8984")
	floor_mat.roughness = 0.55
	floor_mat.metallic = 0.1
	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.55
	cyl.bottom_radius = 1.7
	cyl.height = 0.22
	dais.mesh = cyl
	dais.material_override = floor_mat
	dais.position.y = -0.11
	vp.add_child(dais)
	var ring := MeshInstance3D.new()  # a thin gold line round the edge
	var tm := TorusMesh.new()
	tm.inner_radius = 1.5
	tm.outer_radius = 1.56
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("d9b566")
	rm.emission_enabled = true
	rm.emission = Color("d9b566")
	rm.emission_energy_multiplier = 0.9
	ring.material_override = rm
	ring.scale.y = 0.35
	vp.add_child(ring)
	var ground := MeshInstance3D.new()  # a dark floor round the dais that fades into the haze
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("141110")
	gm.roughness = 0.9
	ground.material_override = gm
	ground.position.y = -0.22
	vp.add_child(ground)
	var key := SpotLight3D.new()
	key.position = Vector3(-3.2, 4.2, 3.6)
	key.light_color = Color("ffd9a8")
	key.light_energy = 14.0
	key.spot_range = 14.0
	key.spot_angle = 26.0
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 1.6
	vp.add_child(key)
	key.look_at(Vector3(0, 1.0, 0))
	var rim := SpotLight3D.new()
	rim.position = Vector3(3.4, 3.0, -3.8)
	rim.light_color = Color("8fb4ff")
	rim.light_energy = 3.2
	rim.spot_range = 14.0
	rim.spot_angle = 30.0
	rim.light_volumetric_fog_energy = 1.2
	vp.add_child(rim)
	rim.look_at(Vector3(0, 1.2, 0))
	var top := SpotLight3D.new()  # a shaft from straight above onto the dais
	top.position = Vector3(0, 6.0, 0.2)
	top.light_color = Color("fff0d8")
	top.light_energy = 7.0
	top.spot_range = 12.0
	top.spot_angle = 22.0
	top.light_volumetric_fog_energy = 2.2
	vp.add_child(top)
	top.look_at(Vector3(0, 0, 0))
	turntable = Node3D.new()
	vp.add_child(turntable)

func _set_model(c) -> void:
	if model != null:
		model.queue_free()
		model = null
	var path: String = Scenery.model_path(c)
	var built: Node3D = Assemble.character(Assemble.spec_of(c)) if Assemble.available() else null
	if built != null:
		model = built
	elif path == "" or not ResourceLoader.exists(path):
		return
	else:
		model = load(path).instantiate()
	turntable.add_child(model)
	model.scale = Vector3.ONE * (1.0 if built != null else Scenery.model_scale(c))
	Scenery.polish_character(model)
	Scenery.equip(model, c)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap != null:
		var stance: String = "calm" if ap.has_animation("calm") else "idle"  # a relaxed stand, not the crouched fighting stance
		if ap.has_animation(stance):
			ap.get_animation(stance).loop_mode = Animation.LOOP_LINEAR
			ap.play(stance)

func _process(dt: float) -> void:
	if turntable != null:
		spin += dt * 0.4
		turntable.rotation.y = spin

func _gui_input(ev: InputEvent) -> void:  # drag over the middle to turn the hero by hand
	if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT and ev.position.x > 380 and ev.position.x < 900:
		spin += ev.relative.x * 0.01

# ---- left: who ----------------------------------------------------------------------------

func _choice(icon: Texture2D, tip: String, picked: bool, on: Callable, size := 44.0) -> Button:
	var b := Button.new()
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := Ui.flat(Color("14100c") if state != "hover" else Color("2a2012"), Ui.GOLD if picked or state == "hover" else Color("5a4a2c"),
			3 if picked else 1, 4, 5)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): Game.sound("UI_DefaultButton_Click", "metal_click", 0.02, -8.0))
	b.pressed.connect(on)
	return b

func _build_left() -> void:
	left_panel = Ui.panel(0.88)
	left_panel.position = Vector2(14, 14)
	left_panel.custom_minimum_size = Vector2(392, 0)
	add_child(left_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	left_panel.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(372, maxf(get_viewport_rect().size.y - 150.0, 420.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll = scroll
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 358
	scroll.add_child(v)
	v.add_child(Ui.title("Your party", 24))
	v.add_child(Ui.rule())
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 4)
	v.add_child(tabs_row)
	include = CheckBox.new()
	include.text = "In the party"
	include.toggled.connect(func(on: bool): if not building: slots[sel].on = on; _refresh_tabs())
	v.add_child(include)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.text_changed.connect(func(t: String): if not building: slots[sel].name = t)
	v.add_child(name_edit)
	v.add_child(Ui.label("Race", 15, Ui.GOLD))
	race_grid = GridContainer.new()
	race_grid.columns = 5
	race_grid.add_theme_constant_override("h_separation", 5)
	race_grid.add_theme_constant_override("v_separation", 5)
	v.add_child(race_grid)
	v.add_child(Ui.label("Class", 15, Ui.GOLD))
	class_grid = GridContainer.new()
	class_grid.columns = 6
	class_grid.add_theme_constant_override("h_separation", 5)
	class_grid.add_theme_constant_override("v_separation", 5)
	v.add_child(class_grid)
	gender_row = HBoxContainer.new()
	gender_row.add_theme_constant_override("separation", 6)
	v.add_child(gender_row)
	build_panel = BuildPanel.new()
	build_panel.changed.connect(_refresh_hero)
	v.add_child(build_panel)
	look_edit = LineEdit.new()
	look_edit.placeholder_text = "Looks, a few words for the story: red braids, a scar"
	look_edit.text_changed.connect(func(t: String): if not building: slots[sel].look = t)
	v.add_child(look_edit)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.add_child(Ui.button("Back", func(): cancelled.emit()))
	var next := Ui.button("Next: the story", _story_step)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(next)
	outer.add_child(foot)
	status = Ui.label("", 14, Ui.GOLD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(status)

func _hero(i: int):
	var s: Dictionary = slots[i]
	return Game.make_hero(s.name if s.name.strip_edges() != "" else "Hero", s.race, s.cls, s.gender, s.look, s.seed, s.variant, s.get("extra", {}))

# A pick in the build panel (hair, scores, skills, spells): rebuild the hero, the model and the sheet, not the pickers.
func _refresh_hero() -> void:
	var s: Dictionary = slots[sel]
	s.hero = _hero(sel)
	_set_model(s.hero)
	_fill_sheet(s.hero)

# Changing class drops the class-specific picks (scores, skills, style, spells) but keeps the looks.
func _reset_class_picks(s: Dictionary) -> void:
	for k in ["abilities", "skills", "expertise", "style", "spells"]:
		s.get("extra", {}).erase(k)

func _select(i: int) -> void:
	sel = i
	building = true
	var s: Dictionary = slots[i]
	include.button_pressed = s.on
	name_edit.text = s.name
	look_edit.text = s.look
	building = false
	_rebuild()

# Rebuilds everything that depends on the chosen hero: the model, the pickers, the sheet, the tabs.
func _rebuild() -> void:
	var s: Dictionary = slots[sel]
	s.hero = _hero(sel)
	_set_model(s.hero)
	for g in [race_grid, class_grid, gender_row]:
		for ch in g.get_children():
			ch.queue_free()
	for r in RACES:
		var icon: Texture2D = load("res://assets/bg3/icons/races/%s.png" % RACE_ICON[r])
		race_grid.add_child(_choice(icon, r.capitalize(), s.race == r, func(): s.race = r; _rebuild()))
	for cl in CLASSES:
		var icon: Texture2D = load("res://assets/bg3/icons/classes/%s.png" % cl)
		class_grid.add_child(_choice(icon, cl.capitalize(), s.cls == cl, func(): s.cls = cl; _reset_class_picks(s); _rebuild()))
	for gname in ["man", "woman"]:
		var b := Ui.button(gname.capitalize(), func(): s.gender = gname; _rebuild())
		b.disabled = s.gender == gname
		gender_row.add_child(b)
	build_panel.show_slot(s)
	_refresh_tabs()
	_fill_sheet(s.hero)

func _refresh_tabs() -> void:
	for ch in tabs_row.get_children():
		ch.queue_free()
	for i in 4:
		var s: Dictionary = slots[i]
		var hero = s.hero if s.hero != null else _hero(i)
		s.hero = hero
		var tab := Control.new()
		tab.custom_minimum_size = Vector2(66, 66)
		var face := Hud.round_portrait(hero, 60.0, "combatants/btn_small_round_h" if i == sel else "combatants/btn_small_round_d")
		face.modulate = Color.WHITE if s.on else Color(0.45, 0.45, 0.45)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(face)
		var click := Button.new()
		click.flat = true
		click.set_anchors_preset(Control.PRESET_FULL_RECT)
		click.focus_mode = Control.FOCUS_NONE
		click.tooltip_text = "%s, %s %s" % [s.name, s.race.capitalize(), s.cls.capitalize()]
		click.pressed.connect(func(): Game.sound("UI_DefaultButton_Click", "metal_click", 0.02, -8.0); _select(i))
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			click.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		tab.add_child(click)
		tabs_row.add_child(tab)

# ---- right: the sheet ----------------------------------------------------------------------

func _build_right() -> void:
	right_panel = Ui.panel(0.88)
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.offset_left = -354
	right_panel.offset_right = -14
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.position.y = 14
	right_panel.custom_minimum_size = Vector2(340, 0)
	add_child(right_panel)
	sheet_box = VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 6)
	right_panel.add_child(sheet_box)

func _fill_sheet(c) -> void:
	for ch in sheet_box.get_children():
		ch.queue_free()
	sheet_box.add_child(Ui.title(c.name, 24))
	sheet_box.add_child(Ui.label("%s %s, level %d" % [c.spec.race.capitalize(), c.cls.capitalize(), c.level], 16, Ui.DIM))
	sheet_box.add_child(Ui.rule())
	var abil := GridContainer.new()
	abil.columns = 3
	abil.add_theme_constant_override("v_separation", 6)
	abil.add_theme_constant_override("h_separation", 6)
	for k in ABIL_NAMES:
		var box := Ui.panel(0.7)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var l1 := Ui.label(ABIL_NAMES[k], 11, Ui.DIM)
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l2 := Ui.title(str(c.abil[k]), 20, Ui.INK)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l3 := Ui.label("%+d" % c.mod(k), 12, Ui.GOLD)
		l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l1)
		col.add_child(l2)
		col.add_child(l3)
		box.add_child(col)
		abil.add_child(box)
	sheet_box.add_child(abil)
	sheet_box.add_child(Ui.label("Hit points %d     Armour class %d     Speed %d ft" % [c.max_hp, c.ac, c.speed], 16))
	sheet_box.add_child(Ui.rule())
	sheet_box.add_child(Ui.label("Attacks", 15, Ui.GOLD))
	for a in c.attacks:
		var dmg: Array = a.damage.map(func(d): return d.dice)
		sheet_box.add_child(Ui.label("%s   %+d to hit   %s" % [a.name, a.bonus, ", ".join(dmg)], 14))
	if not c.features.is_empty():
		sheet_box.add_child(Ui.label("Features", 15, Ui.GOLD))
		var f := Ui.label(", ".join(c.features.map(func(x): return str(x).replace("-", " ").capitalize())), 14, Ui.INK)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_box.add_child(f)
	if not c.spells.is_empty():
		sheet_box.add_child(Ui.label("Spells", 15, Ui.GOLD))
		var sp := Ui.label(", ".join(c.spells.map(func(x): return Game.srd.t.spells[x].name)), 14, Ui.INK)
		sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_box.add_child(sp)
	var slot_line := ""
	for k in c.slots_max:
		slot_line += "L%d: %d   " % [k, c.slots_max[k]]
	if slot_line != "":
		sheet_box.add_child(Ui.label("Spell slots   " + slot_line, 14, Hud.SLOT_PURPLE))

# ---- step two: the story ---------------------------------------------------------------------

func _build_story() -> void:
	story_panel = Ui.panel(0.92)
	story_panel.set_anchors_preset(Control.PRESET_CENTER)
	story_panel.custom_minimum_size = Vector2(640, 0)
	story_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	story_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(story_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	story_panel.add_child(v)
	v.add_child(Ui.title("Your story", 26))
	v.add_child(Ui.rule())
	v.add_child(Ui.label("Story hints (a few words are enough)", 16, Ui.GOLD))
	hints = TextEdit.new()
	hints.placeholder_text = "e.g. a haunted lighthouse, a missing bride, pirates who fear the dark"
	hints.custom_minimum_size.y = 70
	hints.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(hints)
	v.add_child(Ui.label("Or paste a free adventure (text or a web link) to play that instead", 14, Ui.DIM))
	source = TextEdit.new()
	source.custom_minimum_size.y = 60
	source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(source)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(Ui.label("Save slot"))
	slot_pick = OptionButton.new()
	for n in ["1", "2", "3"]:
		slot_pick.add_item(n)
	slot_pick.focus_mode = Control.FOCUS_NONE
	foot.add_child(slot_pick)
	foot.add_child(Ui.button("Back", func(): story_panel.visible = false; left_panel.visible = true; right_panel.visible = true))
	var begin := Ui.button("Begin the adventure", _begin)
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(begin)
	v.add_child(foot)

func _story_step() -> void:
	var names := {}
	for s in slots:
		if s.on and s.name.strip_edges() != "":
			if names.has(s.name.strip_edges()):
				status.text = "Two heroes cannot share a name."
				return
			names[s.name.strip_edges()] = true
	if names.is_empty():
		status.text = "Pick at least one hero."
		return
	status.text = ""
	left_panel.visible = false
	right_panel.visible = false
	story_panel.visible = true

func _begin() -> void:
	var party := []
	for i in 4:
		if slots[i].on and slots[i].name.strip_edges() != "":
			party.append(_hero(i))
	finished.emit(party, hints.text, source.text.strip_edges(), slot_pick.selected + 1)
