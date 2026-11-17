extends RefCounted
# The roll overlay, from BG3's own d20 sprite sheets (assets/bg3/dice/d20_<n>.png tumble to rest on n,
# assets/bg3/ui/activeroll/d20explosion.png bursts on a natural 20). Plays, holds the result, fades.

const Ui = preload("res://ui/ui.gd")
const CELL := 256.0
static var _cache := {}

# Frames of a sprite sheet cut into cell x cell squares, empty ones skipped.
static func _frames(path: String, cw: float, ch: float) -> Array:
	if _cache.has(path):
		return _cache[path]
	var out := []
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var img := tex.get_image()
		for y in int(tex.get_height() / ch):
			for x in int(tex.get_width() / cw):
				var r := Rect2i(int(x * cw), int(y * ch), int(cw), int(ch))
				if not img.get_region(r).is_invisible():
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = Rect2(r)
					out.append(at)
	_cache[path] = out
	return out

# n: the number that came up (1 to 20). title: "Attack Roll". detail: "17 + 5 = 22 vs AC 14". outcome: "HIT".
static func play(layer: CanvasLayer, n: int, title := "", detail := "", outcome := "", good := true, speed := 1.0) -> void:
	var tree := layer.get_tree()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var shade := ColorRect.new()  # darkens the world a little so the die reads
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	shade.create_tween().tween_property(shade, "color:a", 0.35, 0.2)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position += Vector2(0, -40)
	root.add_child(box)
	var boom := TextureRect.new()
	boom.size = Vector2(400, 400)
	boom.position = -boom.size / 2.0
	boom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boom.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(boom)
	var die := TextureRect.new()
	die.size = Vector2(230, 230)
	die.position = -die.size / 2.0
	die.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	die.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	die.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(die)
	if title != "":
		var t := Ui.title(title, 22, Ui.INK)
		t.position = Vector2(-300, -160)
		t.size = Vector2(600, 30)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
	var frames := _frames("res://assets/bg3/dice/d20_%d.png" % clampi(n, 1, 20), CELL, CELL)
	var dt := 1.0 / 26.0 / speed
	Game.sound("UI_HUD_ActiveRoll_Appear", "drop_leather")
	for f in frames:
		die.texture = f
		await tree.create_timer(dt).timeout
	if n == 20:  # a burst of gold on a natural 20
		Game.sound("UI_Gameplay_Critical_Hit", "power_up_1")
		var sparks := _frames("res://assets/bg3/ui/activeroll/d20explosion.png", 267.0, 276.0)
		for f in sparks:
			boom.texture = f
			await tree.create_timer(dt * 0.8).timeout
	elif n == 1:
		die.modulate = Color(1, 0.55, 0.5)
	if detail != "" or outcome != "":
		var d := Ui.label(detail, 22, Ui.INK)
		d.position = Vector2(-300, 128)
		d.size = Vector2(600, 30)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_color_override("font_outline_color", Color.BLACK)
		d.add_theme_constant_override("outline_size", 6)
		box.add_child(d)
		var o := Ui.title(outcome, 40, Color("7ddc6a") if good else Color("ff6b5a"))
		o.position = Vector2(-300, 154)
		o.size = Vector2(600, 50)
		o.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		o.add_theme_color_override("font_outline_color", Color.BLACK)
		o.add_theme_constant_override("outline_size", 10)
		box.add_child(o)
	await tree.create_timer(0.85 / speed).timeout
	var out := root.create_tween()
	out.tween_property(root, "modulate:a", 0.0, 0.25)
	await out.finished
	root.queue_free()
