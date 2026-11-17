# Render a .glb to a PNG to check a conversion by eye.
#   godot -s tools/bg3/view.gd -- model.glb out.png [animation] [seconds] [yaw_degrees]
extends SceneTree

func _initialize() -> void:
	await process_frame  # the root is not in the tree before the first frame
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(a[0], state) != OK:
		push_error("cannot load " + a[0]); quit(1); return
	var model := doc.generate_scene(state)
	var view := SubViewport.new()  # fixed size whatever the window manager does
	view.size = Vector2i(700, 800)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.add_child(model)
	var box := AABB()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		box = box.merge(m.global_transform * m.get_aabb()) if box.size != Vector3.ZERO else m.global_transform * m.get_aabb()
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	print("meshes aabb ", box, " animations ", player.get_animation_list() if player else [])
	if player and a.size() > 2 and a[2] != "":
		player.play(a[2]); player.seek(float(a[3]) if a.size() > 3 else 0.0, true)
	var cam := Camera3D.new()
	var yaw := deg_to_rad(float(a[4]) if a.size() > 4 else 30.0)
	var dist := maxf(box.size.length(), 0.1) * 0.95
	view.add_child(cam)
	cam.look_at_from_position(box.get_center() + Vector3(sin(yaw), 0.25, cos(yaw)) * dist, box.get_center())
	var sun := DirectionalLight3D.new()
	view.add_child(sun)
	sun.rotation_degrees = Vector3(-40, 40, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	var skm := ProceduralSkyMaterial.new()  # something for metal to reflect
	skm.sky_top_color = Color("5a6a8a")
	skm.sky_horizon_color = Color("b0a898")
	var sky := Sky.new()
	sky.sky_material = skm
	env.environment.sky = sky
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	view.add_child(env)
	for i in 4:
		await process_frame
	view.get_texture().get_image().save_png(a[1])
	quit()
