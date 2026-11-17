extends Node3D
# Title screen, save slots and party creation, over a tavern diorama.

const Ui = preload("res://ui/ui.gd")
const Scenery = preload("res://board/scenery.gd")
const Prompts = preload("res://ai/prompts.gd")
const Creator = preload("res://ui/creator.gd")
const RACES = ["human", "dwarf", "elf", "halfling", "dragonborn", "gnome", "half-elf", "half-orc", "tiefling"]
const CLASSES = ["fighter", "rogue", "cleric", "wizard", "barbarian", "bard", "druid", "monk", "paladin", "ranger", "sorcerer", "warlock"]
const NAMES = ["Brakka", "Sly", "Odessa", "Wren"]

var pivot: Node3D
var torches := []
var box: VBoxContainer
var layer: CanvasLayer
var panel: PanelContainer
var shade: TextureRect
var creator: Control
var status: Label

func _ready() -> void:
	Game.story = {}
	Game.party = []
	var demo: Array = Game.demo_party()
	for i in demo.size():
		demo[i].pos = Vector2i(4 + i, 4 + (i % 2))
	torches = Scenery.build(self, "tavern", Game.dice.rng, demo.map(func(c): return c.pos)).torches
	for i in demo.size():
		Scenery.character(self, demo[i], i).node.rotation.y = 0.6
	pivot = Ui.orbit_camera(self, Vector3(Scenery.W / 2.0, 0, Scenery.H / 2.0))
	layer = CanvasLayer.new()
	add_child(layer)
	shade = TextureRect.new()  # darkens the left of the picture so the menu reads over any wall
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.02, 0.015, 0.01, 0.94), Color(0.02, 0.015, 0.01, 0.75), Color(0, 0, 0, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.68])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	panel = Ui.panel()
	panel.position = Vector2(70, 120)
	panel.custom_minimum_size = Vector2(520, 0)
	layer.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	status = Ui.label("", 18, Ui.GOLD)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status.offset_bottom = -30
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 8)
	layer.add_child(status)
	_main()
	Game.music("tavern")
	if OS.get_environment("TAVERN_START") == "new":
		_begin_story(Game.demo_party(), "", "", 1)
	elif OS.get_environment("TAVERN_START") == "builder":
		_new()

func _process(dt: float) -> void:
	pivot.rotation.y += dt * 0.05
	Scenery.flicker(torches)

func _clear() -> void:
	for c in box.get_children():
		c.queue_free()

func _main() -> void:
	_clear()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var logo := Ui.title("TAVERNFALL", 76, Ui.GOLD)
	logo.add_theme_font_override("font", Ui.font(Ui.TITLE_FONT, 700, 6))
	logo.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	logo.add_theme_constant_override("outline_size", 8)
	box.add_child(logo)
	var line := Ui.rule()
	line.custom_minimum_size = Vector2(420, 3)
	box.add_child(line)
	var sub := Ui.label("A tabletop adventure, with Claude as your Dungeon Master", 17, Color("c9b98f"))
	sub.add_theme_font_override("font", Ui.ITALIC_FONT)
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	box.add_child(gap)
	_entry("New adventure", _new)
	for n in [1, 2, 3]:
		var s: String = Game.slot_summary(n)
		if s != "":
			_entry("Continue:  " + s.split("  (")[0], Game.load_game.bind(n))
	_entry("Quick battle", func(): Game.start_battle({"template": "dungeon", "monsters": [{"index": "skeleton", "count": 3}]}))
	_entry("Sound and music: " + ("on" if Game.sound_on else "off"), func(): Game.set_sound(not Game.sound_on); _main())
	if Game.speech.available():
		_entry("Spoken story: " + ("on" if Game.speech.on else "off"), func(): Game.speech.set_on(not Game.speech.on); _main())
	_entry("Fullscreen: " + ("on" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "off"), func():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		await get_tree().process_frame
		_main())
	_entry("Quit", get_tree().quit)

# One line of the title menu: plain engraved text that lights up under the pointer, like the game's own.
func _entry(text: String, on: Callable) -> void:
	var b := Ui.text_button(text, on, 26)
	b.add_theme_font_override("font", Ui.font(Ui.TITLE_FONT, 500, 2))
	b.add_theme_color_override("font_color", Color("e6dcc4"))
	b.add_theme_color_override("font_hover_color", Ui.GOLD)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 6)
	b.custom_minimum_size = Vector2(520, 46)
	box.add_child(b)

func _new() -> void:
	panel.visible = false
	shade.visible = false
	creator = Creator.new()
	layer.add_child(creator)
	layer.move_child(creator, 0)
	creator.cancelled.connect(func(): creator.queue_free(); panel.visible = true; shade.visible = true; _main())
	creator.finished.connect(_begin_story)

func _begin_story(party: Array, hints: String, source: String, slot: int) -> void:
	if party.is_empty():
		return
	Game.party = party
	var text := source
	if text.begins_with("http"):
		status.text = "Fetching the adventure from the web..."
		text = await _fetch(text)
		if text == "":
			status.text = "Could not read that link. Paste the text instead."
			return
	status.text = "Claude is writing your adventure. This takes up to a minute..."
	var r: Dictionary = await Game.dm.ask(Prompts.system(), Prompts.plan(hints, text))
	if not r.ok or not r.data.has("opening"):
		status.text = r.get("error", "The plan came back incomplete. Try again.")
		return
	Game.story = {"title": str(r.data.get("title", "Untitled adventure")), "plan": r.data, "summary": "", "turns": [],
		"scene": {}, "slot": slot}
	Game.save_game()
	Game.go(Game.STORY, "town")

# A web page as plain text, cut to a size the AI can read in one go.
func _fetch(url: String) -> String:
	var http := HTTPRequest.new()
	add_child(http)
	if http.request(url) != OK:
		return ""
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return ""
	var html: String = res[3].get_string_from_utf8()
	var re := RegEx.new()
	re.compile("(?s)<(script|style|nav|footer|head)[^>]*>.*?</\\1>")
	html = re.sub(html, " ", true)
	re.compile("<[^>]+>")
	html = re.sub(html, " ", true)
	re.compile("\\s+")
	return re.sub(html, " ", true).xml_unescape().left(40000)
