extends RefCounted
# All randomness goes through here so fights can be seeded and tests can force rolls.

var rng := RandomNumberGenerator.new()
var queue: Array = []  # tests: forced die results, used before the rng

func _init(seed_value = null) -> void:
	if seed_value == null:
		rng.randomize()
	else:
		rng.seed = seed_value

func die(sides: int) -> int:
	if not queue.is_empty():
		return queue.pop_front()
	return rng.randi_range(1, sides)

# mode: 1 advantage, -1 disadvantage, 0 normal
func d20(mode := 0) -> Dictionary:
	var a := die(20)
	if mode == 0:
		return {"roll": a, "rolls": [a]}
	var b := die(20)
	return {"roll": max(a, b) if mode > 0 else min(a, b), "rolls": [a, b]}

# "2d6+3", "1d8 + 2", "5". A critical hit doubles the dice, not the flat part.
func roll(expr: String, crit := false) -> int:
	var re := RegEx.create_from_string("([+-]?)(\\d+)(?:d(\\d+))?")
	var total := 0
	for m in re.search_all(expr.replace(" ", "")):
		var sign := -1 if m.get_string(1) == "-" else 1
		var n := int(m.get_string(2))
		if m.get_string(3) == "":
			total += sign * n
		else:
			for i in n * (2 if crit else 1):
				total += sign * die(int(m.get_string(3)))
	return max(total, 0)
