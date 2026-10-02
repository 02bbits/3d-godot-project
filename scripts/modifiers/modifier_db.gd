class_name ModifierDB
extends RefCounted

# Registry of every modifier in the game. New content = drop a .tres into
# modifiers/defs (stats only) or a Modifier subclass into modifiers/impl,
# then add one line here.

# ponytail: static var because .new() isn't a const expression; if instances
# ever need construction args, build a real factory here
static var DEFS: Dictionary = _build_defs()


static func _build_defs() -> Dictionary:
	return {
		# --- movement ---
		&"swift_boots": load("res://scripts/modifiers/defs/swift_boots.tres"),
		&"feather": load("res://scripts/modifiers/defs/feather.tres"),
		&"dash_surge": load("res://scripts/modifiers/defs/dash_surge.tres"),
		# --- weapon ---
		&"hair_trigger": load("res://scripts/modifiers/defs/hair_trigger.tres"),
		&"extended_mag": load("res://scripts/modifiers/defs/extended_mag.tres"),
		&"fast_hands": load("res://scripts/modifiers/defs/fast_hands.tres"),
		&"heavy_rounds": load("res://scripts/modifiers/defs/heavy_rounds.tres"),
		# --- combat ---
		# ponytail: behavioral impls (vampire_bullets, berserker, sniper_focus,
		# second_wind) not ported; re-add one line each when their impl/*.gd
		# come back from the old /fps project
		# --- defense ---
		&"plating": load("res://scripts/modifiers/defs/plating.tres"),
		# --- chaos ---
		&"glass_cannon": load("res://scripts/modifiers/defs/glass_cannon.tres"),
		&"low_gravity": load("res://scripts/modifiers/defs/low_gravity.tres"),
	}


static func get_def(id: StringName) -> Modifier:
	return DEFS.get(id)


static func all_ids() -> Array:
	return DEFS.keys()
