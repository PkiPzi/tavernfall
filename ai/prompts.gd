extends RefCounted
# The words sent to the Dungeon Master. The game code rolls every die and applies every rule;
# the AI only tells the story and proposes checks, fights, rests and rewards in fixed JSON.

const TEMPLATES = ["dungeon", "tavern", "cave", "forest", "road"]
# XP a medium fight is worth per hero, by level (SRD encounter thresholds).
const BUDGET = [0, 50, 100, 150, 250, 500]

static func system() -> String:
	var mons := []
	var top := 2  # tougher monsters are offered once the heroes can face them
	for c in Game.party:
		top = max(top, c.level - 1)
	for m in Game.srd.t.monsters.values():
		if m.challenge_rating <= top:
			mons.append("%s:%d" % [m.index, m.xp])
	return """You are the Dungeon Master of Tavernfall, a D&D 5e game (SRD rules only) played on one computer.
The game's code owns every rule and every die roll. You never roll dice, never state hit points or damage,
and never decide whether an uncertain action succeeds: you ask the code for a check instead.
You tell the story, speak for the world and its characters, and propose checks, fights, rests and rewards.
Never decide what the heroes say, feel or do. Keep the tone of a good tabletop session: vivid, concrete, brisk.
Reply with exactly one JSON object and nothing else. No markdown, no code fences.

Skills you may ask checks for: %s. Or an ability: str, dex, con, int, wis, cha.
Place templates: %s.
Monsters you may use, as index:xp (use the index exactly): %s""" % [
		", ".join(Game.srd.t.skills.keys()), ", ".join(TEMPLATES), " ".join(mons)]

static func party_lines() -> String:
	var lines := []
	for c in Game.party:
		lines.append("- %s: %s %s level %d, HP %d/%d%s%s" % [c.name, c.spec.race, c.cls, c.level, c.hp, c.max_hp,
			", spells: " + ", ".join(c.spells) if not c.spells.is_empty() else "", " (DEAD)" if c.dead else ""])
	return "\n".join(lines)

static func budget() -> int:
	var total := 0
	for c in Game.party:
		if not c.dead:
			total += BUDGET[c.level]
	return total

static func plan(hints: String, source: String) -> String:
	var ask := "Write an adventure from these hints from the player: %s" % (hints if hints.strip_edges() != "" else "(none given, surprise them)")
	if source != "":
		ask = "Convert this existing adventure into the plan format, keeping its story, places and foes " \
			+ "(swap any monster that is not in your list for the closest one that is):\n<<<\n%s\n>>>\nExtra wishes from the player: %s" % [source, hints]
	return """REQUEST: plan
%s

The party:
%s

Plan a short adventure of 3 acts for this party, about 2 to 4 fights in total. A medium fight for them is
about %d XP of monsters; the last fight may be up to double that. Use only monsters from your list.
Reply with this JSON:
{"title": "...", "setting": "2 sentences", "villain": {"name": "...", "motive": "..."},
 "locations": [{"name": "...", "description": "1 sentence", "template": "exactly one of: dungeon, tavern, cave, forest, road"}],
 "npcs": [{"name": "...", "role": "..."}],
 "encounters": [{"location": "...", "monsters": [{"index": "...", "count": 1}], "trigger": "..."}],
 "acts": ["act 1 in a sentence", "act 2", "act 3"],
 "opening": "3 to 5 sentences that set the first scene and end where the heroes must choose what to do"}""" % [ask, party_lines(), budget()]

# what: the player's action, a check result or a battle result, as one line of text.
static func turn(what: String) -> String:
	var s: Dictionary = Game.story
	var recent := []
	for t in s.turns.slice(-8):
		recent.append("PLAYER: %s\nDM: %s" % [t.player, t.dm])
	return """REQUEST: turn
The adventure plan (secret from the player):
%s

Story so far (your running summary): %s

Last turns:
%s

The party now:
%s
Medium fight budget: %d XP of monsters.

What just happened: %s

Continue the story. Rules for your reply:
- "narration": 2 to 5 sentences. If you ask for a check, stop before the outcome.
- "choices": 3 or 4 short things the heroes could do next (the player may also type anything). Empty when you set "check" or "encounter".
- "check": when an action could fail and failure matters, else null. "character" is the hero who acts.
- "encounter": when a fight starts now, else null. The code runs the fight and tells you how it went.
- "rest": "short" or "long" when the heroes actually rest, else null.
- "heal": when a hero heals someone outside a fight, else null. "with" is cure-wounds, healing-word or potion. The code
  spends the spell slot or potion and rolls the healing; do not say how much was healed.
- Never mention hit point numbers. Say "badly hurt" or "barely standing" instead.
- "reward": xp for clever play or finished goals (not for fights, the code awards those), and healing potions found, else null.
- "summary": the running summary rewritten to include this turn, at most 120 words.
- "ended": true only when the adventure is over.
Reply with this JSON:
{"narration": "...", "location": {"name": "...", "template": "..."}, "choices": ["..."],
 "check": null or {"character": "...", "skill": "skill or ability", "dc": 5-25, "why": "..."},
 "encounter": null or {"monsters": [{"index": "...", "count": 1}], "intro": "..."},
 "rest": null, "heal": null or {"caster": "...", "with": "cure-wounds", "target": "..."}, "reward": null or {"xp": 0, "items": {"potion-of-healing": 0}},
 "summary": "...", "ended": false}""" % [JSON.stringify(s.plan), s.summary if s.summary != "" else "(just starting)",
		"\n".join(recent) if not recent.is_empty() else "(none yet)", party_lines(), budget(), what]
