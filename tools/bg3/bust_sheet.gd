extends SceneTree
# Renders every BG3 portrait bust into one contact sheet: godot --path . -s tools/bg3/bust_sheet.gd -- out.png
const Bust = preload("res://board/bust.gd")

func _initialize() -> void:
	await process_frame
	var out := OS.get_cmdline_user_args()[0]
	var names := []
	for f in DirAccess.get_files_at("res://assets/bg3/models"):
		if f.ends_with(".glb"):
			names.append(f)
	names.sort()
	var cols := 8
	var sheet := Image.create(cols * Bust.W / 2, ((names.size() + cols - 1) / cols) * Bust.H / 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("201a16"))
	for i in names.size():
		var tex: Texture2D = await Bust.render(root, "res://assets/bg3/models/" + names[i])
		var img := tex.get_image()
		img.resize(Bust.W / 2, Bust.H / 2)
		sheet.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i((i % cols) * Bust.W / 2, (i / cols) * Bust.H / 2))
		print(i, " ", names[i])
	sheet.save_png(out)
	quit()
