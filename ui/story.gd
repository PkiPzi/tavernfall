extends Node3D
# The story screen: the DM's narration over a diorama of the place, choices, a free-text box.
# The code here rolls the checks, hands out rewards and starts the fights the DM proposes.

const Ui = preload("res://ui/ui.gd")
const Scenery = preload("res://board/scenery.gd")
const Prompts = preload("res://ai/prompts.gd")
const Combat = preload("res://rules/combat.gd")
const ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]

var holder: Node3D
var pivot: Node3D
var torches := []
var template_now := ""
var title_l: Label
var place_l: Label
var text: RichTextLabel
var choices: VBoxContainer
var entry: LineEdit
var think: Label
var party_box: VBoxContainer
var autoplay := OS.get_environment("TAVERN_AUTOPLAY") != ""

func _ready() -> void:
	_build_ui()
	var s: Dictionary = Game.story
	if Game.battle_result != null:
		var r: Dictionary = Game.battle_result
		Game.battle_result = null
		s.scene.erase("encounter")
		if r.won:
			var news: Array = Game.award_xp(r.xp_each)
			news.push_front("Victory! Each hero gains %d XP." % r.xp_each)
			_show()
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

func _process(dt: float) -> void:
	if pivot != null:
		pivot.rotation.y += dt * 0.04
	Scenery.flicker(torches)

# ---- interface --------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var top := Ui.panel()
	top.position = Vector2(16, 16)
	layer.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	title_l = Ui.label("", 24, Ui.GOLD)
	place_l = Ui.label("", 15, Ui.DIM)
	tv.add_child(title_l)
	tv.add_child(place_l)
	tv.add_child(Ui.button("Save and go to menu", func(): Game.save_game(); get_tree().change_scene_to_file(Game.MENU)))

	party_box = VBoxContainer.new()
	party_box.position = Vector2(16, 150)
	party_box.add_theme_constant_override("separation", 8)
	layer.add_child(party_box)

	# The dialogue box: narration, then numbered answers, like a CRPG conversation.
	var bottom := Ui.panel(0.92)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -14
	bottom.custom_minimum_size.x = 880
	layer.add_child(bottom)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	bottom.add_child(v)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size.y = 90
	text.add_theme_font_size_override("normal_font_size", 18)
	text.add_theme_color_override("default_color", Ui.INK)
	v.add_child(text)
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 5)
	v.add_child(choices)
	var row := HBoxContainer.new()
	entry = LineEdit.new()
	entry.placeholder_text = "Or type what the party does..."
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text_submitted.connect(func(t): _act(t))
	row.add_child(entry)
	row.add_child(Ui.button("Do it", func(): _act(entry.text)))
	v.add_child(row)
	think = Ui.label("", 14, Ui.GOLD)
	v.add_child(think)

func _place(loc) -> Dictionary:
	if typeof(loc) != TYPE_DICTIONARY:
		loc = {}
	var t := str(loc.get("template", "dungeon"))
	return {"name": str(loc.get("name", "Somewhere")), "template": t if t in Prompts.TEMPLATES else "dungeon"}

func _diorama(template: String) -> void:
	Game.music("tavern" if template == "tavern" else "explore")
	if template == template_now:
		return
	if template_now != "":
		Game.sfx("door_open_1")
	template_now = template
	if holder != null:
		holder.queue_free()
	holder = Node3D.new()
	add_child(holder)
	var heroes: Array = Game.party.filter(func(c): return not c.dead)
	for i in heroes.size():
		heroes[i].pos = Vector2i(5 + i % 2 * 2, 4 + i / 2 * 2)
	torches = Scenery.build(holder, template, Game.dice.rng, heroes.map(func(c): return c.pos)).torches
	for i in heroes.size():
		var m: Dictionary = Scenery.character(holder, heroes[i], i)
		m.node.rotation.y = 0.5
		m.info.text = heroes[i].name
		m.info.modulate = Color("8fd0ff")
	pivot = Ui.orbit_camera(holder, Vector3(Scenery.W / 2.0, 0, Scenery.H / 2.0))

func _show(notes := []) -> void:
	var s: Dictionary = Game.story
	var sc: Dictionary = s.scene
	title_l.text = s.title
	place_l.text = sc.get("location", {}).get("name", "")
	_diorama(sc.get("location", {}).get("template", "dungeon"))
	Game.sfx("handle_coins" if notes.any(func(n): return "XP" in n or "potion" in n) else "book_flip_1")
	var body := ""
	for n in notes:
		body += "[color=#e8c15a]%s[/color]\n" % n
	text.text = body + str(sc.narration)
	text.visible_ratio = 0.0
	create_tween().tween_property(text, "visible_ratio", 1.0, clampf(str(sc.narration).length() / 220.0, 0.3, 2.5))
	think.text = ""
	for c in choices.get_children():
		c.queue_free()
	var can_type := false
	if sc.get("ended", false):
		choices.add_child(Ui.button("The end. Back to the menu", func(): get_tree().change_scene_to_file(Game.MENU)))
	elif sc.get("defeat", false):
		choices.add_child(Ui.button("Try again from the last save", Game.load_game.bind(s.slot)))
		choices.add_child(Ui.button("Back to the menu", func(): get_tree().change_scene_to_file(Game.MENU)))
	elif sc.has("encounter"):
		var foes: Array = sc.encounter.monsters.map(func(m): return "%d x %s" % [m.count, Game.srd.t.monsters[m.index].name])
		choices.add_child(Ui.button("Begin the fight:  " + ", ".join(foes), func(): Game.start_battle(sc.encounter)))
	else:
		can_type = true
		var n := 0
		for ch in sc.get("choices", []):
			n += 1
			var b := Ui.button("%d.  %s" % [n, ch], _act.bind(str(ch)))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			choices.add_child(b)
		if sc.get("choices", []).is_empty():
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

func _party() -> void:
	for c in party_box.get_children():
		c.queue_free()
	for c in Game.party:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(Ui.hero_card(c, 64))
		var slots: Array = c.slots_max.keys().map(func(k): return "L%d %d/%d" % [k, c.slots.get(k, 0), c.slots_max[k]])
		var potions: int = c.items.get("potion-of-healing", 0)
		var info := Ui.label("%s %s %d\nAC %d   XP %d%s%s%s" % [c.spec.race.capitalize(), c.cls.capitalize(), c.level, c.ac, c.xp,
			"\nSlots " + " ".join(slots) if not slots.is_empty() else "",
			"\nPotions %d" % potions if potions > 0 else "", "\nDead" if c.dead else ""], 12, Ui.DIM)
		row.add_child(info)
		party_box.add_child(row)

# ---- talking to the DM ------------------------------------------------------

func _act(what: String) -> void:
	what = what.strip_edges()
	if what == "" or think.text != "" or not entry.editable:
		return
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
	s.scene = {"narration": str(d.narration), "location": _place(d.get("location")),
		"choices": (d.get("choices") if typeof(d.get("choices")) == TYPE_ARRAY else []).slice(0, 4).map(func(x): return str(x))}
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
		var line := _check(chk)
		_show(notes + [line])
		await get_tree().create_timer(0.4 if autoplay else 2.5).timeout
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
func _check(chk: Dictionary) -> String:
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
	return "%s rolls %s: %d + %d = %d against DC %d. %s" % [who.name, (skill if skill != "" else ability).capitalize(),
		r.roll, r.total - r.roll, r.total, dc, "Success!" if r.success else "Failure."]

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
