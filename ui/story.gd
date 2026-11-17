extends Node3D
# The story screen: the DM's narration over a diorama of the place, choices, a free-text box.
# The code here rolls the checks, hands out rewards and starts the fights the DM proposes.

const Ui = preload("res://ui/ui.gd")
const Hud = preload("res://ui/hud.gd")
const Sheet = preload("res://ui/sheet.gd")
const LevelUp = preload("res://ui/levelup.gd")
const Scenes = preload("res://ui/scenes.gd")
const Stage = preload("res://ui/stage.gd")
const Rest = preload("res://ui/rest.gd")
const DiceRoll = preload("res://ui/diceroll.gd")
const Journal = preload("res://ui/journal.gd")
const Pause = preload("res://ui/pause.gd")
const Scenery = preload("res://board/scenery.gd")
const Prompts = preload("res://ai/prompts.gd")
const Combat = preload("res://rules/combat.gd")
const ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]

var stage: Node3D       # the living background (ui/stage.gd)
var stage_key := ""
var curtain: ColorRect  # black, over the 3D stage and under the interface: falls when the party walks off, lifts when the next scene starts
var last_place := ""
var ui_layer: CanvasLayer
var speaker_box: VBoxContainer
var title_l: Label
var place_l: Label
var text: RichTextLabel
var choices: VBoxContainer
var entry: LineEdit
var think: Label
var party_box: VBoxContainer
var autoplay := OS.get_environment("TAVERN_AUTOPLAY") != ""

var skip_btn: Button
var _voice_tw: Tween
var _voice_base := 0
var _voice_quote_at := 0

func _ready() -> void:
	_build_ui()
	_ready_hooks()
	var s: Dictionary = Game.story
	if Game.battle_result != null:
		var r: Dictionary = Game.battle_result
		Game.battle_result = null
		s.scene.erase("encounter")
		if r.won:
			var news: Array = Game.award_xp(r.xp_each)
			news.push_front("Victory! Each hero gains %d XP." % r.xp_each)
			_show()
			if not Game.levelups.is_empty():
				LevelUp.open(ui_layer, Game.levelups)
			_ask("The fight is over. The party won in %d rounds.%s" % [r.rounds,
				" Heroes who died: %s." % ", ".join(r.fallen) if not r.fallen.is_empty() else " Nobody died."], "(the fight)", news)
		else:
			s.scene = {"narration": "Darkness takes the last of you. The tale of this party ends here... unless fate allows another try.",
				"location": s.scene.get("location", {}), "choices": [], "defeat": true}
			_show()
		return
	if s.scene.is_empty():
		s.scene = {"narration": str(s.plan.opening), "location": _place(s.plan.get("locations", [{}])[0]),
			"choices": ["Look around", "Talk to someone nearby", "Set out at once"]}
		Game.save_game()
	_show()

func _ready_hooks() -> void:
	var act := OS.get_environment("TAVERN_ACT")  # screenshots: say this to the party after 7 s
	if act != "":
		get_tree().create_timer(7.0).timeout.connect(func(): _rest_menu() if act == "__rest" else _act(act))

func _rest_menu() -> void:
	if think.text != "":
		return
	Rest.open(ui_layer, func(kind: String, lines: Array):
		stage.camp(5.0)
		text.text = "\n".join(lines.map(func(l): return "[color=#e8c15a]%s[/color]" % l))
		_party()
		Game.save_game())

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_B and not entry.has_focus():
		_rest_menu()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_J and not entry.has_focus():
		Journal.open(ui_layer, Game.story)
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_SPACE and Game.speech.playing and not entry.has_focus():
		_skip_voice()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		Pause.open(ui_layer, func(): Game.save_game(); Game.go(Game.MENU, "town"))

func _process(dt: float) -> void:
	pass

# ---- interface --------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
	add_child(layer)
	Ui.vignette(layer, 0.5)
	curtain = ColorRect.new()
	curtain.color = Color("050403")
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.modulate.a = 0.0
	layer.add_child(curtain)
	var left := VBoxContainer.new()  # the title panel with the party under it, so they never overlap whatever the panel holds
	left.position = Vector2(16, 16)
	left.add_theme_constant_override("separation", 10)
	layer.add_child(left)
	var top := Ui.panel()
	left.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	title_l = Ui.label("", 24, Ui.GOLD)
	place_l = Ui.label("", 15, Ui.DIM)
	tv.add_child(title_l)
	tv.add_child(place_l)
	tv.add_child(Ui.button("Journal  (J)", func(): Journal.open(ui_layer, Game.story)))
	tv.add_child(Ui.button("Rest  (B)", _rest_menu))
	tv.add_child(Ui.button("Save and go to menu", func(): Game.save_game(); Game.go(Game.MENU, "town")))

	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 8)
	left.add_child(party_box)

	# The dialogue box: narration, then numbered answers, like a CRPG conversation.
	var bottom := Ui.panel(0.92)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -14
	bottom.custom_minimum_size.x = 880
	layer.add_child(bottom)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bottom.add_child(v)
	# the speaker's face sits beside the words, so the box stays low and the stage above stays in view
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	speaker_box = VBoxContainer.new()
	speaker_box.add_theme_constant_override("separation", 2)
	speaker_box.custom_minimum_size.x = 120
	speaker_box.visible = false
	head.add_child(speaker_box)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 4)
	head.add_child(words)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size.y = 52
	text.add_theme_font_size_override("normal_font_size", 18)
	text.add_theme_color_override("default_color", Ui.INK)
	words.add_child(text)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 0)
	words.add_child(choices)
	var row := HBoxContainer.new()
	entry = LineEdit.new()
	entry.placeholder_text = "Or type what the party does..."
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text_submitted.connect(func(t): _act(t))
	row.add_child(entry)
	row.add_child(Ui.button("Do it", func(): _act(entry.text)))
	v.add_child(row)
	# thinking note on the left, a small skip button on the right, in one low row under the answers
	var foot := HBoxContainer.new()
	v.add_child(foot)
	think = Ui.label("", 14, Ui.GOLD)
	think.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(think)
	skip_btn = Ui.button("Skip voice (Space)", _skip_voice)
	skip_btn.visible = false
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(skip_btn)

func _place(loc) -> Dictionary:
	if typeof(loc) != TYPE_DICTIONARY:
		loc = {}
	var scene := Scenes.resolve(loc)
	var t := str(loc.get("template", ""))
	if not t in Prompts.TEMPLATES:  # no battlefield named: take the one that goes with the painting
		t = Scenes.template_of(scene)
	return {"name": str(loc.get("name", "Somewhere")), "template": t, "scene": scene}

func _diorama(loc: Dictionary, narration := "") -> void:
	var template := str(loc.get("template", "dungeon"))
	Game.music("tavern" if template == "tavern" else "explore")
	if stage == null:
		stage = Stage.new()
		add_child(stage)
		stage.party_left.connect(func(): create_tween().tween_property(curtain, "modulate:a", 1.0, 0.6))
	var k := "%s/%s" % [template, loc.get("scene", "")]
	if k != stage_key and stage_key != "":
		Game.sfx("door_open_1")
	stage_key = k
	var low := narration.to_lower()
	var mood := ""  # open-air places follow what the narration says; indoors it makes no difference
	if ["night", "moon", "midnight", "stars", "darkness"].any(func(w): return w in low):
		mood = "night"
	elif ["dusk", "sunset", "evening", "twilight", "dawn"].any(func(w): return w in low):
		mood = "dusk"
	stage.build(template, Game.party, {"scene": loc.get("scene", ""), "mood": mood})
	Game.ambience_for(template, stage.mood)

func _show(notes := []) -> void:
	var s: Dictionary = Game.story
	var sc: Dictionary = s.scene
	title_l.text = s.title
	place_l.text = sc.get("location", {}).get("name", "")
	var here: String = place_l.text
	if here != "" and here != last_place and sc.get("location", {}).has("scene"):  # a new place: an establishing shot first
		last_place = here
		Scenes.card(ui_layer, sc.location.scene, here)
	_diorama(sc.get("location", {}), str(sc.get("narration", "")))
	stage.regroup()
	create_tween().tween_property(curtain, "modulate:a", 0.0, 0.9)
	stage.set_speaker(sc.get("speaker", {}) if typeof(sc.get("speaker")) == TYPE_DICTIONARY else {})
	stage.set_shot("npc" if typeof(sc.get("speaker")) == TYPE_DICTIONARY and not sc.speaker.is_empty() else "wide")
	stage.speak(clampf(str(sc.get("narration", "")).length() / 220.0, 0.3, 2.5) + 1.2)
	if notes.any(func(n): return "XP" in n or "potion" in n):
		Game.sound("UI_Gameplay_Coin_Add", "handle_coins")
	else:
		Game.sfx("book_flip_1")
	var body := ""
	var notes_len := 0
	for n in notes:
		body += "[color=#e8c15a]%s[/color]\n" % n
		notes_len += str(n).length() + 1
	_speaker(sc.get("speaker", {}))
	var sp: Dictionary = sc.get("speaker", {}) if typeof(sc.get("speaker")) == TYPE_DICTIONARY else {}
	var says := str(sp.get("says", "")).strip_edges()
	var spoken := ""  # the plain words, for the voice to reveal them in step
	text.text = body + str(sc.narration)
	spoken = str(sc.narration)
	var quote_at := spoken.length()
	if says != "":
		var who := str(sp.get("name", "")) + ": "
		text.text += "\n[color=#e8c15a]%s[/color]\u201c%s\u201d" % [who, says]
		quote_at = spoken.length() + 1 + who.length() + 1
		spoken += "\n" + who + "\u201c" + says + "\u201d"
	_speak_scene(str(sc.narration), says, sp, notes_len, quote_at)
	think.text = ""
	for c in choices.get_children():
		c.queue_free()
	var can_type := false
	if sc.get("ended", false):
		choices.add_child(Ui.button("The end. Back to the menu", func(): Game.go(Game.MENU, "town")))
	elif sc.get("defeat", false):
		choices.add_child(Ui.button("Try again from the last save", Game.load_game.bind(s.slot)))
		choices.add_child(Ui.button("Back to the menu", func(): Game.go(Game.MENU, "town")))
	elif sc.has("encounter"):
		var foes: Array = sc.encounter.monsters.map(func(m): return "%d x %s" % [m.count, Game.srd.t.monsters[m.index].name])
		choices.add_child(Ui.button("Begin the fight:  " + ", ".join(foes), func(): Game.start_battle(sc.encounter)))
	else:
		can_type = true
		var n := 0
		for ch in sc.get("choices", []):
			var o := _opt(ch)
			if o.requires != "" and _proficient(o.requires).is_empty():
				continue  # an option only a hero with that skill can see
			n += 1
			choices.add_child(_choice_button(n, o))
		if n == 0:
			choices.add_child(Ui.button("Continue", _act.bind("We continue.")))
	entry.editable = can_type
	entry.text = ""
	_party()
	if autoplay and not sc.get("ended", false) and not sc.get("defeat", false):
		await get_tree().create_timer(0.8).timeout
		if sc.has("encounter"):
			Game.start_battle(sc.encounter)
		else:
			_act(str(sc.get("choices", ["We continue."])[0]) if not sc.get("choices", []).is_empty() else "We continue.")

# ---- choices with skill checks ---------------------------------------------------------------

# A choice is plain text or {"text", "skill", "dc", "requires"}: "skill" is the check the choice calls for, "requires" a skill
# a hero must be proficient in for the option to show at all (so a wizard sees an Arcana option the fighter never does).
func _opt(ch) -> Dictionary:
	if typeof(ch) == TYPE_DICTIONARY:
		return {"text": str(ch.get("text", "")), "skill": _skill_id(str(ch.get("skill", ""))), "dc": clampi(int(ch.get("dc", 12)), 5, 25),
			"requires": _skill_id(str(ch.get("requires", "")))}
	return {"text": str(ch), "skill": "", "dc": 12, "requires": ""}

func _skill_id(name_: String) -> String:
	var k := name_.strip_edges().to_lower().replace(" ", "-")
	return k if Game.srd.t.skills.has(k) else ""

func _proficient(skill: String) -> Array:
	return Game.party.filter(func(c): return not c.dead and int(c.skills.get(skill, 0)) >= 1)

# The hero who would roll it: the best modifier among the living.
func _best_for(skill: String):
	var best = null
	for c in Game.party:
		if c.dead:
			continue
		if best == null or c.skill_bonus(Game.srd, skill) > best.skill_bonus(Game.srd, skill):
			best = c
	return best

func _choice_button(n: int, o: Dictionary) -> Button:
	var tag := ""
	var tip := ""
	var colour := Ui.INK
	if o.skill != "":
		var who = _best_for(o.skill)
		var bonus: int = who.skill_bonus(Game.srd, o.skill)
		var chance := clampi(roundi((21 - (o.dc - bonus)) * 5.0), 0, 100)
		tag = "[%s  DC %d]  " % [o.skill.replace("-", " ").capitalize(), o.dc]
		tip = "%s check, DC %d.\n%s would roll it (%+d): about %d%% to succeed." % [o.skill.replace("-", " ").capitalize(), o.dc, who.name, bonus, chance]
		colour = Color("7fd8e8")
	if o.requires != "":
		var who = _proficient(o.requires)[0]
		colour = Ui.GOLD
		if o.skill == "":
			tag = "[%s]  " % o.requires.replace("-", " ").capitalize()
		tip += ("\n" if tip != "" else "") + "Only you can see this: %s is skilled in %s." % [who.name, o.requires.replace("-", " ")]
	var b := Ui.text_button("%d.  %s%s" % [n, tag, o.text], _pick.bind(o), 18)
	b.tooltip_text = tip
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, colour)
	return b

func _pick(o: Dictionary) -> void:
	if o.skill == "":
		_act(o.text)
		return
	if think.text != "" or not entry.editable:
		return
	stage.set_shot("wide")
	stage.intent(o.text)
	var who = _best_for(o.skill)
	var res := _check({"character": who.name, "skill": o.skill, "dc": o.dc})
	for c in choices.get_children():
		c.queue_free()
	entry.editable = false
	await DiceRoll.play(ui_layer, res.roll, res.title, "%d %s %d = %d   vs DC %d" % [res.roll, "+" if res.bonus >= 0 else "-", absi(res.bonus), res.total, res.dc],
		"SUCCESS" if res.success else "FAILURE", res.success, 1.0)
	_ask("The player chose: %s. Check result: %s" % [o.text, res.line], "%s (%s)" % [o.text, res.line], [res.line])

# Reads the narration (narrator) and then what the speaker says (their own voice), revealing the text sentence by sentence.
# Without a voice the text just types out. Space or the Skip button ends the reading and shows everything.
func _speak_scene(narration: String, says: String, sp: Dictionary, base: int, quote_at: int) -> void:
	var sp_node: Node = Game.speech
	if _voice_tw != null:
		_voice_tw.kill()
	if sp_node.is_connected("sentence_started", _on_sentence):
		sp_node.sentence_started.disconnect(_on_sentence)
	if sp_node.is_connected("finished", _on_voice_done):
		sp_node.finished.disconnect(_on_voice_done)
	_voice_base = base
	_voice_quote_at = quote_at
	text.visible_characters = -1
	var lines := [{"text": narration, "voice": sp_node.NARRATOR, "speed": 0.95}]
	if says != "":
		lines.append({"text": says, "voice": sp_node.voice_for(str(sp.get("name", "")), str(sp.get("kind", ""))), "speed": 1.0})
	if not sp_node.on or not sp_node.available():
		text.visible_ratio = 0.0
		create_tween().tween_property(text, "visible_ratio", 1.0, clampf(narration.length() / 220.0, 0.3, 2.5))
		skip_btn.visible = false
		return
	text.visible_characters = base
	sp_node.sentence_started.connect(_on_sentence)
	sp_node.finished.connect(_on_voice_done, CONNECT_ONE_SHOT)
	skip_btn.visible = true
	sp_node.play(lines)

func _on_sentence(line: int, from_char: int, to_char: int, seconds: float) -> void:
	var off := _voice_base + (0 if line == 0 else _voice_quote_at + 1)  # +1 for the opening quotation mark
	if _voice_tw != null:
		_voice_tw.kill()
	text.visible_characters = maxi(text.visible_characters, off + from_char)
	_voice_tw = create_tween()
	_voice_tw.tween_property(text, "visible_characters", off + to_char, maxf(seconds * 0.92, 0.2))

func _on_voice_done() -> void:
	if _voice_tw != null:
		_voice_tw.kill()
	text.visible_characters = -1
	skip_btn.visible = false
	if Game.speech.is_connected("sentence_started", _on_sentence):
		Game.speech.sentence_started.disconnect(_on_sentence)

func _skip_voice() -> void:
	Game.speech.skip()

# Who is talking: a bust of a fitting BG3 model and their name above the narration, like a conversation.
func _speaker(sp: Dictionary) -> void:
	for ch in speaker_box.get_children():
		ch.queue_free()
	speaker_box.visible = not sp.is_empty()
	if sp.is_empty():
		return
	var look: String = sp.get("kind", "") + " " + sp.get("name", "")
	var person: Dictionary = Scenery.npc_person(look)
	var face := Hud.round_portrait(person if not person.is_empty() else Scenery.npc_model(look), 84.0)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	speaker_box.add_child(face)
	var nm := Ui.title(sp.get("name", ""), 17)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_box.add_child(nm)
	if sp.get("kind", "") != "":
		var kd := Ui.label(sp.kind.capitalize(), 12, Ui.DIM)
		kd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		speaker_box.add_child(kd)

func _party() -> void:
	for c in party_box.get_children():
		c.queue_free()
	for c in Game.party:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var face := Hud.round_portrait(c, 66.0)
		face.tooltip_text = Ui.sheet(c) + "\n(click for the full sheet)"
		face.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: Sheet.open(ui_layer, c))
		face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if c.dead:
			face.modulate = Color(0.5, 0.45, 0.45)
		v.add_child(face)
		var hp := Hud.hp_bar(c, 62.0, 5.0)
		hp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(hp)
		var l := Ui.label(c.name, 13, Ui.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		v.add_child(l)
		party_box.add_child(v)

# ---- talking to the DM ------------------------------------------------------

func _act(what: String) -> void:
	what = what.strip_edges()
	if what == "" or think.text != "" or not entry.editable:
		return
	stage.set_shot("wide")  # back to the whole stage while the party acts
	stage.intent(what)  # the cast acts it out while the Dungeon Master thinks
	_ask("The player says the party does this: " + what, what)

# what: the line the DM reads. shown: what goes into the turn log as the player's side.
func _ask(what: String, shown: String, notes := [], depth := 0) -> void:
	for c in choices.get_children():
		c.queue_free()
	entry.editable = false
	think.text = "The Dungeon Master is thinking..."
	var r: Dictionary = await Game.dm.ask(Prompts.system(), Prompts.turn(what))
	if not r.ok or not r.data.has("narration"):
		think.text = ""
		text.text = "[color=#ff9a8a]%s[/color]" % r.get("error", "The Dungeon Master's answer was incomplete.")
		choices.add_child(Ui.button("Ask again", _ask.bind(what, shown, notes, depth)))
		return
	var d: Dictionary = r.data
	var s: Dictionary = Game.story
	var who = d.get("speaker")
	s.scene = {"narration": str(d.narration), "location": _place(d.get("location")),
		"speaker": {"name": str(who.get("name", "")), "kind": str(who.get("kind", "")), "says": str(who.get("says", "")) if who.get("says") != null else ""} if typeof(who) == TYPE_DICTIONARY and str(who.get("name", "")) != "" else {},
		"choices": (d.get("choices") if typeof(d.get("choices")) == TYPE_ARRAY else []).slice(0, 5).filter(func(x): return typeof(x) in [TYPE_STRING, TYPE_DICTIONARY]).map(func(x): return x if typeof(x) == TYPE_DICTIONARY else str(x))}
	s.turns.append({"player": shown, "dm": s.scene.narration})
	if typeof(d.get("summary")) == TYPE_STRING and d.summary != "":
		s.summary = d.summary
	notes = notes + _apply(d)
	if d.get("ended", false) == true:
		s.scene["ended"] = true
	var enc = _encounter(d.get("encounter"))
	if enc != null:
		enc["template"] = s.scene.location.template
		s.scene["encounter"] = enc
	Game.save_game()
	var chk = d.get("check")
	if typeof(chk) == TYPE_DICTIONARY and enc == null and depth < 2:
		var res := _check(chk)
		var line: String = res.line
		await DiceRoll.play(ui_layer, res.roll, res.title, "%d %s %d = %d   vs DC %d" % [res.roll, "+" if res.bonus >= 0 else "-", absi(res.bonus), res.total, res.dc],
			"SUCCESS" if res.success else "FAILURE", res.success, 3.0 if autoplay else 1.0)
		_show(notes + [line])
		await get_tree().create_timer(0.4 if autoplay else 1.0).timeout
		_ask("Check result: " + line, "(%s)" % line, [line], depth + 1)
		return
	_show(notes)

# Rewards and rests the DM granted. Returns lines to show the player.
func _apply(d: Dictionary) -> Array:
	var notes := []
	var alive: Array = Game.party.filter(func(c): return not c.dead)
	var rw = d.get("reward")
	if typeof(rw) == TYPE_DICTIONARY and not alive.is_empty():
		var xp := clampi(int(rw.get("xp", 0)), 0, 300)
		if xp > 0:
			notes.append("Each hero gains %d XP." % xp)
			notes += Game.award_xp(xp)
		var items = rw.get("items")
		var potions := clampi(int(items.get("potion-of-healing", 0)), 0, 3) if typeof(items) == TYPE_DICTIONARY else 0
		for i in potions:
			alive.sort_custom(func(a, b): return a.items.get("potion-of-healing", 0) < b.items.get("potion-of-healing", 0))
			alive[0].items["potion-of-healing"] = alive[0].items.get("potion-of-healing", 0) + 1
			notes.append("%s takes a healing potion." % alive[0].name)
	var h = d.get("heal")
	if typeof(h) == TYPE_DICTIONARY:
		notes.append(_heal(alive, str(h.get("caster", "")), str(h.get("with", "")), str(h.get("target", ""))))
	match d.get("rest"):
		"short":
			for c in alive:
				c.short_rest(Game.dice, c.hit_dice)
			notes.append("The party takes a short rest.")
		"long":
			for c in alive:
				c.long_rest()
			notes.append("The party takes a long rest. Everyone is restored.")
	return notes

# Healing outside a fight: spends the potion or the lowest spell slot and rolls.
func _heal(alive: Array, caster_name: String, with: String, target_name: String) -> String:
	var caster = null
	var target = null
	for c in alive:
		if c.name == caster_name:
			caster = c
		if c.name == target_name:
			target = c
	if caster == null or target == null:
		return "Nobody was healed (the DM named someone who is not here)."
	var amount := 0
	if with == "potion":
		if caster.items.get("potion-of-healing", 0) < 1:
			return "%s has no healing potion." % caster.name
		caster.items["potion-of-healing"] -= 1
		amount = Game.dice.roll("2d4+2")
	else:
		var sp = Game.srd.t.spells.get(with)
		var slot := 0
		for k in caster.slots:
			if caster.slots[k] > 0 and (slot == 0 or k < slot):
				slot = k
		if sp == null or not sp.has("heal_at_slot_level") or not with in caster.spells or slot == 0:
			return "%s cannot cast that right now (no such spell prepared or no spell slot left)." % caster.name
		caster.slots[slot] -= 1
		amount = Game.dice.roll(sp.heal_at_slot_level[str(slot)].replace("MOD", str(caster.mod(caster.cast_abil)))) \
			+ (2 + slot if "disciple-of-life" in caster.features else 0)
	var before: int = target.hp
	target.hp = min(target.max_hp, target.hp + amount)
	return "%s heals %s for %d hit points." % [caster.name, target.name, target.hp - before]

# Rolls the check the DM asked for. Returns the line shown to the player and sent back to the DM.
func _check(chk: Dictionary) -> Dictionary:
	var alive: Array = Game.party.filter(func(c): return not c.dead)
	var who = alive[0]
	for c in alive:
		if c.name == str(chk.get("character", "")):
			who = c
	var skill := str(chk.get("skill", "perception")).to_lower().replace(" ", "-")
	var ability := "wis"
	if skill in ABILITIES:
		ability = skill
		skill = ""
	elif Game.srd.t.skills.has(skill):
		ability = Game.srd.t.skills[skill].ability_score.index
	else:
		skill = "perception"
	var dc := clampi(int(chk.get("dc", 12)), 5, 25)
	var r: Dictionary = Combat.new(Game.dice, Game.srd).check(who, ability, dc, skill)
	var label := (skill if skill != "" else ability).replace("-", " ").capitalize()
	return {"roll": r.roll, "bonus": r.total - r.roll, "total": r.total, "dc": dc, "success": r.success, "title": "%s: %s Check" % [who.name, label],
		"line": "%s rolls %s: %d + %d = %d against DC %d. %s" % [who.name, label, r.roll, r.total - r.roll, r.total, dc, "Success!" if r.success else "Failure."]}

# Keeps only monsters that exist and trims the fight to something the party can survive.
func _encounter(e):
	if typeof(e) != TYPE_DICTIONARY or typeof(e.get("monsters")) != TYPE_ARRAY:
		return null
	var mons := []
	for m in e.monsters:
		if typeof(m) == TYPE_DICTIONARY and Game.srd.t.monsters.has(str(m.get("index", ""))):
			mons.append({"index": str(m.index), "count": clampi(int(m.get("count", 1)), 1, 6)})
	var cap: int = Prompts.budget() * 3
	var xp_of := func(m): return int(Game.srd.t.monsters[m.index].xp)
	while not mons.is_empty():
		var total := 0
		var heads := 0
		for m in mons:
			total += xp_of.call(m) * m.count
			heads += m.count
		if total <= cap and heads <= 8:
			break
		mons.sort_custom(func(a, b): return xp_of.call(a) * a.count > xp_of.call(b) * b.count)
		mons[0].count -= 1
		if mons[0].count == 0:
			mons.pop_front()
	return {"monsters": mons} if not mons.is_empty() else null
