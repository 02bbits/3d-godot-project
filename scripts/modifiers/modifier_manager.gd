class_name ModifierManager
extends Node

# Per-player: holds active Modifier instances, caches final stat values, and
# applies build-affecting stats onto the controller. One node, child of the
# player. get_stat() is the single place caps are enforced.

signal build_changed(mods: Array)
signal mod_timer_done(mod_id: StringName)

# Multiplier caps per stat, as [lo, hi] applied to (base + adds) * mults.
const STAT_CAPS := {
	&"damage": [0.5, 2.5],
	&"damage_taken": [0.4, 1.5],
	&"move_speed": [0.5, 1.6],
	&"fire_rate": [0.5, 2.0],
	&"reload_time": [0.3, 2.0],
	&"mag_size": [0.5, 2.5],
	&"max_health": [0.4, 1.6],
	&"gravity": [0.2, 1.2],
	&"dash_cooldown": [0.3, 2.0],
}

var mods: Array = []
var _mults := {}
var _adds := {}
var _bases := {}


func get_stat(stat: StringName, base: float) -> float:
	var value := (base + float(_adds.get(stat, 0.0))) * float(_mults.get(stat, 1.0))
	if STAT_CAPS.has(stat):
		var cap: Array = STAT_CAPS[stat]
		value = clampf(value, base * cap[0], base * cap[1])
	return value


func set_build(ids: Array) -> void:
	# per-player copies (behavioral mods carry per-instance state); exclusive
	# groups enforced here as well as at draft time: last pick of a group wins
	mods = []
	for id in ids:
		var def: Modifier = ModifierDB.get_def(id)
		if def == null:
			continue
		if def.exclusive_group != StringName():
			mods = mods.filter(func(other: Modifier) -> bool:
				return other.exclusive_group != def.exclusive_group)
		mods.append(def.duplicate())
	_rebuild_cache()
	_apply_player_stats()
	build_changed.emit(mods)


func clear() -> void:
	mods = []
	_rebuild_cache()
	_apply_player_stats()
	build_changed.emit(mods)


func _rebuild_cache() -> void:
	_adds = {}
	_mults = {}
	for m in mods:
		for stat in m.stat_adds:
			_adds[stat] = float(_adds.get(stat, 0.0)) + float(m.stat_adds[stat])
		for stat in m.stat_mults:
			_mults[stat] = float(_mults.get(stat, 1.0)) * float(m.stat_mults[stat])


func _apply_player_stats() -> void:
	var player := get_parent() as PlayerCharacter
	if player == null or player.is_remote:
		return
	if _bases.is_empty():
		# ponytail: snapshots controller exports on first apply; keep this the
		# only writer of these fields or the base values drift
		_bases = {
			&"walk": player.walk_speed,
			&"run": player.run_speed,
			&"crouch": player.crouch_speed,
			&"wallrun": player.wallrun_speed,
			&"slide": player.slide_speed,
			&"dash": player.dash_speed,
			&"jump_gravity": player.jump_gravity,
			&"fall_gravity": player.fall_gravity,
			&"max_health": player.max_health,
			&"dash_cooldown": player.time_bef_reload_dash_ref,
		}
	var sm := get_stat(&"move_speed", 1.0)
	player.walk_speed = _bases[&"walk"] * sm
	player.run_speed = _bases[&"run"] * sm
	player.crouch_speed = _bases[&"crouch"] * sm
	player.wallrun_speed = _bases[&"wallrun"] * sm
	player.slide_speed = _bases[&"slide"] * sm
	player.dash_speed = _bases[&"dash"] * sm
	var gm := get_stat(&"gravity", 1.0)
	player.jump_gravity = _bases[&"jump_gravity"] * gm
	player.fall_gravity = _bases[&"fall_gravity"] * gm
	player.time_bef_reload_dash_ref = _bases[&"dash_cooldown"] * get_stat(&"dash_cooldown", 1.0)
	var h := player.get_node_or_null("Health") as Health
	if h != null:
		var prev_max := h.max_health
		var new_max := get_stat(&"max_health", _bases[&"max_health"])
		player.max_health = new_max
		h.max_health = new_max
		if new_max > prev_max:
			h.heal(new_max - prev_max)
		h.health = minf(h.health, new_max)


# Hook dispatch: callers pass the ctx dict; mods may mutate it in place.
func on_damage_dealt(ctx: Dictionary) -> void:
	for m in mods:
		m.on_damage_dealt(ctx, get_parent())


func on_damage_taken(ctx: Dictionary) -> void:
	for m in mods:
		m.on_damage_taken(ctx, get_parent())


func on_kill(ctx: Dictionary) -> void:
	for m in mods:
		m.on_kill(ctx, get_parent())


func on_round_start() -> void:
	for m in mods:
		m.on_round_start(get_parent())


func add_timer(mod_id: StringName, seconds: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	add_child(t)
	t.timeout.connect(func() -> void:
		mod_timer_done.emit(mod_id)
		t.queue_free())
	t.start(seconds)
