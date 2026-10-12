class_name ModRules
extends RefCounted

## Every modifier tuning knob that isn't per-modifier: draft size and timer,
## rarity colours and drop weights, type names and icons, and the stat table.
## A modifier's own numbers live in its .tres (resources/modifiers/).
## Guide: docs/MODIFIER_GUIDE.md.

const OFFER_COUNT := 3
const DRAFT_SECONDS := 20.0

# indexed by Modifier.Rarity. Weights are relative drop chances per card slot.
const RARITIES := [
	{"name": "COMMON", "color": Color("#4DA2FE"), "weight": 60.0},
	{"name": "RARE", "color": Color("#FF8A2B"), "weight": 30.0},
	{"name": "EPIC", "color": Color("#A66CFF"), "weight": 10.0},
]

# indexed by Modifier.Type
const TYPES := [
	{"name": "Stats", "icon": preload("res://assets/ui/mods/stats.svg"),
			"blurb": "Changes player stats: damage, speed, health, healing."},
	{"name": "Weapon", "icon": preload("res://assets/ui/mods/weapon.svg"),
			"blurb": "Changes how the gun behaves: fire rate, magazine, rounds."},
	{"name": "Ability", "icon": preload("res://assets/ui/mods/ability.svg"),
			"blurb": "Adds a custom ability, such as a stronger dash."},
	{"name": "Environment", "icon": preload("res://assets/ui/mods/environment.svg"),
			"blurb": "Changes the match for everyone: gravity, custom events."},
]

# Every stat a modifier may touch (a .tres naming any other key fails
# validation).
#   label    card / tray text
#   min, max caps on the final value, as multiples of the base value
#            (absolute limits when the base is 0)
#   good     +1 higher is better, -1 lower is better: colours card values
#   suffix   unit shown after flat values ("%" for lifesteal)
#   player   controller properties the stat scales; ModifierManager applies
#            them. Stats without it are read where they apply with
#            `player.mods.get_stat(stat, base)`.
const STATS := {
	&"move_speed": {"label": "Move speed", "min": 0.5, "max": 1.6, "good": 1,
			"player": [&"walk_speed", &"run_speed", &"crouch_speed", &"wallrun_speed",
					&"slide_speed", &"dash_speed"]},
	&"max_health": {"label": "Max health", "min": 0.4, "max": 1.6, "good": 1},
	&"stamina": {"label": "Stamina", "min": 0.5, "max": 2.0, "good": 1,
			"player": [&"stamina_max", &"stamina_regen"]},
	&"traction": {"label": "Traction", "min": 0.2, "max": 1.5, "good": 1,
			"player": [&"idle_deccel", &"walk_accel", &"walk_deccel", &"run_accel",
					&"run_deccel", &"crouch_accel", &"crouch_deccel"]},
	&"gravity": {"label": "Gravity", "min": 0.2, "max": 1.2, "good": -1,
			"player": [&"jump_gravity", &"fall_gravity"]},
	&"air_jumps": {"label": "Air jumps", "min": 0.0, "max": 3.0, "good": 1,
			"player": [&"nb_jumps_in_air_allowed_ref"]},
	&"dash_charges": {"label": "Dash charges", "min": 1.0, "max": 3.0, "good": 1,
			"player": [&"nb_dashs_allowed_ref"]},
	&"dash_cooldown": {"label": "Dash cooldown", "min": 0.3, "max": 2.0, "good": -1,
			"player": [&"time_bef_reload_dash_ref"]},
	&"damage": {"label": "Damage", "min": 0.5, "max": 2.5, "good": 1},
	&"damage_taken": {"label": "Damage taken", "min": 0.4, "max": 1.5, "good": -1},
	&"fire_rate": {"label": "Fire rate", "min": 0.5, "max": 2.0, "good": 1},
	&"reload_time": {"label": "Reload time", "min": 0.3, "max": 2.0, "good": -1},
	&"mag_size": {"label": "Magazine", "min": 0.5, "max": 2.5, "good": 1},
	&"lifesteal": {"label": "Lifesteal", "min": 0.0, "max": 50.0, "good": 1, "suffix": "%"},
}


static func rarity_color(rarity: int) -> Color:
	return RARITIES[rarity].color
