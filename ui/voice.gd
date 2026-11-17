extends Node
# Spoken story. The Dungeon Master's narration is read by a narrator, and what a character says is read in a voice picked
# for that character. Speech comes from Kokoro running on the CPU in a worker process (tools/tts/speak.py); nothing goes
# online. A sentence is made while the one before it plays, so talking starts after about a second.
# Skip (Space, or the button on the story screen) stops it and shows the whole text.

signal sentence_started(line: int, from_char: int, to_char: int, seconds: float)
signal finished

const NARRATOR = "bm_george"
const FEMALE = ["af_bella", "af_nicole", "af_sarah", "af_sky", "af_nova", "af_river", "af_jessica", "af_heart", "af_kore", "bf_emma", "bf_isabella", "bf_alice", "bf_lily", "af_alloy", "af_aoede"]
const MALE = ["am_adam", "am_michael", "am_eric", "am_liam", "am_fenrir", "am_echo", "am_puck", "bm_daniel", "bm_lewis", "bm_fable"]
const DEEP = ["am_onyx", "bm_lewis", "am_fenrir", "bm_george"]
const HIGH = ["am_puck", "af_sky", "af_nova", "af_bella"]

var on := true               # the player's setting (menu and pause screen)
var playing := false
var _proc := {}              # execute_with_pipe result
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _thread: Thread
var _jobs := []              # {text, voice, speed, out}
var _results := {}           # out path -> true when the file is ready
var _quit := false
var _gen := 0                # bumped by skip() so late answers are ignored
var _player: AudioStreamPlayer
var _sentences := []         # [{line, from, to, text, voice, speed, path}]
var _next := 0
var _line_offsets := []

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_play_next)

func _exit_tree() -> void:
	_quit = true
	_sem.post()
	if _thread != null:
		_thread.wait_to_finish()
	if not _proc.is_empty():
		OS.kill(_proc.pid)

static func root_dir() -> String:
	return ProjectSettings.globalize_path("res://tools/tts")

func available() -> bool:
	return FileAccess.file_exists(root_dir() + "/.venv/bin/python") and FileAccess.file_exists(root_dir() + "/models/kokoro-v1.0.int8.onnx")

func _start() -> bool:
	if not _proc.is_empty():
		return OS.is_process_running(_proc.pid)
	if not available():
		return false
	_proc = OS.execute_with_pipe("nice", ["-n", "10", root_dir() + "/.venv/bin/python", root_dir() + "/speak.py"])
	if _proc.is_empty():
		return false
	_thread = Thread.new()
	_thread.start(_work)
	return true

# Runs in the thread: one request at a time to the worker, then marks the file ready.
func _work() -> void:
	var io: FileAccess = _proc.stdio
	io.get_line()  # "ready" once the model is loaded
	while not _quit:
		_sem.wait()
		if _quit:
			return
		_mutex.lock()
		var job = _jobs.pop_front() if not _jobs.is_empty() else null
		_mutex.unlock()
		if job == null:
			continue
		if not FileAccess.file_exists(job.out):
			io.store_line(JSON.stringify({"text": job.text, "voice": job.voice, "speed": job.speed, "out": job.out}))
			io.flush()
			io.get_line()
		_mutex.lock()
		_results[job.out] = true
		_mutex.unlock()

func _ask(text: String, voice: String, speed: float) -> String:
	var dir := "user://voice"
	DirAccess.make_dir_recursive_absolute(dir)
	var out := ProjectSettings.globalize_path("%s/%s.wav" % [dir, ("%s|%s|%.2f" % [voice, text, speed]).md5_text()])
	_mutex.lock()
	_results.erase(out)
	_jobs.append({"text": text, "voice": voice, "speed": speed, "out": out})
	_mutex.unlock()
	_sem.post()
	return out

# The voice for a person: same name, same voice, every time. kind is words like "old bearded priest" or "goblin scout".
static func voice_for(name_: String, kind := "") -> String:
	var k := (name_ + " " + kind).to_lower()
	var h := absi(name_.to_lower().hash())
	var female := false
	for w in ["woman", "girl", "she ", "lady", "queen", "witch", "priestess", "maid", "mother", "wife", "daughter", "sister", "duchess", "matron", "hag", "female"]:
		if w in k + " ":
			female = true
	if not female:
		for w in ["man", "boy", "king", "lord", "father", "brother", "son", "priest", "guard", "soldier", "knight", "male", "old", "goblin", "ogre", "orc"]:
			if w in k:
				break
	var pool: Array = FEMALE if female else MALE
	for w in ["ogre", "orc", "troll", "giant", "bugbear", "undead", "skeleton", "zombie", "dragon", "old", "ancient", "elder"]:
		if w in k:
			return DEEP[h % DEEP.size()] if not female else FEMALE[h % 3 + 6]
	for w in ["goblin", "imp", "kobold", "child", "boy", "girl", "sprite", "rat"]:
		if w in k:
			return HIGH[h % HIGH.size()]
	return pool[h % pool.size()]

# lines: [{"text": "...", "voice": "bm_george", "speed": 1.0}]. Returns at once; watch sentence_started and finished.
func play(lines: Array) -> void:
	skip()
	if not on or lines.is_empty() or not _start():
		finished.emit()
		return
	playing = true
	_sentences = []
	_next = 0
	var gen := _gen
	for li in lines.size():
		var text: String = str(lines[li].text)
		var re := RegEx.new()
		re.compile("[^.!?…]+[.!?…]+[\"')\\]]*\\s*|[^.!?…]+$")
		for m in re.search_all(text):
			var s := m.get_string().strip_edges()
			if s.length() < 2:
				continue
			_sentences.append({"line": li, "from": m.get_start(), "to": m.get_end(), "text": s, "voice": lines[li].get("voice", NARRATOR), "speed": lines[li].get("speed", 1.0), "path": ""})
	for i in mini(2, _sentences.size()):  # start the first two now, the rest as playing goes on
		_sentences[i].path = _ask(_sentences[i].text, _sentences[i].voice, _sentences[i].speed)
	_wait_and_play(gen)

func _ready_file(path: String) -> bool:
	_mutex.lock()
	var ok: bool = _results.has(path)
	_mutex.unlock()
	return ok

func _wait_and_play(gen: int) -> void:
	if _next >= _sentences.size():
		playing = false
		finished.emit()
		return
	var s: Dictionary = _sentences[_next]
	if s.path == "":
		s.path = _ask(s.text, s.voice, s.speed)
	while not _ready_file(s.path):
		await get_tree().create_timer(0.05).timeout
		if gen != _gen:
			return
	if gen != _gen:
		return
	var wav := AudioStreamWAV.load_from_file(s.path)
	if wav == null:
		_next += 1
		_wait_and_play(gen)
		return
	_player.stream = wav
	_player.play()
	sentence_started.emit(s.line, s.from, s.to, wav.get_length())
	_next += 1
	if _next + 1 < _sentences.size() and _sentences[_next + 1].path == "":  # prepare one sentence ahead
		_sentences[_next + 1].path = _ask(_sentences[_next + 1].text, _sentences[_next + 1].voice, _sentences[_next + 1].speed)

func _play_next() -> void:
	if playing:
		_wait_and_play(_gen)

func skip() -> void:
	_gen += 1
	_player.stop()
	_mutex.lock()
	_jobs.clear()
	_mutex.unlock()
	if playing:
		playing = false
		finished.emit()

func set_on(v: bool) -> void:
	on = v
	if not v:
		skip()
	Game.settings.set_value("sound", "voice", v)
	Game.settings.save(Game.SETTINGS)
