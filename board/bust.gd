extends RefCounted
# Renders a BG3 model into a portrait picture: head and shoulders for people, the whole body for
# animals and monsters on all fours. Offscreen, one time, cached. Used for every portrait in the game.

const W := 320
const H := 400
static var cache := {}   # model path -> Texture2D
static var busy := false

# host: any node in the tree (the Game autoload). Returns null when the model is missing.
# factory: builds the model node itself (an assembled player character); path is then only the cache key.
static func render(host: Node, path: String, factory := Callable()) -> Texture2D:
	if not factory.is_valid() and not ResourceLoader.exists(path):
		return null
	if cache.has(path):
		return cache[path]
	while busy:  # one render at a time: each loads a big model
		await host.get_tree().process_frame
	busy = true
	var tex := await _draw(host, path, factory)
	busy = false
	cache[path] = tex
	return tex

static func _draw(host: Node, path: String, factory := Callable()) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var model: Node3D = factory.call() if factory.is_valid() else load(path).instantiate()
	if model == null:
		vp.queue_free()
		return null
	vp.add_child(model)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
		ap.seek(0.3, true)
		ap.pause()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var target := Vector3(0, 1.5, 0)
	var vis := 0.9  # metres the picture shows from top to bottom
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var head := sk.find_bone("Head_M") if sk != null else -1
	if head >= 0:  # aim at the head bone of the posed skeleton
		var at: Vector3 = sk.global_transform * sk.get_bone_global_pose(head).origin
		var tip := sk.find_bone("HeadEnd_M_endBone")
		var len := 0.28
		if tip >= 0:
			len = ((sk.global_transform * sk.get_bone_global_pose(tip).origin) - at).length()
		target = at + Vector3(0, len * 0.35, 0)
		vis = clampf(len * 4.6, 0.7, 4.0)
	else:  # no skeleton: the whole thing
		var box := AABB()
		var first := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		target = box.get_center()
		vis = maxf(box.size.y, box.size.z) * 1.1
	var cam := Camera3D.new()
	cam.fov = 26
	vp.add_child(cam)
	cam.position = target + Vector3(0.3, 0.12, 1.0).normalized() * (vis / 2.0 / tan(deg_to_rad(cam.fov / 2.0)))
	cam.look_at(target)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a8378")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	var key := DirectionalLight3D.new()  # warm key from the upper left front, like a painted portrait
	key.look_at_from_position(Vector3(-2, 2.5, 3), Vector3.ZERO)
	key.light_energy = 1.7
	key.light_color = Color("ffe0b8")
	vp.add_child(key)
	var rim := DirectionalLight3D.new()  # cool rim from behind right to lift the head off the dark frame
	rim.look_at_from_position(Vector3(2.5, 1.5, -3), Vector3.ZERO)
	rim.light_energy = 0.9
	rim.light_color = Color("9bb8ff")
	vp.add_child(rim)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)
