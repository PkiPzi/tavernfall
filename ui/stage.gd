extends Node3D
# The living background of the story screen: the place built as a small stage, the party standing on it, the person who
# is talking standing opposite. The camera frames whoever matters. What the player says moves the cast: "talk to the
# stranger" sends the lead hero walking over, "set out" sends the party off the edge of the stage, and when a new scene
# starts they arrive from the left. Nothing here is a world to roam; it is a set that is rebuilt per scene.

const Scenery = preload("res://board/scenery.gd")
const Scenes = preload("res://ui/scenes.gd")

const FORMATION = [Vector2i(5, 5), Vector2i(6, 7), Vector2i(5, 7), Vector2i(6, 4), Vector2i(4, 6), Vector2i(7, 6)]
const TALK_SPOT := Vector2i(11, 6)   # where the person who talks stands
const STAGE_CELLS := Rect2i(3, 3, 11, 6)  # kept clear of props: the cast walks here
const RUN := 4.0
const WALK := 1.7

var holder: Node3D
var rig: Node3D
var cam: Camera3D
var torches := []
var heroes: Array = []        # {node, c, ap, home}
var npc := {}                 # {node, ap}
var npc_name := ""
var mood := ""               # what the open-air stage turned out to be: day, dusk or night
var away := false             # the party has walked off the stage and must come back
var key := ""
var focus := Vector3.ZERO
var zoom := 11.0
var yaw := 0.45
var pitch := -0.2
var t := 0.0
signal party_left   # every hero has walked off the stage
var shot := "wide"           # "wide" shows the stage, "npc" is a close-up of whoever is talking, over the lead hero's shoulder
var yaw_now := 0.45
var pitch_now := -0.2
var vo_now := -0.95
var look_kick := 0.0           # a quick turn of the camera, for "look around"

# template: a battlefield template; opts: {scene, mood}. Rebuilds only when the stage changes.
func build(template: String, party: Array, opts: Dictionary, arrive := true) -> void:
	var k := "%s/%s" % [template, opts.get("scene", "")]
	if k == key:
		return
	key = k
	if holder != null:
		holder.queue_free()
	heroes = []
	npc = {}
	npc_name = ""
	away = false
	holder = Node3D.new()
	add_child(holder)
	var alive: Array = party.filter(func(c): return not c.dead)
	var spots := []
	for x in range(STAGE_CELLS.position.x, STAGE_CELLS.end.x + 1):
		for y in range(STAGE_CELLS.position.y, STAGE_CELLS.end.y + 1):
			spots.append(Vector2i(x, y))
	var made: Dictionary = Scenery.build(holder, template, Game.dice.rng, spots, opts)
	torches = made.torches
	mood = made.get("mood", "")
	for i in alive.size():
		var c = alive[i]
		c.pos = FORMATION[i % FORMATION.size()]
		var m: Dictionary = Scenery.character(holder, c, i)
		var disc: Node = m.node.get_node_or_null("disc")
		if disc != null:
			disc.visible = false
		m.info.visible = false  # the names are in the portrait column; floating ones overlap and hang far above the heads
		m["home"] = Scenery.world(c.pos)
		_play(m, "Idle")
		heroes.append(m)
	Scenery.character_lights(holder)
	_rig()
	if arrive:
		_arrive()

func _rig() -> void:
	rig = Node3D.new()
	holder.add_child(rig)
	cam = Camera3D.new()
	cam.fov = 36
	cam.position = Vector3(0, 0, zoom)
	cam.v_offset = -0.95  # lifts the action above the dialogue box
	var blur := CameraAttributesPractical.new()  # soft background, sharp where the cast stands
	blur.dof_blur_far_enabled = true
	blur.dof_blur_far_distance = 16.0
	blur.dof_blur_far_transition = 10.0
	blur.dof_blur_amount = 0.05
	cam.attributes = blur
	rig.add_child(cam)
	_backdrop()
	focus = _party_centre()
	rig.position = focus

# A painted distance behind the stage (BG3's loading-screen painting for this place) instead of an empty sky. It hangs behind
# whatever the camera looks at, so it follows the camera round, and the depth of field softens it into a backdrop.
func _backdrop() -> void:
	var art := Scenes.art(key.get_slice("/", 1))
	if art == null:
		return
	var quad := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = Vector2(190, 107)
	quad.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = art
	mat.albedo_color = Color(0.62, 0.58, 0.56) if mood != "night" else Color(0.34, 0.36, 0.46)
	mat.disable_receive_shadows = true
	quad.material_override = mat
	quad.position = Vector3(0, 14, -95)
	quad.layers = 1
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(quad)

func _party_centre() -> Vector3:
	if heroes.is_empty():
		return Scenery.world(Vector2i(7, 6))
	var sum := Vector3.ZERO
	for h in heroes:
		sum += h.node.position
	return sum / heroes.size() + Vector3(0, 1.1, 0)

func _lead() -> Dictionary:
	return heroes[0] if not heroes.is_empty() else {}

func _process(dt: float) -> void:
	if rig == null:
		return
	t += dt
	Scenery.flicker(torches)
	var want := _party_centre()
	var want_zoom := 11.0
	if not npc.is_empty() and is_instance_valid(npc.node) and not _lead().is_empty():
		want = (_lead().node.position + npc.node.position) / 2.0 + Vector3(0, 1.1, 0)
		want_zoom = clampf(_lead().node.position.distance_to(npc.node.position) * 0.9 + 6.5, 10.0, 15.0)
	var want_yaw := yaw + sin(t * 0.13) * 0.09 + look_kick
	var want_pitch := pitch + sin(t * 0.21) * 0.015
	var want_vo := -0.95
	var want_fov := 36.0
	var close: bool = shot == "npc" and not npc.is_empty() and is_instance_valid(npc.node) and not npc.get("moving", false) and not _lead().is_empty()
	if close:  # over the shoulder of the lead hero, onto the speaker's face
		var head: Vector3 = npc.node.position + Vector3(0, 1.62 * float(npc.get("scale", 1.0)), 0)
		var away_from: Vector3 = _lead().node.position - npc.node.position
		away_from.y = 0
		var dir := away_from.normalized()
		want = head + Vector3(0, -0.05, 0)
		want_zoom = 2.7
		want_yaw = atan2(dir.x, dir.z) + 0.38
		want_pitch = -0.04
		want_vo = -0.42
		want_fov = 30.0
	focus = focus.lerp(want, 1.0 - exp(-2.6 * dt))
	zoom = lerpf(zoom, want_zoom, 1.0 - exp(-2.0 * dt))
	yaw_now = lerp_angle(yaw_now, want_yaw, 1.0 - exp(-2.2 * dt))
	pitch_now = lerpf(pitch_now, want_pitch, 1.0 - exp(-2.2 * dt))
	vo_now = lerpf(vo_now, want_vo, 1.0 - exp(-2.2 * dt))
	cam.v_offset = vo_now
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-2.2 * dt))
	look_kick = lerpf(look_kick, 0.0, 1.0 - exp(-0.7 * dt))
	rig.position = focus
	rig.rotation = Vector3(pitch_now, yaw_now, 0)
	cam.position = Vector3(0, 0, zoom)

# ---- moving the cast -------------------------------------------------------

func _play(actor: Dictionary, anim: String) -> void:
	var ap: AnimationPlayer = actor.get("ap")
	if ap == null:
		return
	if anim == "Idle" and ap.has_animation("Calm"):  # on the stage people stand relaxed, not in a fighting crouch
		anim = "Calm"
	if not ap.has_animation(anim):
		anim = "Running_A" if anim == "Walking_A" else "Idle"
	if ap.current_animation != anim:
		ap.play(anim, 0.2)

func _face(node: Node3D, at: Vector3, seconds := 0.35) -> void:
	var d := at - node.position
	if d.length() < 0.01:
		return
	var to := atan2(d.x, d.z)
	var tw := create_tween()
	tw.tween_property(node, "rotation:y", node.rotation.y + angle_difference(node.rotation.y, to), seconds)

# Walks an actor in a straight line (the stage is kept clear). Awaitable.
func walk(actor: Dictionary, to: Vector3, run := false) -> void:
	if actor.is_empty() or not is_instance_valid(actor.node):
		return
	var node: Node3D = actor.node
	var d := to - node.position
	d.y = 0
	if d.length() < 0.05:
		return
	node.rotation.y = atan2(d.x, d.z)
	var speed := RUN if run else WALK
	var ap: AnimationPlayer = actor.get("ap")
	if ap != null:  # BG3's walk cycle covers about 1.8 m/s and its run about 3.9 m/s on a person of normal size; scale the clip so the feet do not slide
		ap.speed_scale = clampf(speed / ((3.9 if run else 1.8) * float(actor.get("scale", 1.0))), 0.4, 2.2)
	actor["moving"] = true
	_play(actor, "Running_A" if run else "Walking_A")
	if actor.get("tween") != null and actor.tween.is_valid():
		actor.tween.kill()  # a new order replaces the walk in progress
	var tw := create_tween()
	actor["tween"] = tw
	tw.tween_property(node, "position", Vector3(to.x, node.position.y, to.z), d.length() / speed)
	await tw.finished
	if is_instance_valid(node):
		actor["moving"] = false
		if ap != null:
			ap.speed_scale = 1.0
		_play(actor, "Idle")

func _arrive() -> void:  # the party comes on from the left, one after another
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		h.node.position = Scenery.world(Vector2i(-3, h.c.pos.y)) + Vector3(0, 0, 0)
		_arrive_one(h, i * 0.35)

func _arrive_one(h: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(h.node):
		return
	await walk(h, h.home, true)
	if is_instance_valid(h.node) and not npc.is_empty() and is_instance_valid(npc.node):
		_face(h.node, npc.node.position)
	elif is_instance_valid(h.node):
		_face(h.node, h.home + Vector3(5, 0, 0))

# Who stands opposite the party: sp {name, kind} from the Dungeon Master, or empty for nobody.
func set_speaker(sp: Dictionary) -> void:
	var nm := str(sp.get("name", ""))
	if nm == npc_name:
		return
	if not npc.is_empty():
		_send_off(npc)
		npc = {}
	npc_name = nm
	if nm == "" or holder == null:
		return
	var from := Scenery.world(Vector2i(16, TALK_SPOT.y))
	npc = Scenery.npc_actor(holder, "%s %s" % [sp.get("kind", ""), nm], from)
	var me := npc
	await get_tree().create_timer(0.4).timeout
	if npc != me or not is_instance_valid(me.node):
		return
	await walk(me, Scenery.world(TALK_SPOT))
	if npc != me or not is_instance_valid(me.node):
		return
	_face(me.node, _lead().node.position if not _lead().is_empty() else me.node.position + Vector3(-5, 0, 0), 0.5)
	approach()  # the lead hero steps up to meet them
	speak(3.0)

func _send_off(actor: Dictionary) -> void:
	if not is_instance_valid(actor.node):
		return
	await walk(actor, actor.node.position + Vector3(10, 0, 0))
	if is_instance_valid(actor.node):
		actor.node.queue_free()

# The speaker gestures while the words appear, then settles. seconds: how long the narration takes to read.
func speak(seconds: float) -> void:
	if npc.is_empty() or not is_instance_valid(npc.node):
		return
	var me := npc
	if me.get("moving", false):  # still walking in: the gesture waits for the arrival
		return
	_play(me, "Talk")
	await get_tree().create_timer(seconds).timeout
	if npc == me and is_instance_valid(me.node):
		_play(me, "Idle")

# The lead hero walks up to whoever is talking and the two face each other.
func set_shot(s: String) -> void:
	shot = s

func approach() -> void:
	var lead := _lead()
	if lead.is_empty() or npc.is_empty() or not is_instance_valid(npc.node):
		return
	var stop: Vector3 = npc.node.position - Vector3(2.4, 0, 0)
	await walk(lead, stop)
	if is_instance_valid(lead.node) and not npc.is_empty() and is_instance_valid(npc.node):
		_face(lead.node, npc.node.position)
		_face(npc.node, lead.node.position)
		if lead.ap != null and lead.ap.has_animation("Greet"):  # a raised hand, then back to standing
			_play(lead, "Greet")
			await get_tree().create_timer(2.2).timeout
			if is_instance_valid(lead.node):
				_play(lead, "Idle")

func walk_out() -> void:  # the whole party heads off the right edge
	if away or heroes.is_empty():
		return
	away = true
	if not npc.is_empty():
		_send_off(npc)
		npc = {}
		npc_name = ""
	for i in heroes.size():
		_leave(heroes[i], i * 0.25, i == heroes.size() - 1)

func _leave(h: Dictionary, delay: float, last: bool) -> void:
	await get_tree().create_timer(delay).timeout
	await walk(h, Scenery.world(Vector2i(Scenery.W - 1, h.c.pos.y)))
	if last and away:
		party_left.emit()

# Back on the stage after walking off, when the story stayed in the same place.
func regroup() -> void:
	if not away:
		return
	away = false
	for i in heroes.size():
		if heroes[i].get("tween") != null and heroes[i].tween.is_valid():
			heroes[i].tween.kill()
		heroes[i].node.position = Scenery.world(Vector2i(-3, heroes[i].c.pos.y))
		_arrive_one(heroes[i], i * 0.3)

func look_around() -> void:
	look_kick = 0.9 if randf() < 0.5 else -0.9
	for h in heroes:
		_face(h.node, h.node.position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), 0.6)

# A campfire in the middle of the party for a rest: they turn toward it, it burns a while, then goes out.
func camp(seconds: float) -> void:
	if holder == null or heroes.is_empty():
		return
	var at := Scenery.world(Vector2i(6, 6))
	var holder_fire := Node3D.new()
	holder.add_child(holder_fire)
	var light := Scenery.fire_pit(holder_fire, at, Color("ffa860"), false)
	torches.append(light)
	for h in heroes:
		_face(h.node, at, 0.6)
	await get_tree().create_timer(seconds).timeout
	torches.erase(light)
	if is_instance_valid(holder_fire):
		holder_fire.queue_free()

# What the player's words do on the stage.
func intent(said: String) -> void:
	var low := said.to_lower()
	var any := func(words: Array) -> bool: return words.any(func(w): return w in low)
	if not npc.is_empty() and any.call(["talk", "speak", "greet", "approach", "ask", "address", "question", "chat", "hail", "stranger", "innkeeper", "say "]):
		approach()
	elif any.call(["set out", "leave", "head out", "depart", "travel", "go to", "go into", "walk", "enter", "follow", "onward", "venture", "descend", "climb", "cross"]):
		walk_out()
	elif any.call(["look around", "search", "inspect", "examine", "scout", "listen", "watch", "survey"]):
		look_around()
