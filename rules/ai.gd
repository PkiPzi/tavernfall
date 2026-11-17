extends RefCounted
# Plays one turn for a monster: close in and hit, or shoot if it cannot reach.

static func take_turn(cb, c) -> void:
	var foes: Array = cb.all.filter(func(o): return o.side != c.side and cb.active(o))
	if foes.is_empty() or c.attacks.is_empty():
		cb.end_turn()
		return
	foes.sort_custom(func(a, b): return cb.dist(c.pos, a.pos) < cb.dist(c.pos, b.pos))
	if cb.flag(c, "flee"):
		_flee(cb, c, foes[0])
		cb.end_turn()
		return
	var t = foes[0]
	var melee := -1
	var shot := -1
	for i in c.attacks.size():
		if c.attacks[i].ranged and shot < 0:
			shot = i
		elif not c.attacks[i].ranged and melee < 0:
			melee = i
	var adjacent: bool = cb.dist(c.pos, t.pos) <= 5
	if shot >= 0 and not adjacent and (melee < 0 or cb.dist(c.pos, t.pos) > c.speed + 5):
		if _swing(cb, c, t, shot):
			cb.end_turn()
			return
	if melee >= 0:
		_approach(cb, c, t)
		if cb.winner() == "" and cb.active(c) and not _swing(cb, c, t, melee):
			if shot < 0 or not _swing(cb, c, t, shot):
				cb.dash(c)
				_approach(cb, c, t)
	cb.end_turn()

# The whole Attack action: every swing of a Multiattack. True if at least one swing happened.
static func _swing(cb, c, t, i: int) -> bool:
	var seq: Array = c.multi_seq if not c.attacks[i].ranged else []
	if not cb.attack(c, t, seq[0] if not seq.is_empty() else i).ok:
		return false
	for k in range(1, c.multi):
		if t.dead or not cb.active(c) or cb.winner() != "":
			break
		cb.attack(c, t, seq[k] if not seq.is_empty() else i)
	return true

# Walks the shortest way round walls and other creatures to a square next to the target.
static func _approach(cb, c, t) -> void:
	if cb.dist(c.pos, t.pos) <= 5:
		return
	var came := {c.pos: c.pos}
	var queue := [c.pos]
	var goal = null
	while not queue.is_empty() and goal == null and came.size() < 600:
		var cur: Vector2i = queue.pop_front()
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var cell: Vector2i = cur + Vector2i(dx, dy)
				if came.has(cell) or cb.blocked.has(cell) or cb.at(cell) != null:
					continue
				came[cell] = cur
				if goal == null and cb.dist(cell, t.pos) <= 5:
					goal = cell
				queue.append(cell)
	if goal == null:
		return
	var path := []
	while goal != c.pos:
		path.push_front(goal)
		goal = came[goal]
	for cell in path:
		if not cb.active(c) or not cb.move(c, [cell]).ok:
			return

# A turned creature spends its movement stepping to whichever neighbouring square is furthest from the nearest foe.
static func _flee(cb, c, foe) -> void:
	while cb.active(c) and c.move_left >= 5:
		var best = null
		var far: int = cb.dist(c.pos, foe.pos)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var cell: Vector2i = c.pos + Vector2i(dx, dy)
				if (dx != 0 or dy != 0) and not cb.blocked.has(cell) and cb.at(cell) == null and cb.dist(cell, foe.pos) > far:
					far = cb.dist(cell, foe.pos)
					best = cell
		if best == null or not cb.move(c, [best]).ok:
			return
