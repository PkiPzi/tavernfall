extends Node
# Everything that outlives a scene: the rules data, the party, the story so far, saves.

const Srd = preload("res://rules/srd.gd")
const Dice = preload("res://rules/dice.gd")
const Creature = preload("res://rules/creature.gd")
const Dm = preload("res://ai/dm.gd")

const MENU := "res://ui/menu.tscn"
const STORY := "res://ui/story.tscn"
const BATTLE := "res://board/battle.tscn"

# Sensible starting builds, so making a character is name + race + class.
const PRESETS = {
	"fighter": {"abilities": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"armor": "chain-mail", "shield": true, "weapons": ["longsword", "crossbow-light"], "style": "defense",
		"skills": ["athletics", "perception"], "items": {"potion-of-healing": 1}},
	"rogue": {"abilities": {"str": 8, "dex": 15, "con": 13, "int": 12, "wis": 10, "cha": 14},
		"armor": "leather-armor", "weapons": ["rapier", "shortbow"],
		"skills": ["stealth", "sleight-of-hand", "perception", "deception"], "expertise": ["stealth", "sleight-of-hand"],
		"items": {"potion-of-healing": 1}},
	"cleric": {"abilities": {"str": 13, "dex": 8, "con": 14, "int": 10, "wis": 15, "cha": 12},
		"armor": "scale-mail", "shield": true, "weapons": ["mace"], "skills": ["medicine", "insight"],
		"spells": ["sacred-flame", "cure-wounds", "healing-word", "guiding-bolt", "bless", "shield-of-faith"]},
	"wizard": {"abilities": {"str": 8, "dex": 14, "con": 13, "int": 15, "wis": 12, "cha": 10},
		"weapons": ["dagger"], "skills": ["arcana", "investigation"],
		"spells": ["fire-bolt", "ray-of-frost", "magic-missile", "burning-hands", "sleep", "mage-armor"]},
	"barbarian": {"abilities": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"weapons": ["greataxe", "javelin"], "skills": ["athletics", "survival"], "items": {"potion-of-healing": 1}},
	"bard": {"abilities": {"str": 8, "dex": 14, "con": 13, "int": 10, "wis": 12, "cha": 15},
		"armor": "leather-armor", "weapons": ["rapier", "crossbow-hand"], "skills": ["persuasion", "performance", "deception"],
		"spells": ["vicious-mockery", "healing-word", "thunderwave", "sleep"]},
	"druid": {"abilities": {"str": 10, "dex": 13, "con": 14, "int": 8, "wis": 15, "cha": 12},
		"armor": "leather-armor", "shield": true, "weapons": ["scimitar"], "skills": ["nature", "animal-handling"],
		"spells": ["produce-flame", "poison-spray", "cure-wounds", "healing-word", "thunderwave"]},
	"monk": {"abilities": {"str": 12, "dex": 15, "con": 13, "int": 8, "wis": 14, "cha": 10},
		"weapons": ["quarterstaff", "dart"], "skills": ["acrobatics", "stealth"], "items": {"potion-of-healing": 1}},
	"paladin": {"abilities": {"str": 15, "dex": 8, "con": 13, "int": 10, "wis": 12, "cha": 14},
		"armor": "chain-mail", "shield": true, "weapons": ["longsword", "javelin"], "style": "defense",
		"skills": ["athletics", "persuasion"], "spells": []},
	"ranger": {"abilities": {"str": 12, "dex": 15, "con": 13, "int": 8, "wis": 14, "cha": 10},
		"armor": "studded-leather-armor", "weapons": ["longbow", "shortsword"], "style": "archery",
		"skills": ["survival", "perception", "stealth"], "spells": [], "items": {"potion-of-healing": 1}},
	"sorcerer": {"abilities": {"str": 8, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 15},
		"weapons": ["dagger"], "skills": ["arcana", "persuasion"],
		"spells": ["fire-bolt", "ray-of-frost", "shocking-grasp", "magic-missile", "burning-hands"]},
	"warlock": {"abilities": {"str": 8, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 15},
		"armor": "leather-armor", "weapons": ["dagger"], "skills": ["arcana", "intimidation"],
		"spells": ["eldritch-blast", "chill-touch", "burning-hands"]},
}
# Spells a caster picks up when reaching a level. Only spells the rules engine can resolve.
const LEVEL_SPELLS = {
	"cleric": {3: ["hold-person", "spiritual-weapon"], 5: ["mass-healing-word"]},
	"wizard": {2: ["thunderwave"], 3: ["shatter", "hold-person"], 4: ["scorching-ray"], 5: ["fireball"]},
	"bard": {2: ["cure-wounds"], 3: ["hold-person", "shatter"]},
	"druid": {3: ["moonbeam", "hold-person"], 5: ["call-lightning"]},
	"paladin": {2: ["bless", "cure-wounds", "shield-of-faith"]},
	"ranger": {2: ["hunters-mark", "cure-wounds"]},
	"sorcerer": {2: ["sleep"], 3: ["scorching-ray"], 4: ["shatter"], 5: ["fireball"]},
	"warlock": {3: ["hold-person", "scorching-ray"], 4: ["shatter"], 5: ["fireball"]},
}

var srd
var dice
var dm
var party := []
var story := {}        # {title, plan, summary, turns, scene, slot}; empty outside an adventure
var encounter = null   # {monsters: [{index, count}], template} for the next battle
var battle_result = null

func _ready() -> void:
	srd = Srd.new()
	dice = Dice.new()
	dm = Dm.new()
	settings.load(SETTINGS)
	sound_on = settings.get_value("sound", "on", true) and OS.get_environment("TAVERN_MUTE") == ""
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -16
	add_child(music_player)
	var shot := OS.get_environment("TAVERN_SHOT")
	if shot != "":
		await get_tree().create_timer(float(OS.get_environment("TAVERN_SHOT_AT"))).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()

func make_hero(hero_name: String, race: String, cls: String, gender := "woman", look := "", seed := 1):
	var spec: Dictionary = PRESETS[cls].duplicate(true)
	spec.merge({"name": hero_name, "race": race, "class": cls, "level": 1, "gender": gender, "look": look, "seed": seed})
	return Creature.make_pc(srd, spec)

# ---- sound ------------------------------------------------------------------

const SETTINGS := "user://settings.cfg"
var settings := ConfigFile.new()
var sound_on := true
var music_player: AudioStreamPlayer
var music_now := ""

func sfx(id: String, vary := 0.08) -> void:
	if not sound_on:
		return
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/sfx/%s.ogg" % id)
	p.pitch_scale = randf_range(1.0 - vary, 1.0 + vary)
	p.volume_db = -6
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

# track: tavern, explore or battle. Keeps playing across scenes when the track does not change.
func music(track: String) -> void:
	if track != music_now:
		music_now = track
		var st: AudioStreamOggVorbis = load("res://assets/audio/music/%s.ogg" % track)
		st.loop = true
		music_player.stream = st
	if sound_on and not music_player.playing:
		music_player.play()

func set_sound(on: bool) -> void:
	sound_on = on
	settings.set_value("sound", "on", on)
	settings.save(SETTINGS)
	if on and music_now != "":
		music_player.play()
	else:
		music_player.stop()

func demo_party() -> Array:
	return [make_hero("Brakka", "human", "fighter", "man", "scarred, short beard"),
		make_hero("Sly", "halfling", "rogue", "man", "sharp grin, curly hair"),
		make_hero("Odessa", "dwarf", "cleric", "woman", "red braids, kind eyes"),
		make_hero("Wren", "elf", "wizard", "woman", "silver hair, thoughtful")]

# Gives xp to everyone alive; returns lines about level-ups for the story screen.
func award_xp(amount: int) -> Array:
	var news := []
	for c in party:
		if c.dead:
			continue
		if c.gain_xp(srd, amount) > 0:
			learn(c)
			news.append("%s reaches level %d!" % [c.name, c.level])
	if not news.is_empty():
		sfx("power_up_3")
	return news

# Adds the spells the hero's class gets up to its level.
func learn(c) -> void:
	for lv in LEVEL_SPELLS.get(c.cls, {}):
		if lv <= c.level:
			for sp in LEVEL_SPELLS[c.cls][lv]:
				if not sp in c.spec.spells:
					c.spec.spells.append(sp)
	c.derive(srd)

func start_battle(enc: Dictionary) -> void:
	encounter = enc
	battle_result = null
	get_tree().change_scene_to_file(BATTLE)

func after_battle() -> void:
	for c in party:  # the fight is over: get the fallen back on their feet, barely
		c.conditions = []
		c.conc = ""
		c.death_s = 0
		c.death_f = 0
		if not c.dead and c.hp == 0:
			c.hp = 1
	get_tree().change_scene_to_file(STORY if not story.is_empty() else BATTLE)

# ---- pictures ---------------------------------------------------------------
# shortcut: Pollinations only (free, no key). Cloudflare Workers AI goes in front once a key exists.

var textures := {}  # file path -> texture
var loading := {}   # file path -> true while a download is running
var net_busy := false
var net_next := 0   # earliest time (ms) the next download may start
var failed := {}    # file path -> time (ms) before which we do not retry

# A generated picture, cached on disk under user://art. Null when the service is unreachable.
func picture(prompt: String, w := 384, h := 480, seed := 1) -> Texture2D:
	var path := "user://art/%s.jpg" % ("%s|%d|%d|%d" % [prompt, w, h, seed]).md5_text()
	while loading.has(path):  # someone else is already fetching this one
		await get_tree().process_frame
	if textures.has(path):
		return textures[path]
	if not FileAccess.file_exists(path):
		if OS.get_environment("TAVERN_ART") == "off" or failed.get(path, 0) > Time.get_ticks_msec():
			return null
		loading[path] = true
		var img := Image.new()
		var ok := false
		for attempt in 4:
			# The free tier allows one picture every 45 seconds, so downloads queue up and trickle in.
			while net_busy or Time.get_ticks_msec() < net_next:
				await get_tree().process_frame
			net_busy = true
			var http := HTTPRequest.new()
			http.timeout = 90
			add_child(http)
			var code := 0
			# asks for a taller picture and cuts the bottom strip, where the service puts its mark
			if http.request("https://image.pollinations.ai/prompt/%s?width=%d&height=%d&nologo=true&seed=%d" % [
					prompt.uri_encode(), w, h + 48, seed]) == OK:
				var res: Array = await http.request_completed
				code = res[1]
				ok = res[0] == HTTPRequest.RESULT_SUCCESS and code == 200 \
					and (img.load_jpg_from_buffer(res[3]) == OK or img.load_png_from_buffer(res[3]) == OK)
			http.queue_free()
			net_next = Time.get_ticks_msec() + 47000
			net_busy = false
			if ok or code != 402:  # 402 = asked too soon, wait and try again
				break
		loading.erase(path)
		if not ok:
			failed[path] = Time.get_ticks_msec() + 300000
			return null
		img.crop(w, h)
		DirAccess.make_dir_recursive_absolute("user://art")
		img.save_jpg(path, 0.9)
	textures[path] = ImageTexture.create_from_image(Image.load_from_file(path))
	return textures[path]

const STYLE := "fantasy character portrait, oil painting, dramatic rim lighting, detailed face, head and shoulders, dark moody background"
const CLASS_LOOK = {"fighter": "plate armor, sword", "rogue": "dark leather hood, daggers",
	"cleric": "scale armor, holy symbol", "wizard": "embroidered robes, staff, arcane glow",
	"barbarian": "furs, war paint, great axe", "bard": "colourful doublet, lute", "druid": "leaf cloak, antlers, wooden staff",
	"monk": "simple robes, shaved head", "paladin": "shining plate armor, holy sword", "ranger": "green hooded cloak, longbow",
	"sorcerer": "flowing robes, crackling magic in the hands", "warlock": "dark robes, eerie glowing eyes"}

func portrait(c) -> Texture2D:
	if c.is_pc:
		return await picture("%s %s %s, %s, %s, %s" % [c.spec.get("gender", ""), c.spec.race, c.cls,
			c.spec.get("look", ""), CLASS_LOOK[c.cls], STYLE], 384, 480, c.spec.get("seed", 1))
	var kind: String = c.name.rstrip(" 0123456789")
	return await picture("%s, menacing monster, dark fantasy creature portrait, oil painting, dramatic lighting, dark background" % kind)

# ---- saves ------------------------------------------------------------------

# TAVERN_SAVES points test runs at a folder of their own, away from the player's saves.
var saves_dir := OS.get_environment("TAVERN_SAVES") if OS.get_environment("TAVERN_SAVES") != "" else "user://saves"

func slot_path(n: int) -> String:
	return "%s/slot%d.json" % [saves_dir, n]

func save_game() -> void:
	if story.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(saves_dir)
	var f := FileAccess.open(slot_path(story.slot), FileAccess.WRITE)
	f.store_string(JSON.stringify({"story": story, "party": party.map(func(c): return c.to_dict()),
		"saved": Time.get_datetime_string_from_system(false, true)}, "  "))
	f.close()

# One line per slot for the menu: "" when empty.
func slot_summary(n: int) -> String:
	var d = _read(n)
	if d == null:
		return ""
	return "%s  (%s)  %s" % [d.story.title, ", ".join(d.party.map(func(p): return "%s %d" % [p.spec.name, p.spec.level])), d.saved]

func _read(n: int):
	if not FileAccess.file_exists(slot_path(n)):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(slot_path(n)))
	return ints(d) if typeof(d) == TYPE_DICTIONARY else null

func load_game(n: int) -> bool:
	var d = _read(n)
	if d == null:
		return false
	story = d.story
	party = d.party.map(func(p): return Creature.from_dict(srd, p))
	encounter = null
	battle_result = null
	get_tree().change_scene_to_file(STORY)
	return true

# JSON has no integers; put them back so levels and hit points stay whole numbers.
static func ints(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_ARRAY:
			return v.map(func(x): return ints(x))
		TYPE_DICTIONARY:
			for k in v:
				v[k] = ints(v[k])
	return v
