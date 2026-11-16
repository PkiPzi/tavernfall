extends RefCounted
# SRD 5.1 data (5e-database JSON), each table indexed by its "index" field.

var t := {}

func _init(dir := "res://data/srd") -> void:
	for n in ["Classes", "Conditions", "Equipment", "Features", "Levels", "Monsters",
			"Proficiencies", "Races", "Skills", "Spells", "Subclasses", "Subraces", "Traits"]:
		var m := {}
		for e in JSON.parse_string(FileAccess.get_file_as_string("%s/5e-SRD-%s.json" % [dir, n])):
			m[e.index] = e
		t[n.to_lower()] = m
