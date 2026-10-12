class_name ModifierDB
extends RefCounted

## Every modifier, discovered from disk: each .tres in DRAFT_DIR is a
## draftable modifier, each in STATUS_DIR a timed status effect. Adding
## content is adding a file (its name is the id); nothing here changes.

const DRAFT_DIR := "res://resources/modifiers/"
const STATUS_DIR := "res://resources/modifiers/status/"

# load-time validation messages (also push_error'd); tools/check_modifiers.gd
# fails on any
static var problems: PackedStringArray = []
static var _defs: Dictionary = _load_all()


static func get_def(id: StringName) -> Modifier:
	return _defs.get(id)


static func all() -> Array:
	return _defs.values()


static func draftable() -> Array[Modifier]:
	var mods: Array[Modifier] = []
	for mod: Modifier in _defs.values():
		if mod.duration <= 0.0:
			mods.append(mod)
	return mods


## `count` distinct offers for a player. levels: id -> owned level;
## taken_globals: environment ids anyone owns; held_groups: the player's
## exclusive groups. Each slot rolls a rarity by weight, then a modifier of
## it (any rarity if that one ran dry).
static func roll_offers(levels: Dictionary, taken_globals: Array, held_groups: Array,
		count := ModRules.OFFER_COUNT, rng := RandomNumberGenerator.new()) -> Array[Modifier]:
	var pool: Array[Modifier] = []
	for mod in draftable():
		var owned := int(levels.get(mod.id, 0))
		if owned >= mod.max_level:
			continue
		if mod.is_global() and taken_globals.has(mod.id):
			continue
		if mod.exclusive_group != &"" and owned == 0 and held_groups.has(mod.exclusive_group):
			continue
		pool.append(mod)
	var weights := PackedFloat32Array()
	for rarity in ModRules.RARITIES:
		weights.append(rarity.weight)
	var hand: Array[Modifier] = []
	while hand.size() < count and not pool.is_empty():
		var rarity := rng.rand_weighted(weights)
		var of_rarity := pool.filter(func(mod: Modifier) -> bool: return mod.rarity == rarity)
		var source: Array = of_rarity if not of_rarity.is_empty() else pool
		var pick: Modifier = source[rng.randi() % source.size()]
		hand.append(pick)
		pool.erase(pick)
	return hand


static func _load_all() -> Dictionary:
	var defs := {}
	for dir in [DRAFT_DIR, STATUS_DIR]:
		for file in ResourceLoader.list_directory(dir):
			if not file.ends_with(".tres"):
				continue
			var path: String = dir + file
			var mod := load(path) as Modifier
			if mod == null:
				_problem(path, "not a Modifier resource")
				continue
			mod.id = StringName(file.get_basename())
			if defs.has(mod.id):
				_problem(path, "duplicate id '%s'" % mod.id)
				continue
			_validate(mod, path, dir == STATUS_DIR)
			defs[mod.id] = mod
	return defs


static func _validate(mod: Modifier, path: String, is_status: bool) -> void:
	if mod.display_name.is_empty():
		_problem(path, "no display_name")
	if is_status != (mod.duration > 0.0):
		_problem(path, "statuses (and only statuses) need duration > 0")
	for stat in mod.percent.keys() + mod.flat.keys():
		if not ModRules.STATS.has(stat):
			_problem(path, "unknown stat '%s' (add it to ModRules.STATS)" % stat)


static func _problem(path: String, message: String) -> void:
	problems.append("%s: %s" % [path, message])
	push_error("Modifier %s: %s" % [path, message])
