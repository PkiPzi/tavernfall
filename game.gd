extends Node
# Everything that outlives a scene: the rules data, the party, the story so far, saves.

const Srd = preload("res://rules/srd.gd")
const Dice = preload("res://rules/dice.gd")
const Creature = preload("res://rules/creature.gd")
const Dm = preload("res://ai/dm.gd")
const Scenery = preload("res://board/scenery.gd")
const Bust = preload("res://board/bust.gd")
const Portraits = preload("res://ui/portraits.gd")

const MENU := "res://ui/menu.tscn"
const STORY := "res://ui/story.tscn"
const BATTLE := "res://board/battle.tscn"
const Assemble = preload("res://board/assemble.gd")

# Sensible starting builds, so making a character is name + race + class.
const PRESETS = {
	"fighter": {"abilities": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"armor": "chain-mail", "shield": true, "weapons": ["longsword", "crossbow-light"], "style": "defense",
		"skills": ["athletics", "perception"], "items": {"potion-of-healing": 1}},
	"rogue": {"abilities": {"str": 8, "dex": 15, "con": 13, "int": 12, "wis": 10, "cha": 14},
		"armor": "leather-armor", "weapons": ["shortsword", "dagger", "shortbow"],
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
	"wizard": {2: ["thunderwave"], 3: ["shatter", "hold-person", "web"], 4: ["scorching-ray", "blur"], 5: ["fireball", "fear"], 6: ["lightning-bolt"], 7: ["ice-storm"]},
	"bard": {2: ["cure-wounds"], 3: ["hold-person", "shatter", "invisibility"], 5: ["fear"]},
	"druid": {2: ["entangle", "faerie-fire"], 3: ["moonbeam", "hold-person"], 5: ["call-lightning"]},
	"paladin": {2: ["bless", "cure-wounds", "shield-of-faith"]},
	"ranger": {2: ["hunters-mark", "cure-wounds"]},
	"sorcerer": {2: ["sleep"], 3: ["scorching-ray", "web"], 4: ["shatter", "blur"], 5: ["fireball", "fear"], 6: ["lightning-bolt"], 7: ["ice-storm"]},
	"warlock": {3: ["hold-person", "scorching-ray"], 4: ["shatter", "invisibility"], 5: ["fireball", "fear"]},
}

var srd
var dice
var dm
var party := []
var story := {}        # {title, plan, summary, turns, scene, slot}; empty outside an adventure
var encounter = null   # {monsters: [{index, count}], template} for the next battle
var battle_result = null

func _ready() -> void:
	var ui_theme: Theme = load("res://ui/ui.gd").make_theme()  # every screen gets the BG3-style look (loaded late: ui.gd uses Game)
	get_tree().root.theme = ui_theme
	get_tree().node_added.connect(func(n: Node):  # controls under a CanvasLayer do not inherit from the window
		if n is Control and n.get_parent() is CanvasLayer:
			(n as Control).theme = ui_theme)
	_fit_resolution()
	get_tree().root.size_changed.connect(_fit_resolution)
	srd = Srd.new()
	dice = Dice.new()
	dm = Dm.new()
	settings.load(SETTINGS)
	quality = int(settings.get_value("video", "quality", 1))
	_fit_resolution()
	sound_on = settings.get_value("sound", "on", true) and OS.get_environment("TAVERN_MUTE") == ""
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -16
	add_child(music_player)
	speech = load("res://ui/voice.gd").new()
	speech.on = settings.get_value("sound", "voice", true) and (OS.get_environment("TAVERN_MUTE") == "" or OS.get_environment("TAVERN_VOICE_TEST") != "") and OS.get_environment("TAVERN_NOVOICE") == ""
	add_child(speech)
	var shot := OS.get_environment("TAVERN_SHOT")
	if shot != "":
		await get_tree().create_timer(float(OS.get_environment("TAVERN_SHOT_AT"))).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()

# extra: what the player chose in the creator over the class preset (hair, hair_color, beard, abilities, skills, expertise, style, spells).
func make_hero(hero_name: String, race: String, cls: String, gender := "woman", look := "", seed := 1, variant := 0, extra := {}):
	var spec: Dictionary = PRESETS[cls].duplicate(true)
	spec.merge({"name": hero_name, "race": race, "class": cls, "level": 1, "gender": gender, "look": look, "seed": seed, "variant": variant})
	spec.merge(extra.duplicate(true), true)
	return Creature.make_pc(srd, spec)

# ---- sound ------------------------------------------------------------------

const SETTINGS := "user://settings.cfg"
var settings := ConfigFile.new()
var sound_on := true
var music_player: AudioStreamPlayer
var speech: Node   # ui/voice.gd: speaks the story
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

# The 3D scene is drawn at a lower resolution on big screens and scaled up with FSR; the interface stays sharp at full size.
# A 4K display gave 19 frames a second on the GTX 1650 before this.
const QUALITY_NAMES = ["Fast", "Balanced", "Sharp"]
var quality := 1   # 0 fast, 1 balanced (the default), 2 sharp: how large the 3D picture is drawn before it is scaled up

func set_quality(q: int) -> void:
	quality = posmod(q, 3)
	settings.set_value("video", "quality", quality)
	settings.save(SETTINGS)
	_fit_resolution()

func _fit_resolution() -> void:
	var w := get_tree().root.size.x
	var auto := 1.0 if w <= 2000 else (0.75 if w <= 2800 else 0.667)  # about 1440p inside a 4K window
	get_tree().root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	get_tree().root.fsr_sharpness = 0.2  # lower is sharper
	get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA  # smooths edges cheaply (MSAA is off)
	get_tree().root.scaling_3d_scale = clampf(auto * [0.75, 1.0, 1.3][quality], 0.4, 1.0)

# BG3 sounds (assets/bg3/audio/<event>_<n>.ogg, exported by tools/bg3/audio.sh): plays one of the event's recordings
# and returns true, or returns false when none is exported so the caller can fall back to a bundled sound.
var _bg3_sounds := {}

func bg3(event: String, vary := 0.05, db := -4.0) -> bool:
	if not sound_on:
		return true
	if not _bg3_sounds.has(event):
		var list := []
		while ResourceLoader.exists("res://assets/bg3/audio/%s_%d.ogg" % [event, list.size()]):
			list.append(load("res://assets/bg3/audio/%s_%d.ogg" % [event, list.size()]))
		_bg3_sounds[event] = list
	var list: Array = _bg3_sounds[event]
	if list.is_empty():
		return false
	var p := AudioStreamPlayer.new()
	p.stream = list[randi() % list.size()]
	p.pitch_scale = randf_range(1.0 - vary, 1.0 + vary)
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return true

# A BG3 sound, or the bundled one when that is not on this machine.
func sound(event: String, fallback: String, vary := 0.05, db := -4.0) -> void:
	if not bg3(event, vary, db):
		sfx(fallback)

# Pain and death voices by creature (SRD index words), as BG3 event names.
const VOICES = {"hobgoblin": ["HobGoblin_Pain", "HobGoblin_Death"], "goblin": ["Goblin_Voice_Male_Pain", "Goblin_Voice_Male_Death"],
	"skeleton": ["Skeleton_Pain", "Skeleton_Death"], "zombie": ["Zombie_Pain", "Zombie_Death"], "ghoul": ["Ghoul_Pain", "Ghoul_Death"],
	"wolf": ["Wolf_Pain_Generic", "Wolf_Death_Generic"], "worg": ["Wolf_Pain_Generic", "Wolf_Death_Generic"], "dog": ["Wolf_Pain_Generic", "Wolf_Death_Generic"],
	"jackal": ["Wolf_Pain_Generic", "Wolf_Death_Generic"], "bear": ["Bear_Pain_Generic", "Bear_Death_Generic"], "ogre": ["Ogre_Voice_Pain", "Ogre_Voice_Death"],
	"owlbear": ["Owlbear_Pain", "Owlbear_Death"], "gnoll": ["Gnoll_Pain", "Gnoll_Death"], "kobold": ["Kobold_Voice_Pain", "Kobold_Voice_Death"],
	"rat": ["Rat_Pain", "Rat_Death"], "spider": ["Spider_Giant_Pain", "Spider_Giant_Death"], "bugbear": ["BugBear_Pain", "BugBear_Death"],
	"minotaur": ["Minotaur_Pain", "Minotaur_Death"], "harpy": ["Harpy_Pain", "Harpy_Death"]}

# kind 0 = pain, 1 = death. Heroes and unlisted creatures stay silent (no voice).
func voice(c, kind: int) -> void:
	if c.is_pc:
		return
	for k in VOICES:
		if k in str(c.index):
			bg3(VOICES[k][kind], 0.06, -2.0)
			return

# Ambience: looping BG3 beds under the music (a tavern's murmur, forest, cave drip, a fire's crackle), one player per layer.
# layers: [[event, volume_db], ...]; the same layers again do nothing; an empty list fades everything out.
const AMBIENCE = {"tavern": [["Amb_SV_CTY_ElfsongTavern", -12.0], ["Amb_PS_Fire_Torch_Medium_Loop_MO", -22.0]],
	"forest": [["Amb_SV_Forest_QD", -13.0]], "road": [["Amb_SV_Forest_Dense_QD", -15.0]], "forest_night": [["Amb_SV_SCL_Dark_Forest", -12.0], ["Amb_PS_Insects_Night_Crickets_Loop_ST", -20.0], ["Amb_PS_Fire_Campfire_Loop_MO", -18.0]],
	"cave": [["Amb_SV_OwlbearCave_QD", -12.0], ["Amb_PS_Fire_Campfire_Loop_MO", -22.0]], "dungeon": [["Amb_PS_Dungeon_Water_Drip_Loop", -12.0], ["Amb_PS_Fire_Torch_Medium_Loop_MO", -22.0]]}
var _amb_players := {}
var _amb_now := ""

func ambience_for(template: String, mood := "") -> void:
	var key := "forest_night" if template in ["forest", "road"] and mood == "night" else template
	if key == _amb_now:
		return
	_amb_now = key
	var layers: Array = AMBIENCE.get(key, [])
	var wanted := {}
	for l in layers:
		wanted[l[0]] = l[1]
	for ev in _amb_players.keys():  # fade out what is no longer wanted
		if not wanted.has(ev):
			var old: AudioStreamPlayer = _amb_players[ev]
			_amb_players.erase(ev)
			var tw := old.create_tween()
			tw.tween_property(old, "volume_db", -60.0, 1.5)
			tw.tween_callback(old.queue_free)
	if not sound_on:
		return
	for ev in wanted:
		if _amb_players.has(ev):
			continue
		var beds: Array = []  # the long recordings of the event are the bed; the short ones are one-shots
		var i := 0
		while ResourceLoader.exists("res://assets/bg3/audio/%s_%d.ogg" % [ev, i]):
			var st: AudioStreamOggVorbis = load("res://assets/bg3/audio/%s_%d.ogg" % [ev, i])
			if st.get_length() >= 8.0:
				beds.append(st)
			i += 1
		if beds.is_empty():
			continue
		var bed: AudioStreamOggVorbis = beds[randi() % beds.size()].duplicate()
		bed.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = bed
		p.volume_db = -60.0
		add_child(p)
		p.play(randf() * minf(bed.get_length(), 20.0))
		p.create_tween().tween_property(p, "volume_db", wanted[ev], 2.0)
		_amb_players[ev] = p

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

var levelups: Array = []  # who gained a level in the last award_xp, for the level-up screen

# Gives xp to everyone alive; returns lines about level-ups for the story screen.
func award_xp(amount: int) -> Array:
	var news := []
	levelups = []
	for c in party:
		if c.dead:
			continue
		var was := {"level": c.level, "hp": c.max_hp, "features": c.features.duplicate(), "spells": c.spells.duplicate()}
		if c.gain_xp(srd, amount) > 0:
			learn(c)
			news.append("%s reaches level %d!" % [c.name, c.level])
			levelups.append({"c": c, "from": was.level, "to": c.level, "hp": c.max_hp - was.hp,
				"features": c.features.filter(func(f): return not f in was.features), "spells": c.spells.filter(func(sp): return not sp in was.spells)})
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

# Changes scene behind one of the game's own loading screens, so the heavy load of a battle never shows as a hitch.
# kind picks the artwork: "dark" (dungeon, cave), "wild" (forest, road), "town" (tavern, menu).
const LOADING_ART = {"dark": [3, 7, 8, 10, 11], "wild": [1, 6, 9, 12], "town": [2, 4, 16]}
const TIPS = ["A natural 20 on an attack is always a hit, and the damage dice are doubled.", "Disengage before you walk away from a foe, or it gets a free attack.",
	"Advantage means rolling two d20s and keeping the higher.", "Hold a doorway: only one foe at a time can reach you.",
	"A hidden attacker has advantage on its first strike.", "Help gives an ally advantage on their next attack.",
	"Concentration breaks when you are hurt and fail a Constitution save.", "Rage resists weapon damage, but you cannot cast while raging."]
var changing := false

func go(scene: String, kind := "dark") -> void:
	if changing:
		return
	changing = true
	if scene == MENU:
		ambience_for("")
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var art: Array = LOADING_ART.get(kind, LOADING_ART.dark)
	var f := "res://assets/bg3/ui/loadingscreen/loadscreen_bgartwork_%d.png" % art[randi() % art.size()]
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.modulate.a = 0.0
	layer.add_child(root)
	var black := ColorRect.new()
	black.color = Color("0a0807")
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)
	if ResourceLoader.exists(f):
		var pic := TextureRect.new()
		pic.texture = load(f)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(pic)
	var ui = load("res://ui/ui.gd")
	var tip: Label = ui.label(TIPS[randi() % TIPS.size()], 18, Color("e6dcc4"))
	tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip.offset_bottom = -70
	tip.add_theme_font_override("font", ui.ITALIC_FONT)
	tip.add_theme_color_override("font_outline_color", Color.BLACK)
	tip.add_theme_constant_override("outline_size", 8)
	root.add_child(tip)
	var load_l: Label = ui.title("Loading", 22)
	load_l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	load_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	load_l.offset_bottom = -30
	root.add_child(load_l)
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.35)
	await tw.finished
	await get_tree().process_frame
	_warm_portraits()  # the busts render while the picture covers the screen
	get_tree().change_scene_to_file(scene)
	await get_tree().create_timer(1.2).timeout  # long enough for the next scene to build behind the picture
	var out := root.create_tween()
	out.tween_property(root, "modulate:a", 0.0, 0.5)
	await out.finished
	layer.queue_free()
	changing = false

# Starts the portrait renders of the party and of the foes of the coming fight.
func _warm_portraits() -> void:
	for c in party:
		portrait(c)
	if encounter != null:
		for m in encounter.get("monsters", []):
			var stem: String = Scenery.monster_stem({"index": m.index, "kind": srd.t.monsters[m.index].type})
			if stem != "":
				bust_of("res://assets/bg3/models/%s.glb" % stem)

func start_battle(enc: Dictionary) -> void:
	encounter = enc
	battle_result = null
	go(BATTLE, {"forest": "wild", "road": "wild", "tavern": "town"}.get(enc.get("template", "dungeon"), "dark"))

func after_battle() -> void:
	for c in party:  # the fight is over: get the fallen back on their feet, barely
		c.conditions = []
		c.conc = ""
		c.death_s = 0
		c.death_f = 0
		if not c.dead and c.hp == 0:
			c.hp = 1
	go(STORY if not story.is_empty() else BATTLE, "town")

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

# A portrait rendered straight from a model file (people the story introduces).
func bust_of(path: String) -> Texture2D:
	return await Bust.render(self, path)

# A portrait of an assembled person (a hero, or a story character) from its spec.
func bust_spec(sp: Dictionary) -> Texture2D:
	var key := "pc|" + JSON.stringify([sp.race, sp.sex, sp.cls, sp.look, sp.hair, sp.beard, sp.hair_color.to_html()])
	return await Bust.render(self, key, func(): return Assemble.character(sp))

func portrait(c) -> Texture2D:
	if c.is_pc and Assemble.available():  # a picture of this very hero: their race, hair, beard and outfit
		var sp: Dictionary = Assemble.spec_of(c)
		var key := "pc|" + JSON.stringify([sp.race, sp.sex, sp.cls, sp.look, sp.hair, sp.beard, sp.hair_color.to_html()])
		var mine: Texture2D = await Bust.render(self, key, func(): return Assemble.character(sp))
		if mine != null:
			return mine
	var face: String = Portraits.pick(c)  # BG3's own generic portrait for this kind of creature
	if face != "":
		return load(face)
	var path: String = Scenery.model_path(c)
	if path != "":  # a render of the BG3 model, made on this machine
		var bust: Texture2D = await Bust.render(self, path)
		if bust != null:
			return bust
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
	go(STORY, "town")
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
