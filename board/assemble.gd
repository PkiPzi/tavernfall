extends RefCounted
# Builds a player character from parts the converter makes (tools/bg3/players.py): a bare body with its head, an outfit
# that fits the body, hair and a beard. All parts share bone names, so a part's skin binds to the body's skeleton by
# name; the same outfit therefore fits every race (the skin's bind poses re-aim it at that race's bones).
# Body regions that an outfit covers are cut out of the body mesh so skin does not poke through the cloth.

# The body's vertex colour (green channel, 0..255) numbers its regions; the outfit names the ones it covers.
const REGION = {"Torso": 50, "Shoulders": 30, "upperarm": 65, "lowerarm": 80, "wrists": 58, "hands": 95, "decolletage_01": 110,
	"decolletage_02": 130, "Thighs": 185, "knees": 15, "shins": 36, "feet": 150, "Pants": 185}

static func load_glb(path: String) -> Node3D:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)

# parts: res:// paths of outfit/hair/beard glbs. hide: region names. Returns the body node with parts attached.
static func build(base_path: String, parts: Array, hide: Array = []) -> Node3D:
	var base := load_glb(base_path)
	if base == null:
		return null
	var sk: Skeleton3D = base.find_child("Skeleton3D", true, false)
	for p in parts:
		var part := load_glb(p)
		if part == null:
			continue
		var part_sk: Skeleton3D = part.find_child("Skeleton3D", true, false)
		if part_sk != null:
			_merge_bones(sk, part_sk)
		for m in part.find_children("*", "MeshInstance3D", true, false):
			if m.skin != null and part_sk != null:  # re-key the skin by bone name: its indices belong to the part's own skeleton
				var named := Skin.new()
				for i in m.skin.get_bind_count():
					named.add_named_bind(part_sk.get_bone_name(m.skin.get_bind_bone(i)), m.skin.get_bind_pose(i))
				m.skin = named
			m.get_parent().remove_child(m)
			m.owner = null
			sk.add_child(m)
			m.skeleton = NodePath("..")
		part.free()
	if not hide.is_empty():
		hide_regions(sk, hide)
	return base

static func hide_regions(sk: Skeleton3D, names: Array) -> void:
	var gone := {}
	for n in names:
		if REGION.has(n):
			gone[REGION[n]] = true
	for m in sk.find_children("*", "MeshInstance3D", true, false):
		if not str(m.name).contains("NKD_Body") or m.mesh == null:
			continue
		var mesh := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var col = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if col == null or idx.is_empty():
				continue
			var keep := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				var all_hidden := true
				for k in 3:
					if not gone.has(int(round(col[idx[t + k]].g * 255.0))):
						all_hidden = false
						break
				if not all_hidden:
					keep.append(idx[t]); keep.append(idx[t + 1]); keep.append(idx[t + 2])
			if keep.is_empty():
				continue  # the whole surface is under the outfit
			arr[Mesh.ARRAY_INDEX] = keep
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m.mesh.surface_get_material(s))
		m.mesh = mesh

static func hide_list(outfit_glb: String) -> Array:
	var f := FileAccess.open(outfit_glb + ".hide.txt", FileAccess.READ)
	return Array(f.get_as_text().split(" ", false)) if f != null else []

# ---- whole characters ---------------------------------------------------------------------------------------------

const DIR = "res://players/"
# Hairstyle name words -> the strand map painted on the crown (the converter writes scalp_<name>.png, see tools/bg3/creature.py SCALPS)
const SCALPS = [
	["f", "Afro", "Short", "HAIR_HUM_F_Afro_Short_A"], ["f", "Afro", "", "HAIR_HUM_F_Afro_Long_A"], ["f", "Curly", "", "HUM_F_NKD_Hair_FemCurly_Short_A"],
	["f", "Braids", "Short", "HUM_F_NKD_Hair_FemBraids_Short_B"], ["f", "Braids", "", "HUM_F_NKD_Hair_FemBraids_Long_A_Spring"],
	["f", "Dreads", "", "HUM_F_NKD_Hair_FemDreads_Long_A_Spring"], ["f", "", "Short", "HUM_F_NKD_Hair_FemStraight_Short_A"],
	["f", "", "", "HUM_F_NKD_Hair_FemStraight_Long_A"],
	["m", "Afro", "", "HUM_M_NKD_Hair_MenAfro_Short_B"], ["m", "Curly", "", "HUM_F_NKD_Hair_MenCurly_Short_B"],
	["m", "Dreads", "", "HUM_M_NKD_Hair_MenDreads_Short_A"], ["m", "Wavy", "Long", "HUM_M_NKD_Hair_MenWavy_Long_B"],
	["m", "Wavy", "", "HUM_M_NKD_Hair_MenWavy_Short_C"], ["m", "", "Long", "HUM_M_NKD_Hair_MenStraight_Long_A"],
	["m", "", "", "HUM_M_NKD_Hair_MenStraight_Short_C"]]
const HAIR_F = ["Straight_Short_L", "Straight_Short_E", "Straight_Short_A", "Straight_Short_C_Spring", "Straight_Long_B_Spring", "Straight_Long_D",
	"Curly_Long_A_Spring", "Curly_Short_A", "Afro_Short_A", "Braids_Long_B", "Braids_Short_B", "Dreads_Long_A_Spring"]
const HAIR_M = ["Straight_Short_C", "Straight_Short_G", "Straight_Short_J", "Straight_Long_A_Spring", "Wavy_Short_A", "Wavy_Long_B", "Curly_Short_A",
	"Afro_Short_A", "Braids_Long_B_Spring", "Dreads_Short_A", "Straight_Short_E", "Wavy_Short_D"]
const BEARDS = ["Short_A", "Short_C", "Short_G", "Short_L", "Long_A", "Long_D", "Long_E"]
const HAIR_COLORS = {"Black": Color("1c1a1a"), "Dark brown": Color("3a2a20"), "Brown": Color("5a3d28"), "Chestnut": Color("7a4a2e"), "Auburn": Color("8a3a22"),
	"Red": Color("a8401f"), "Ginger": Color("c26a2c"), "Blond": Color("c9a45a"), "Platinum": Color("e2d7b4"), "Grey": Color("8e8c8c"), "White": Color("e8e6e0"),
	"Blue": Color("3a5f9c"), "Violet": Color("6c3f94")}

static func path(file: String) -> String:
	return ProjectSettings.globalize_path(DIR + file)

static func available() -> bool:
	return FileAccess.file_exists(path("base_human_f.glb"))

static func scalp_file(hair: String, sex: String) -> String:
	for r in SCALPS:
		if r[0] == sex and (r[1] == "" or hair.contains(r[1])) and (r[2] == "" or hair.contains(r[2])):
			return "scalp_%s.png" % r[3]
	return ""

# spec: race, sex ("f"/"m"), cls, look ("a"/"b"), hair (style name or ""), hair_color, beard (style or ""). Null when the parts are not there.
static func character(spec: Dictionary) -> Node3D:
	var sex: String = spec.get("sex", "f")
	var cls: String = spec.get("cls", "fighter")
	var look: String = spec.get("look", "a")
	var race: String = spec.get("race", "human")
	var outfit := path("outfit_%s_%s_%s.glb" % [cls, look, sex])
	var parts := [outfit]
	var hide := hide_list(outfit)
	var tint: Color = spec.get("hair_color", Color("5a3d28"))
	var hair: String = spec.get("hair", "")
	var beard: String = spec.get("beard", "")
	if hair != "" and FileAccess.file_exists(path("hair_%s_%s.glb" % [sex, hair])):
		parts.append(path("hair_%s_%s.glb" % [sex, hair]))
	if beard != "" and sex == "m" and FileAccess.file_exists(path("beard_%s.glb" % beard)):
		parts.append(path("beard_%s.glb" % beard))
	var base_file := path("base_%s_%s.glb" % [race, sex])
	if not FileAccess.file_exists(base_file) or not FileAccess.file_exists(outfit):
		return null
	var node := build(base_file, parts, hide)
	var sk: Skeleton3D = node.find_child("Skeleton3D", true, false)
	for m in sk.find_children("*", "MeshInstance3D", true, false):
		var n := str(m.name)
		if n.contains("Scalp"):
			m.set_surface_override_material(0, _scalp_material(scalp_file(hair, sex), tint) if hair != "" else null)
			m.visible = hair != ""
		elif n.begins_with("HAIR_") or n.begins_with("BEARD_") or n.contains("_Hair_") or n.contains("Beard"):
			for i in m.mesh.get_surface_count():
				var mat = m.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var d: BaseMaterial3D = mat.duplicate()
					d.albedo_color = tint
					m.set_surface_override_material(i, d)
	return node

static func _scalp_material(file: String, tint: Color) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.3
	m.roughness = 0.55
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if file != "" and FileAccess.file_exists(path(file)):
		m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(path(file)))
	return m

# A part may carry bones the body's skeleton lacks (hair sockets, cloth bones). Add them, hung under the same-named parent.
static func _merge_bones(sk: Skeleton3D, from: Skeleton3D) -> void:
	var added := true
	while added:
		added = false
		for b in from.get_bone_count():
			var bn := from.get_bone_name(b)
			if sk.find_bone(bn) != -1:
				continue
			var p := from.get_bone_parent(b)
			var parent_idx := -1
			if p >= 0:
				parent_idx = sk.find_bone(from.get_bone_name(p))
				if parent_idx == -1:
					continue  # its parent is not in yet: next pass
			sk.add_bone(bn)
			var i := sk.find_bone(bn)
			sk.set_bone_parent(i, parent_idx)
			sk.set_bone_rest(i, from.get_bone_rest(b))
			sk.set_bone_pose_position(i, from.get_bone_rest(b).origin)
			sk.set_bone_pose_rotation(i, from.get_bone_rest(b).basis.get_rotation_quaternion())
			added = true

# The look a hero has when the player has not chosen one: hair and colour picked from the hero's seed.
static func default_look(seed_n: int, sex: String) -> Dictionary:
	var styles: Array = HAIR_F if sex == "f" else HAIR_M
	var cols: Array = HAIR_COLORS.keys()
	var d := {"hair": styles[seed_n % styles.size()], "hair_color": cols[(seed_n / 7) % cols.size()], "beard": ""}
	if sex == "m" and seed_n % 3 != 0:
		d.beard = BEARDS[(seed_n / 3) % BEARDS.size()]
	return d

# A hero's creature -> the spec `character()` wants.
static func spec_of(c) -> Dictionary:
	var sp: Dictionary = c.spec
	var sex := "f" if str(sp.get("gender", "woman")) == "woman" else "m"
	var d := default_look(int(sp.get("seed", 1)), sex)
	var colname: String = str(sp.get("hair_color", d.hair_color))
	return {"race": str(sp.get("race", "human")), "sex": sex, "cls": str(c.cls), "look": "b" if int(sp.get("variant", 0)) == 1 else "a",
		"hair": str(sp.get("hair", d.hair)), "beard": str(sp.get("beard", d.beard)) if sex == "m" else "",
		"hair_color": HAIR_COLORS.get(colname, Color("5a3d28"))}
