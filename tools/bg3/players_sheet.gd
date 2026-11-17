extends SceneTree
# Contact sheet of assembled player characters, to check races, outfits and hair by eye.
#   godot --path . -s tools/bg3/players_sheet.gd -- out.png "human,elf,tiefling" f|m cls [hair] [full|face] [beard]
const Asm = preload("res://board/assemble.gd")
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var races: PackedStringArray = a[1].split(",")
	var sex: String = a[2]
	var face: bool = a.size() > 5 and a[5] == "face"
	var tile := Vector2i(420, 520)
	var vps := []
	for r in races:
		var vp := SubViewport.new()
		vp.size = tile
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		vps.append(vp)
		var n := Asm.character({"race": r, "sex": sex, "cls": a[3], "look": "a", "hair": a[4] if a.size() > 4 else "", "hair_color": Color("6b4226"), "beard": a[6] if a.size() > 6 else ""})
		if n == null:
			print("missing ", r); continue
		vp.add_child(n)
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		if ap and ap.has_animation("calm"):
			ap.play("calm"); ap.seek(0.3, true); ap.pause()
		await process_frame
		await process_frame
		var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
		var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head_M")).origin
		var cam := Camera3D.new()
		vp.add_child(cam)
		if face:
			cam.fov = 18
			cam.look_at_from_position(head + Vector3(0.25, 0.08, 1.7), head + Vector3(0, 0.05, 0))
		else:
			cam.fov = 32
			cam.look_at_from_position(Vector3(0.6, head.y * 0.55, 3.3 + head.y * 1.1), Vector3(0, head.y * 0.5, 0))
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.18, 0.18, 0.22)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("a09888")
		env.ambient_light_energy = 0.8
		cam.environment = env
		var key := DirectionalLight3D.new()
		key.look_at_from_position(Vector3(-2, 3, 4), Vector3.ZERO)
		vp.add_child(key)
	for i in 8:
		await RenderingServer.frame_post_draw
	var out := Image.create(tile.x * races.size(), tile.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.18, 0.18, 0.22))
	for i in vps.size():
		var img: Image = vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(Vector2i.ZERO, tile), Vector2i(tile.x * i, 0))
	out.save_png(a[0])
	quit()
