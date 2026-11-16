extends Node3D
# Title screen, save slots and party creation, over a tavern diorama.

const Ui = preload("res://ui/ui.gd")
const Scenery = preload("res://board/scenery.gd")
const Prompts = preload("res://ai/prompts.gd")
const RACES = ["human", "dwarf", "elf", "halfling", "dragonborn", "gnome", "half-elf", "half-orc", "tiefling"]
const CLASSES = ["fighter", "rogue", "cleric", "wizard", "barbarian", "bard", "druid", "monk", "paladin", "ranger", "sorcerer", "warlock"]
const NAMES = ["Brakka", "Sly", "Odessa", "Wren"]

var pivot: Node3D
var torches := []
var box: VBoxContainer
var rows := []
var hints: TextEdit
var source: TextEdit
var slot_pick: OptionButton
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
	var layer := CanvasLayer.new()
	add_child(layer)
	var p := Ui.panel()
	p.position = Vector2(40, 24)
	p.custom_minimum_size = Vector2(520, 0)
	layer.add_child(p)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	p.add_child(box)
	_main()
	Game.music("tavern")
	if OS.get_environment("TAVERN_START") == "new":
		_new()
		_begin()
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
	box.add_child(Ui.label("Tavernfall", 54, Ui.GOLD))
	box.add_child(Ui.label("A tabletop adventure with Claude as your Dungeon Master", 15, Ui.DIM))
	box.add_child(Ui.button("New adventure", _new))
	for n in [1, 2, 3]:
		var s: String = Game.slot_summary(n)
		box.add_child(Ui.button("Continue slot %d:  %s" % [n, s] if s != "" else "Slot %d is empty" % n,
			Game.load_game.bind(n), s != ""))
	box.add_child(Ui.button("Quick battle (no story)", func(): Game.start_battle({"template": "dungeon", "monsters": [{"index": "skeleton", "count": 3}]})))
	box.add_child(Ui.button("Sound and music: on" if Game.sound_on else "Sound and music: off",
		func(): Game.set_sound(not Game.sound_on); _main()))
	box.add_child(Ui.button("Quit", get_tree().quit))

func _pick(items: Array, chosen: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it.capitalize())
	o.selected = chosen
	o.focus_mode = Control.FOCUS_NONE
	return o

func _new() -> void:
	_clear()
	rows = []
	box.add_child(Ui.label("Your party", 28, Ui.GOLD))
	box.add_child(Ui.label("One to four heroes. Untick a row to leave one out. Their looks are painted into portraits as you play.", 14, Ui.DIM))
	for i in 4:
		var row := HBoxContainer.new()
		var on := CheckBox.new()
		on.button_pressed = true
		var who := LineEdit.new()
		who.text = NAMES[i]
		who.custom_minimum_size.x = 110
		var race := _pick(RACES, [0, 3, 1, 2][i])
		var cls := _pick(CLASSES, i)
		var gender := _pick(["woman", "man"], [1, 1, 0, 0][i])
		var look := LineEdit.new()
		look.placeholder_text = "looks, e.g. red braids, scar"
		look.text = ["scarred, short beard", "sharp grin, curly hair", "red braids, kind eyes", "silver hair, thoughtful"][i]
		look.custom_minimum_size.x = 190
		for w in [on, who, race, cls, gender, look]:
			row.add_child(w)
		box.add_child(row)
		rows.append([on, who, race, cls, gender, look])
	box.add_child(Ui.label("Story hints (a few words are enough)", 16, Ui.GOLD))
	hints = TextEdit.new()
	hints.placeholder_text = "e.g. a haunted lighthouse, a missing bride, pirates who fear the dark"
	hints.custom_minimum_size.y = 56
	hints.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(hints)
	box.add_child(Ui.label("Or paste a free adventure (text or a web link) to play that instead", 14, Ui.DIM))
	source = TextEdit.new()
	source.custom_minimum_size.y = 48
	source.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(source)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(Ui.label("Save slot"))
	slot_pick = _pick(["1", "2", "3"], 0)
	foot.add_child(slot_pick)
	foot.add_child(Ui.button("Begin", _begin))
	foot.add_child(Ui.button("Back", _main))
	box.add_child(foot)
	status = Ui.label("", 14, Ui.GOLD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)

func _begin() -> void:
	Game.party = []
	for r in rows:
		if r[0].button_pressed and r[1].text.strip_edges() != "":
			if Game.party.any(func(c): return c.name == r[1].text.strip_edges()):
				status.text = "Two heroes cannot share a name."
				return
			Game.party.append(Game.make_hero(r[1].text.strip_edges(), RACES[r[2].selected], CLASSES[r[3].selected],
				["woman", "man"][r[4].selected], r[5].text.strip_edges(), randi() % 100000))
	if Game.party.is_empty():
		status.text = "Pick at least one hero."
		return
	var text := source.text.strip_edges()
	if text.begins_with("http"):
		status.text = "Fetching the adventure from the web..."
		text = await _fetch(text)
		if text == "":
			status.text = "Could not read that link. Paste the text instead."
			return
	status.text = "Claude is writing your adventure. This takes up to a minute..."
	var r: Dictionary = await Game.dm.ask(Prompts.system(), Prompts.plan(hints.text, text))
	if not r.ok or not r.data.has("opening"):
		status.text = r.get("error", "The plan came back incomplete. Try again.")
		return
	Game.story = {"title": str(r.data.get("title", "Untitled adventure")), "plan": r.data, "summary": "", "turns": [],
		"scene": {}, "slot": slot_pick.selected + 1}
	Game.save_game()
	get_tree().change_scene_to_file(Game.STORY)

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
