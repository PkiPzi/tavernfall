extends SceneTree
# A big close-up of a model's head to judge faces: godot --path . -s tools/bg3/face.gd -- model.glb out.png [yaw_degrees]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 900)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var model: Node3D
	if a[0].begins_with("res://"):
		model = load(a[0]).instantiate()
	else:  # a .glb straight from the converter, no import needed
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		doc.append_from_file(a[0], state)
		model = doc.generate_scene(state)
	vp.add_child(model)
	if OS.get_environment("POLISH") != "":
		load("res://board/scenery.gd").polish_character(model)
	if OS.get_environment("HAIRDBG") != "":  # show hair meshes as solid red to see which parts of the head they cover
		for m in model.find_children("*", "MeshInstance3D", true, false):
			if "HAIR" in str(m.name).to_upper() or "HAIR" in str(m.mesh.resource_name).to_upper():
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color.RED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.material_override = mat
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap != null and ap.has_animation("calm"):
		ap.play("calm"); ap.seek(0.3, true); ap.pause()
	await process_frame
	await process_frame
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var head := sk.find_bone("Head_M")
	var at: Vector3 = sk.global_transform * sk.get_bone_global_pose(head).origin + Vector3(0, 0.08, 0)
	var cam := Camera3D.new()
	cam.fov = 24
	vp.add_child(cam)
	var yaw := deg_to_rad(float(a[2]) if a.size() > 2 else 15.0)
	cam.look_at_from_position(at + Vector3(sin(yaw), 0.05, cos(yaw)) * 1.0, at)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a8378")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	cam.environment = env
	var key := DirectionalLight3D.new()
	key.look_at_from_position(Vector3(-2, 2.5, 3), Vector3.ZERO)
	key.light_energy = 1.1
	key.light_color = Color("ffe0b8")
	vp.add_child(key)
	if OS.get_environment("POLISH") != "":
		load("res://board/scenery.gd").character_lights(model, 0.4)
	for i in 5:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(a[1])
	quit()
