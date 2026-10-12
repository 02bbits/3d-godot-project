class_name Modifier
extends Resource

## One modifier card: data plus optional behaviour. A pure-stat modifier is
## just a .tres in resources/modifiers/ (the file name is its id). A
## behavioural one is a subclass in scripts/modifiers/behaviors/ overriding
## the hooks it needs, with its own .tres. Guide: docs/MODIFIER_GUIDE.md.

enum Type { STATS, WEAPON, ABILITY, ENVIRONMENT }
enum Rarity { COMMON, RARE, EPIC }

const TONE_GOOD := "good"
const TONE_BAD := "bad"
const TONE_NEUTRAL := "neutral"
const MINUS := "−"

@export var display_name := ""
## one flavour line under the name on the card
@export_multiline var description := ""
## sets the icon. ENVIRONMENT modifiers apply to every player.
@export var type := Type.STATS
## sets the colour and how often the card is offered (ModRules.RARITIES)
@export var rarity := Rarity.COMMON
## how many times it can be picked; each level adds the values below again
@export_range(1, 5) var max_level := 1

@export_group("Per level")
## percent change per level, by ModRules.STATS key: {&"move_speed": 15.0}
@export var percent: Dictionary[StringName, float] = {}
## flat change per level, by ModRules.STATS key: {&"max_health": 15.0}
@export var flat: Dictionary[StringName, float] = {}

@export_group("Special")
## replaces the owner's weapon while owned (the last one picked wins)
@export var weapon: WeaponDefinition
## modifiers sharing a group never stack: owning one removes the others from
## the draft pool
@export var exclusive_group: StringName
## > 0 makes this a timed status effect (resources/modifiers/status/), applied
## by hits and never drafted
@export var duration := 0.0

# set by ModifierDB from the file name; copied onto every instance
@export_storage var id: StringName
# runtime: how many times the owner picked it
var level := 1


func is_global() -> bool:
	return type == Type.ENVIRONMENT


## Card / tray lines at `at_level`: [{label, value, tone}]. Subclasses append
## lines for their behaviour.
func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for stat in percent:
		lines.append(stat_line(stat, percent[stat] * at_level, "%"))
	for stat in flat:
		lines.append(stat_line(stat, flat[stat] * at_level,
				str(ModRules.STATS.get(stat, {}).get("suffix", ""))))
	if weapon != null:
		lines.append(line("Weapon", weapon.display_name))
		lines.append(line("Damage", str(weapon.damage)))
		lines.append(line("Magazine", str(weapon.mag_size)))
	if is_global():
		lines.append(line("Applies to", "All players", TONE_GOOD))
	return lines


## one-line summary for the TAB list: "Damage +50% · Fire rate −20%"
func summary(at_level: int = level) -> String:
	var parts: PackedStringArray = []
	for entry in describe(at_level):
		if entry.label != "Applies to":
			parts.append("%s %s" % [entry.label, entry.value])
	return " · ".join(parts) + (" (all players)" if is_global() else "")


static func stat_line(stat: StringName, amount: float, suffix: String) -> Dictionary:
	var info: Dictionary = ModRules.STATS.get(stat, {})
	var effect := signf(amount) * float(info.get("good", 0))
	var tone := TONE_GOOD if effect > 0.0 else (TONE_BAD if effect < 0.0 else TONE_NEUTRAL)
	return line(str(info.get("label", stat)), signed(amount) + suffix, tone)


static func line(label: String, value: String, tone := TONE_NEUTRAL) -> Dictionary:
	return {"label": label, "value": value, "tone": tone}


# "+15", "−0.5" (typographic minus, like the cards)
static func signed(amount: float) -> String:
	var magnitude := absf(amount)
	var text := "%d" % roundi(magnitude) if is_equal_approx(magnitude, roundf(magnitude)) \
			else "%.1f" % magnitude
	return ("+" if amount >= 0.0 else MINUS) + text


# HOOKS: override what the behaviour needs. `me` is the owning player; ctx
# dictionaries are shared with the caller, so mutating them changes the outcome.

## Owner shoots. shot = {origin, direction, range, hit}; replace `hit` (a ray
## result: collider, position, normal) to retarget the shot.
func on_fire(_shot: Dictionary, _me: Node) -> void:
	pass


## Owner hits something. ctx = {amount, attacker_id, distance, hit_player,
## victim, statuses}; append status ids to `statuses` to apply them on hit.
func on_damage_dealt(_ctx: Dictionary, _me: Node) -> void:
	pass


## Owner is about to take damage. ctx = {amount, attacker_id}.
func on_damage_taken(_ctx: Dictionary, _me: Node) -> void:
	pass


## Owner eliminated someone. ctx = {victim}.
func on_kill(_ctx: Dictionary, _me: Node) -> void:
	pass


## Owner (re)spawned: reset per-life state here.
func on_respawn(_me: Node) -> void:
	pass
