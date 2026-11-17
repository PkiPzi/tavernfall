extends RefCounted
# The one door to the AI. ask() sends a system prompt and a request and returns
# {"ok": true, "data": <parsed JSON object>} or {"ok": false, "error": text}.
# Default: the Claude Code subscription through `claude -p` (no API key).
# TAVERN_DM=fake answers from a script instead, for tests.

var model := "sonnet"
var fake := OS.get_environment("TAVERN_DM") == "fake"
var fake_turn := 0

func ask(system: String, prompt: String) -> Dictionary:
	if fake:
		await Engine.get_main_loop().create_timer(0.2).timeout
		return {"ok": true, "data": _fake(prompt)}
	var t := Thread.new()
	t.start(_run.bind(system, prompt))
	while t.is_alive():
		await Engine.get_main_loop().process_frame
	return t.wait_to_finish()

func _run(system: String, prompt: String) -> Dictionary:
	# An empty folder of its own, no tools, no settings: a plain text-in, JSON-out call.
	var dir := OS.get_user_data_dir() + "/dm"
	DirAccess.make_dir_recursive_absolute(dir)
	for part in [["system.txt", system], ["prompt.txt", prompt]]:
		var f := FileAccess.open(dir + "/" + part[0], FileAccess.WRITE)
		f.store_string(part[1])
		f.close()  # must be closed before the shell reads it
	var out := []
	var code := OS.execute("sh", ["-c", "cd '%s' && claude -p --system-prompt \"$(cat system.txt)\" --tools '' " % dir \
		+ "--strict-mcp-config --setting-sources '' --disable-slash-commands --no-session-persistence " \
		+ "--output-format json --model '%s' < prompt.txt" % model], out, true)
	var raw: String = out[0] if not out.is_empty() else ""
	var outer = JSON.parse_string(raw)
	if code != 0 or typeof(outer) != TYPE_DICTIONARY or outer.get("is_error", false):
		return {"ok": false, "error": "Claude did not answer (%d): %s" % [code, raw.left(300)]}
	var data = parse_object(str(outer.get("result", "")))
	if data == null:
		return {"ok": false, "error": "The answer was not JSON: " + str(outer.get("result", "")).left(300)}
	return {"ok": true, "data": data}

# The first {...} block in a reply, tolerating code fences or chatter around it.
static func parse_object(text: String):
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		return null
	var v = JSON.parse_string(text.substr(a, b - a + 1))
	return v if typeof(v) == TYPE_DICTIONARY else null

func _fake(prompt: String) -> Dictionary:
	if prompt.begins_with("REQUEST: plan"):
		return {"title": "The Hollow Crypt", "setting": "A border village troubled by the restless dead.",
			"villain": {"name": "Maelis the Pale", "motive": "wants an army of bones"},
			"locations": [{"name": "The Gilded Mug", "description": "A warm tavern.", "template": "tavern", "scene": "market_street"},
				{"name": "Hollow Crypt", "description": "Cold halls under the hill.", "template": "dungeon"}],
			"npcs": [{"name": "Tolla", "role": "innkeeper"}],
			"encounters": [{"location": "Hollow Crypt", "monsters": [{"index": "skeleton", "count": 2}], "trigger": "entering"}],
			"acts": ["Hear of the crypt", "Fight through it", "Face Maelis"],
			"opening": "Rain hammers the shutters of the Gilded Mug as Tolla slides a key across the bar."}
	fake_turn += 1
	var base := {"narration": "", "location": {"name": "The Gilded Mug", "template": "tavern"}, "choices": [], "speaker": {"name": "Tolla", "kind": "gruff innkeeper"},
		"check": null, "encounter": null, "rest": null, "reward": null, "summary": "Fake summary %d." % fake_turn, "ended": false}
	match fake_turn:
		1:
			base.narration = "Tolla leans across the bar and lowers her voice. The road to the old crypt is dark, and the lanterns on it have gone out one by one."
			base.speaker = {"name": "Tolla", "kind": "gruff woman innkeeper", "says": "Lights in the old crypt, three nights running. I'll not send anyone up there, but I won't stop you either."}
			base.choices = [{"text": "Sneak toward the crypt", "skill": "stealth", "dc": 12}, {"text": "Read the wards scratched on her doorframe", "skill": "arcana", "dc": 13, "requires": "arcana"},
				{"text": "Study the faded notice by the door", "requires": "history"}, "Ask around", "Rest first"]
		2:
			base.narration = "You creep along the hedgerow toward the crypt door."
			base.check = {"character": "", "skill": "stealth", "dc": 12, "why": "moving unseen"}
		3:
			base.narration = "Bones rattle in the dark. Two skeletons lurch from their alcoves!"
			base.location = {"name": "Hollow Crypt", "template": "dungeon"}
			base.encounter = {"monsters": [{"index": "skeleton", "count": 2}], "intro": "They attack."}
		4:
			base.narration = "The bones fall still. Among them you find a vial."
			base.location = {"name": "Hollow Crypt", "template": "dungeon"}
			base.reward = {"xp": 260, "items": {"potion-of-healing": 1}}
			base.choices = ["Press on", "Take a short rest"]
		5:
			base.narration = "You bind your wounds in the quiet of the crypt."
			base.location = {"name": "Hollow Crypt", "template": "cave", "scene": "underdark"}
			base.rest = "short"
			base.choices = ["Press on"]
		_:
			base.narration = "Maelis is gone, and dawn finds the village safe. The tale ends here."
			base.ended = true
	return base
