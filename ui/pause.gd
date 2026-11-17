extends RefCounted
# The Escape menu: resume, sound, fullscreen, the controls, back to the title. Pauses the scene tree while open.

const Ui = preload("res://ui/ui.gd")

static func open(layer: CanvasLayer, quit_to_menu: Callable) -> Control:
	var tree := layer.get_tree()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS  # still clickable while the world is paused
	root.z_index = 80
	layer.add_child(root)
	tree.paused = true
	var close := func():
		tree.paused = false
		root.queue_free()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.66)
	root.add_child(shade)
	var panel := Ui.panel(0.97)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 0)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := Ui.title("Paused", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Ui.rule())
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 6)
	v.add_child(menu)
	var fill_box := []  # lambdas capture by value, so a lambda reaches itself through this box
	var fill := func():
		for ch in menu.get_children():
			ch.queue_free()
		menu.add_child(Ui.button("Resume", close))
		menu.add_child(Ui.button("Sound and music: " + ("on" if Game.sound_on else "off"), func(): Game.set_sound(not Game.sound_on); fill_box[0].call()))
		if Game.speech.available():
			menu.add_child(Ui.button("Spoken story: " + ("on" if Game.speech.on else "off"), func(): Game.speech.set_on(not Game.speech.on); fill_box[0].call()))
		menu.add_child(Ui.button("Fullscreen: " + ("on" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "off"), func():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			fill_box[0].call()))
		menu.add_child(Ui.button("Picture: " + Game.QUALITY_NAMES[Game.quality] + "  (sharper is slower)", func(): Game.set_quality(Game.quality + 1); fill_box[0].call()))
		menu.add_child(Ui.button("Quit to the title screen", func(): close.call(); quit_to_menu.call()))
	fill_box.append(fill)
	fill.call()
	v.add_child(Ui.rule())
	var help := Ui.label("Click a square to move.  Click a foe with an attack chosen to strike.\nWASD pans the view, Q and E turn it, the wheel or + and - zoom, R and F tilt, Space returns to the acting hero.\nC opens the character sheet, I the bag, B rests (story).  Hover anything for details.", 13, Ui.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	return root
