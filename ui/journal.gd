extends RefCounted
# The journal: where the party is, the story so far, the last few turns. J in the story screen.

const Ui = preload("res://ui/ui.gd")

static func open(layer: CanvasLayer, story: Dictionary) -> Control:
	Game.sound("UI_Gameplay_Journal_Open", "book_flip_1")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 50
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	shade.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: root.queue_free())
	root.add_child(shade)
	var panel := Ui.panel(0.97)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(760, 0)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(Ui.title("Journal", 28))
	v.add_child(Ui.label(str(story.get("title", "")), 20, Ui.INK))
	var place: String = story.get("scene", {}).get("location", {}).get("name", "")
	if place != "":
		v.add_child(Ui.label("You are at " + place, 15, Ui.DIM))
	v.add_child(Ui.rule())
	v.add_child(Ui.label("The story so far", 16, Ui.GOLD))
	var sum := Ui.label(str(story.get("summary", "")) if str(story.get("summary", "")) != "" else "Your tale has only just begun.", 16)
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sum)
	var turns: Array = story.get("turns", [])
	if not turns.is_empty():
		v.add_child(Ui.label("Recently", 16, Ui.GOLD))
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.custom_minimum_size.y = 120
		rt.add_theme_font_size_override("normal_font_size", 14)
		for t in turns.slice(maxi(0, turns.size() - 5)):
			rt.append_text("[color=#d9b566]%s[/color]\n%s\n\n" % [str(t.player).left(120), str(t.dm).left(260)])
		v.add_child(rt)
	v.add_child(Ui.button("Close", func(): root.queue_free()))
	return root
