extends RefCounted
# Story scenes: BG3's loading-screen paintings as establishing shots. Each scene has a painting, a keyword list for
# matching a place the Dungeon Master describes, and the battlefield template to use when a fight breaks out there.
# Scenes.resolve(location) -> scene id; Scenes.card(layer, id, place) fades the painting in with a slow push.

const Ui = preload("res://ui/ui.gd")
const ART := "res://assets/bg3/ui/loadingscreen/loadscreen_bgartwork_%d.png"

const SCENES = {
	"harbor_city": {"art": 1, "label": "A harbour city", "template": "road", "words": ["harbor", "harbour", "port", "docks", "bay", "coast", "seaside", "city at"]},
	"coastal_ruins": {"art": 2, "label": "Ruins on the coast", "template": "road", "words": ["castle", "fortress", "bridge", "keep", "tower", "ruined fort"]},
	"underdark": {"art": 3, "label": "The depths", "template": "cave", "words": ["underdark", "cavern", "mushroom", "glowing", "crystal", "mine", "grotto"]},
	"elven_vale": {"art": 4, "label": "An elven vale", "template": "forest", "words": ["elven", "elf", "sylvan", "spire", "garden", "moonlit", "enclave"]},
	"beach_wreck": {"art": 5, "label": "A wrecked shore", "template": "road", "words": ["beach", "shore", "wreck", "ship", "tentacle", "tide", "sea"]},
	"haunted_marsh": {"art": 6, "label": "A haunted marsh", "template": "forest", "words": ["haunted", "graveyard", "cemetery", "swamp", "marsh", "bog", "statue", "tomb"]},
	"chained_hall": {"art": 7, "label": "A chained hall", "template": "dungeon", "words": ["dungeon", "prison", "cell", "chain", "torture", "crypt", "catacomb", "vault"]},
	"sunken_temple": {"art": 8, "label": "An ancient temple", "template": "dungeon", "words": ["temple", "shrine", "cathedral", "altar", "abbey", "sanctum", "monastery"]},
	"river_valley": {"art": 9, "label": "A river valley", "template": "road", "words": ["valley", "river", "hills", "overlook", "trail", "mountain", "pass", "highlands"]},
	"cursed_wood": {"art": 10, "label": "A cursed wood", "template": "forest", "words": ["cursed", "dark forest", "storm", "blight", "witch", "hag", "twisted", "wood"]},
	"infernal_forge": {"art": 11, "label": "A burning hall", "template": "cave", "words": ["lava", "forge", "hell", "infernal", "volcano", "furnace", "fire", "burning", "smelter"]},
	"dragon_lair": {"art": 13, "label": "A dragon's lair", "template": "cave", "words": ["dragon", "lair", "hoard", "den", "wyrm"]},
	"market_street": {"art": 16, "label": "A busy street", "template": "tavern", "words": ["market", "street", "inn", "tavern", "square", "bazaar", "alley", "shop"]},
}

# What to show when nothing in the text matches: by the battlefield template the plan names.
const DEFAULT_FOR = {"dungeon": "chained_hall", "tavern": "market_street", "cave": "underdark", "forest": "cursed_wood", "road": "river_valley"}

static func ids() -> Array:
	return SCENES.keys()

# loc: {name, description?, template?, scene?}. An explicit scene wins, then keywords in the name and description, then the template.
static func resolve(loc: Dictionary) -> String:
	var s := str(loc.get("scene", ""))
	if SCENES.has(s):
		return s
	var text := ("%s %s" % [loc.get("name", ""), loc.get("description", "")]).to_lower()
	var best := ""
	var best_hits := 0
	for id in SCENES:
		var hits := 0
		for w in SCENES[id].words:
			if w in text:
				hits += 1
		if hits > best_hits:
			best = id
			best_hits = hits
	if best != "":
		return best
	return DEFAULT_FOR.get(str(loc.get("template", "")), "chained_hall")

# The battlefield that goes with a scene.
static func template_of(id: String) -> String:
	return SCENES.get(id, {}).get("template", "dungeon")

static func art(id: String) -> Texture2D:
	var f: String = ART % SCENES.get(id, SCENES.chained_hall).art
	return load(f) if ResourceLoader.exists(f) else null

# Full-screen establishing shot: the painting drifts in, the place name rises at the bottom. Click or wait to leave.
static func card(layer: CanvasLayer, id: String, place: String, seconds := 4.5) -> Control:
	var tex := art(id)
	if tex == null:
		return null
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.z_index = 40
	root.modulate.a = 0.0
	layer.add_child(root)
	var black := ColorRect.new()
	black.color = Color("060504")
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	root.add_child(clip)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.pivot_offset = layer.get_viewport().get_visible_rect().size / 2.0
	clip.add_child(pic)
	var fade := TextureRect.new()  # darkens the lower third so the title reads on any painting
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.82)])
	g.offsets = PackedFloat32Array([0.55, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	var box := VBoxContainer.new()  # the title block sits at the bottom, centred
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_bottom = -70
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var name_l := Ui.title(place, 46, Color("f0e2bc"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_outline_color", Color.BLACK)
	name_l.add_theme_constant_override("outline_size", 10)
	box.add_child(name_l)
	var rule := Ui.rule()
	rule.custom_minimum_size = Vector2(420, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	var sub := Ui.label(SCENES[id].label, 20, Ui.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", Ui.ITALIC_FONT)
	box.add_child(sub)
	var tw := root.create_tween()
	var leave := func():
		if is_instance_valid(root):
			var out := root.create_tween()
			out.tween_property(root, "modulate:a", 0.0, 0.5)
			out.tween_callback(root.queue_free)
	tw.tween_property(root, "modulate:a", 1.0, 0.7)
	root.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: leave.call())
	var push := root.create_tween().set_parallel()
	push.tween_property(pic, "scale", Vector2(1.1, 1.1), seconds + 1.5).from(Vector2(1.0, 1.0)).set_trans(Tween.TRANS_SINE)
	# a tween on root dies with root; a tree timer would call a lambda whose captured root is already freed
	var wait := root.create_tween()
	wait.tween_interval(seconds)
	wait.tween_callback(leave)
	return root
