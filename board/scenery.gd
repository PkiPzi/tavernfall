extends RefCounted
# Builds the places: floor, walls, props, lights and the character models.
# Used by the battle board and by the story screen's diorama.

const W := 12
const H := 10

# Per template: floor tiles, slow ground, props that block a square [model, size],
# wall pieces, wall decoration, light colours.
const TEMPLATES = {
	"dungeon": {
		"floor": ["floor_tile_small", "floor_tile_small", "floor_tile_small", "floor_tile_small",
			"floor_tile_small_broken_A", "floor_tile_small_broken_B", "floor_tile_small_weeds_A", "floor_tile_small_weeds_B"],
		"rough": ["floor_dirt_small_A", "floor_dirt_small_B", "floor_dirt_small_C", "floor_dirt_small_D"],
		"props": [["pillar", 0.5], ["barrel_large", 0.5], ["box_large", 0.55], ["crates_stacked", 0.42], ["column", 0.7]],
		"walls": ["wall", "wall", "wall", "wall_cracked"], "deco": "banner_patternA_red",
		"ambient": Color("7f8ab5"), "torch": Color("ff9040"), "fog": 0.025, "prop_rate": 0.09, "rough_rate": 0.12,
	},
	"tavern": {
		"floor": ["floor_wood_small", "floor_wood_small", "floor_wood_small_dark"],
		"rough": ["floor_wood_small_dark"],
		"props": [["table_small", 0.5], ["barrel_large", 0.5], ["keg", 0.5], ["stool", 0.6], ["chair", 0.55], ["box_small", 0.6]],
		"walls": ["wall", "wall_shelves", "wall_window_closed", "wall"], "deco": "banner_patternB_yellow",
		"ambient": Color("b59a7f"), "torch": Color("ffb060"), "fog": 0.01, "prop_rate": 0.12, "rough_rate": 0.0,
	},
	"cave": {
		"floor": ["floor_dirt_small_A", "floor_dirt_small_B", "floor_dirt_small_C", "floor_dirt_small_D", "floor_dirt_small_weeds"],
		"rough": ["floor_tile_small_broken_A", "floor_tile_small_broken_B"],
		"props": [["column", 0.7], ["box_small", 0.6], ["barrel_small", 0.6], ["trunk_small_A", 0.6]],
		"walls": ["wall_broken", "wall_cracked", "wall"], "deco": "",
		"ambient": Color("5f7a8f"), "torch": Color("7fd0ff"), "fog": 0.05, "prop_rate": 0.1, "rough_rate": 0.18,
	},
	# Open-air places: a flat coloured ground instead of floor tiles, trees instead of walls, daylight.
	"forest": {
		"ground": Color("3c5a2a"), "mud": Color("4a3d28"), "edge": ["trees_A_medium", "trees_B_medium", "trees_A_small", "tree_single_A"],
		"props": [["tree_single_A", 1.0], ["tree_single_B", 1.0], ["rock_single_A", 1.2], ["rock_single_C", 1.2], ["tree_single_A_cut", 1.0]],
		"ambient": Color("a8c49a"), "fog": 0.012, "prop_rate": 0.12, "rough_rate": 0.1,
	},
	"road": {
		"ground": Color("5b6b34"), "mud": Color("6b5638"), "edge": ["trees_A_small", "rock_single_D", "tree_single_B", "rock_single_E"],
		"props": [["rock_single_B", 1.2], ["crate_A_small", 1.3], ["barrel", 1.3], ["sack", 1.3], ["wheelbarrow", 1.1], ["tree_single_A", 1.0]],
		"ambient": Color("c9c2a0"), "fog": 0.006, "prop_rate": 0.07, "rough_rate": 0.0, "track": true,
	},
}

# Which model and which of its built-in gear each class shows.
# shortcut: the pack has no mace or goblin; clerics carry a sword and every monster is a skeleton
# until more CC0 packs are added.
const LOOK = {
	"fighter": ["Knight", ["1H_Sword", "Rectangle_Shield", "Knight_Helmet"]],
	"rogue": ["Rogue_Hooded", ["Knife", "Knife_Offhand"]],
	"cleric": ["Knight", ["1H_Sword", "Badge_Shield"]],
	"wizard": ["Mage", ["2H_Staff"]],
	"barbarian": ["Barbarian", ["2H_Axe"]],
	"bard": ["Rogue_Hooded", ["1H_Crossbow"]],
	"druid": ["Mage", ["2H_Staff", "Round_Shield"]],
	"monk": ["Barbarian", []],
	"paladin": ["Knight", ["2H_Sword", "Knight_Helmet"]],
	"ranger": ["Rogue_Hooded", ["2H_Crossbow"]],
	"sorcerer": ["Mage", ["1H_Wand"]],
	"warlock": ["Mage", ["Spellbook_open"]],
}
# The pack has only skeletons for monsters, so the kind of creature shows as a tint (and its size as scale).
const KIND_TINT = {"humanoid": Color("9fc27a"), "beast": Color("b08a5a"), "giant": Color("9aa3b5"), "fiend": Color("d0553f"),
	"dragon": Color("c0453a"), "ooze": Color("6fd08a"), "plant": Color("5fa04a"), "fey": Color("c79be0"),
	"elemental": Color("6fc0e0"), "aberration": Color("a070c0"), "monstrosity": Color("c0a060"), "construct": Color("8a8a95"),
	"celestial": Color("ffe9a0")}
const GEAR = ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword",
	"2H_Sword", "Knight_Helmet", "Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable", "Spellbook",
	"Spellbook_open", "1H_Wand", "2H_Staff", "1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug"]
const MONSTERS = ["Skeleton_Warrior", "Skeleton_Rogue", "Skeleton_Minion", "Skeleton_Mage"]

static func mat(color: Color, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)

static func box(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

# A KayKit dungeon model. They are built on a 2 m grid, so half size fits our 1 m cells.
static func piece(parent: Node, id: String, pos: Vector3, turn := 0.0, size := 0.5) -> Node3D:
	var path := "res://assets/kaykit/dungeon/%s.gltf.glb" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/kaykit/dungeon/%s.glb" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/kaykit/nature/%s.gltf" % id
	var n: Node3D = load(path).instantiate()
	n.position = pos
	n.rotation.y = turn
	n.scale = Vector3.ONE * size
	parent.add_child(n)
	return n

# Two walls (the near sides stay open so you can see in), props that block squares,
# ground that slows you. Random every time. Returns {walls, rough, torches}.
# spots: cells that must stay free of props (where characters will stand).
static func build(parent: Node3D, template: String, rng: RandomNumberGenerator, spots := []) -> Dictionary:
	var t: Dictionary = TEMPLATES.get(template, TEMPLATES.dungeon)
	var walls := {}
	var rough := {}
	var torches := []
	var outdoor: bool = t.has("ground")
	for x in range(-1, W + 1):
		for y in range(-1, H + 1):
			var cell := Vector2i(x, y)
			if x < 0 or y < 0 or x >= W or y >= H:
				walls[cell] = true
				continue
			var open: bool = x < 4 or x > W - 5 or cell in spots  # keep the starting columns clear
			var quarter := (rng.randi() % 4) * PI / 2
			if not open and rng.randf() < t.prop_rate:
				var p: Array = t.props[rng.randi() % t.props.size()]
				piece(parent, p[0], world(cell), quarter, p[1])
				walls[cell] = true
			elif not open and rng.randf() < t.rough_rate:
				rough[cell] = true
			if outdoor:
				if rough.has(cell) or (t.get("track", false) and abs(y - H / 2.0 + 0.5) < 1.0):
					box(parent, Vector3(1, 0.02, 1), world(cell) + Vector3(0, 0.01, 0), mat(t.mud))
				continue
			var set: Array = t.rough if rough.has(cell) else t.floor
			piece(parent, set[rng.randi() % set.size()], world(cell), quarter)
	if outdoor:
		box(parent, Vector3(W + 60, 0.4, H + 60), Vector3(W / 2.0, -0.2, H / 2.0), mat(t.ground))
		for i in W + 4:  # a tree line along the two far sides
			piece(parent, t.edge[rng.randi() % t.edge.size()], Vector3(i - 3.5, 0, -1.0 - rng.randf() * 1.5), rng.randf() * TAU, 1.3)
		for i in H + 2:
			piece(parent, t.edge[rng.randi() % t.edge.size()], Vector3(-1.0 - rng.randf() * 1.5, 0, i - 0.5), rng.randf() * TAU, 1.3)
		_light(parent, t, true)
		return {"walls": walls, "rough": rough, "torches": torches}
	box(parent, Vector3(W, 0.4, H), Vector3(W / 2.0, -0.25, H / 2.0), mat(Color("211d1b")))
	for i in W / 2:
		piece(parent, t.walls[rng.randi() % t.walls.size()], Vector3(2 * i + 1, 0, -0.25))
	for i in H / 2:
		piece(parent, t.walls[rng.randi() % t.walls.size()], Vector3(-0.25, 0, 2 * i + 1), PI / 2)
	piece(parent, "pillar", Vector3(-0.25, 0, -0.25))
	if t.deco != "":
		piece(parent, t.deco, Vector3(W / 2.0, 0, -0.25))
		piece(parent, t.deco, Vector3(-0.25, 0, H / 2.0), PI / 2)
	for spot in [[Vector3(W * 0.25, 1.0, 0), 0.0], [Vector3(W * 0.75, 1.0, 0), 0.0],
			[Vector3(0, 1.0, H * 0.25), PI / 2], [Vector3(0, 1.0, H * 0.75), PI / 2]]:
		piece(parent, "torch_mounted", spot[0], spot[1])
		var l := OmniLight3D.new()
		l.position = spot[0] + Vector3(0.35, 0.45, 0.0).rotated(Vector3.UP, spot[1] - PI / 2)
		l.light_color = t.torch
		l.light_energy = 3.0
		l.omni_range = 8.0
		l.shadow_enabled = true
		parent.add_child(l)
		torches.append(l)
	_light(parent, t, false)
	return {"walls": walls, "rough": rough, "torches": torches}

static func _light(parent: Node3D, t: Dictionary, outdoor: bool) -> void:
	parent.get_viewport().msaa_3d = Viewport.MSAA_4X
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("7fa6c9") if outdoor else Color("08080b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = t.ambient
	env.ambient_light_energy = 0.9 if outdoor else 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = t.fog
	env.volumetric_fog_albedo = Color("b9a58f")
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var moon := DirectionalLight3D.new()  # comes in over the open sides, shadows fall toward the walls
	moon.rotation_degrees = Vector3(-52, 32, 0)
	moon.light_energy = 1.5 if outdoor else 0.55
	moon.light_color = Color("fff1d6") if outdoor else Color("c3ceff")
	moon.shadow_enabled = true
	parent.add_child(moon)

static func flicker(torches: Array) -> void:
	for t in torches:
		t.light_energy = 3.0 + sin(Time.get_ticks_msec() * 0.011 + t.position.x) * 0.3 + randf() * 0.25

# The animated model for a creature, on a team-coloured disc. n picks the monster variant.
static func character(parent: Node3D, c, n: int) -> Dictionary:
	var node := Node3D.new()
	node.position = world(c.pos)
	node.rotation.y = PI / 2 if c.side == "party" else -PI / 2
	parent.add_child(node)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.4
	cyl.height = 0.02
	disc.mesh = cyl
	disc.material_override = mat(Color("3f8cff") if c.side == "party" else Color("e0402c"), 0.8, 0.55)
	disc.position.y = 0.04
	disc.name = "disc"
	node.add_child(disc)
	var look: Array = LOOK[c.cls] if c.is_pc else [MONSTERS[n % MONSTERS.size()], []]
	var model: Node3D = load("res://assets/kaykit/chars/%s.glb" % look[0]).instantiate()
	model.scale = Vector3.ONE * 0.55 * c.size
	node.add_child(model)
	if not c.is_pc and KIND_TINT.has(c.kind):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var m: BaseMaterial3D = mi.mesh.surface_get_material(i).duplicate()
				m.albedo_color = KIND_TINT[c.kind]
				mi.set_surface_override_material(i, m)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name in GEAR:
			mi.visible = mi.name in look[1]
	if not c.is_pc:  # skeletons come empty-handed; put a blade in the right hand
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var hand := BoneAttachment3D.new()
		hand.bone_name = "handslot.r"
		sk.add_child(hand)
		hand.add_child(load("res://assets/kaykit/gear/Skeleton_Blade.gltf").instantiate())
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	for a in ["Idle", "Running_A"]:
		ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	ap.play("Idle")
	ap.seek(randf())
	var info := Label3D.new()
	info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info.no_depth_test = true
	info.font_size = 36
	info.outline_size = 12
	info.position.y = 1.55 * maxf(c.size, 1.0)
	node.add_child(info)
	return {"node": node, "c": c, "info": info, "ap": ap}
