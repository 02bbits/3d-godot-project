class_name ModifierManager
extends Node

## Per-player modifier state (child of the player, `player.mods`).
## The build is the player's replicated `net_mods` (picked ids in pick order,
## comma separated), so every copy of a player knows it. A copy's active set
## is its own picks + environment modifiers any other player owns + timed
## statuses. get_stat() is the only place stat math and caps happen.
## Guide: docs/MODIFIER_GUIDE.md.

signal build_changed
signal picked(mod: Modifier)

var _instances := {} # id -> Modifier: one live copy per id, so behaviour state survives refreshes
var _own: Array[Modifier] = [] # own picks, pick order, one entry per id
var _active: Array[Modifier] = []
var _status_tokens := {} # status id -> token of its latest application
var _flat := {}
var _percent := {}
var _bases := {} # controller property -> unmodified value

@onready var player: Node = get_parent()


func _ready() -> void:
	add_to_group(&"modifier_manager")


# BUILD

## Local player only: adds one level of `id` to the replicated build.
func pick(id: StringName) -> void:
	var ids: PackedStringArray = String(player.net_mods).split(",", false)
	ids.append(String(id))
	player.net_mods = ",".join(ids) # the setter runs sync_build on every copy
	picked.emit(_instances[id])


## Every copy, whenever the player's net_mods changes.
func sync_build(csv: String) -> void:
	var levels := {}
	_own.clear()
	for raw in csv.split(",", false):
		var mod := _instance(StringName(raw))
		if mod == null or mod.duration > 0.0:
			continue
		levels[mod.id] = int(levels.get(mod.id, 0)) + 1
		if levels[mod.id] == 1:
			_own.append(mod)
	for mod in _own:
		mod.level = mini(levels[mod.id], mod.max_level)
	# environment picks change every player's active set
	get_tree().call_group(&"modifier_manager", &"refresh")


func refresh() -> void:
	if not player.is_node_ready():
		return
	_active = _own.duplicate()
	for other in get_tree().get_nodes_in_group(&"player"):
		if other == player or not is_instance_valid(other) or not other.is_node_ready():
			continue
		for theirs: Modifier in other.mods.owned():
			if theirs.is_global() and not _active.any(func(m: Modifier) -> bool: return m.id == theirs.id):
				var mod := _instance(theirs.id)
				mod.level = theirs.level
				_active.append(mod)
	for id in _status_tokens:
		_active.append(_instance(id))
	_rebuild_cache()
	_apply_player_stats()
	_apply_weapon()
	build_changed.emit()


func owned() -> Array[Modifier]:
	return _own


## own picks + environment modifiers from others (statuses excluded): the HUD list
func active() -> Array[Modifier]:
	var mods: Array[Modifier] = []
	for mod in _active:
		if mod.duration <= 0.0:
			mods.append(mod)
	return mods


## active timed statuses (HUD status chips)
func statuses() -> Array[Modifier]:
	var mods: Array[Modifier] = []
	for mod in _active:
		if mod.duration > 0.0:
			mods.append(mod)
	return mods


func level_of(id: StringName) -> int:
	for mod in _own:
		if mod.id == id:
			return mod.level
	return 0


func roll_offers() -> Array[Modifier]:
	var levels := {}
	var groups: Array = []
	for mod in _own:
		levels[mod.id] = mod.level
		if mod.exclusive_group != &"":
			groups.append(mod.exclusive_group)
	var taken: Array = []
	for manager in get_tree().get_nodes_in_group(&"modifier_manager"):
		for mod: Modifier in manager.owned():
			if mod.is_global():
				taken.append(mod.id)
	return ModifierDB.roll_offers(levels, taken, groups)


# STATS

## (base + Σflat) × (1 + Σpercent / 100), clamped by the ModRules.STATS caps.
func get_stat(stat: StringName, base: float) -> float:
	var value := (base + float(_flat.get(stat, 0.0))) * (1.0 + float(_percent.get(stat, 0.0)) / 100.0)
	var info: Dictionary = ModRules.STATS.get(stat, {})
	if info.has("min"):
		var unit := base if base != 0.0 else 1.0
		var lo: float = info.min * unit
		var hi: float = info.max * unit
		value = clampf(value, minf(lo, hi), maxf(lo, hi))
	return value


func _rebuild_cache() -> void:
	_flat = {}
	_percent = {}
	for mod in _active:
		for stat in mod.flat:
			_flat[stat] = float(_flat.get(stat, 0.0)) + mod.flat[stat] * mod.level
		for stat in mod.percent:
			_percent[stat] = float(_percent.get(stat, 0.0)) + mod.percent[stat] * mod.level


# Only the local copy simulates, so only it gets stats. Bases are snapshot on
# first apply; this must stay the only writer of the bound properties.
func _apply_player_stats() -> void:
	if player.is_remote:
		return
	for stat in ModRules.STATS:
		for prop in ModRules.STATS[stat].get("player", []):
			if not _bases.has(prop):
				_bases[prop] = player.get(prop)
			var value := get_stat(stat, float(_bases[prop]))
			player.set(prop, roundi(value) if _bases[prop] is int else value)
	if not _bases.has(&"max_health"):
		_bases[&"max_health"] = player.max_health
	var health: Health = player.get_node("Health")
	var previous := health.max_health
	var new_max := get_stat(&"max_health", _bases[&"max_health"])
	player.max_health = new_max
	health.max_health = new_max
	if new_max > previous:
		health.heal(new_max - previous)
	health.health = minf(health.health, new_max)


# every copy: remote players must show the replacement gun in their hand
func _apply_weapon() -> void:
	var definition: WeaponDefinition = player.weapon_definition
	for mod in _own:
		if mod.weapon != null:
			definition = mod.weapon
	if player.weapon != null and definition != null and player.weapon.definition != definition:
		player.equip_weapon(definition)


# STATUSES

## Local copy only (rpc_apply_status): a timed modifier, refreshed on re-hit.
func apply_status(id: StringName) -> void:
	var def := ModifierDB.get_def(id)
	if def == null or def.duration <= 0.0:
		return
	var token := Time.get_ticks_usec()
	_status_tokens[id] = token
	refresh()
	_instance(id).on_applied(player)
	await get_tree().create_timer(def.duration).timeout
	if _status_tokens.get(id) == token:
		_status_tokens.erase(id)
		refresh()


# HOOKS: game code calls these; every active modifier may mutate the ctx.

func on_fire(shot: Dictionary) -> void:
	for mod in _active:
		mod.on_fire(shot, player)


func on_damage_dealt(ctx: Dictionary) -> void:
	for mod in _active:
		mod.on_damage_dealt(ctx, player)


func on_damage_taken(ctx: Dictionary) -> void:
	for mod in _active:
		mod.on_damage_taken(ctx, player)


func on_kill(ctx: Dictionary) -> void:
	for mod in _active:
		mod.on_kill(ctx, player)


func on_physics(delta: float) -> void:
	for mod in _active:
		mod.on_physics(delta, player)


func on_dash() -> void:
	for mod in _active:
		mod.on_dash(player)


func on_impact(shot: Dictionary) -> void:
	for mod in _active:
		mod.on_impact(shot, player)


func on_shot_fx(hit: Dictionary) -> void:
	for mod in _active:
		mod.on_shot_fx(hit, player)


func on_respawn() -> void:
	if not _status_tokens.is_empty():
		_status_tokens.clear()
		refresh()
	for mod in _active:
		mod.on_respawn(player)


func _instance(id: StringName) -> Modifier:
	if not _instances.has(id):
		var def := ModifierDB.get_def(id)
		if def == null:
			return null
		_instances[id] = def.duplicate()
	return _instances[id]
