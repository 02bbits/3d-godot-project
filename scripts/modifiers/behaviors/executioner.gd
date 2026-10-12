extends Modifier

## Weapon: more damage against players below `threshold` of their health
## (read from the victim's replicated health).

@export var threshold := 0.3
@export var bonus_percent := 30.0


func on_damage_dealt(ctx: Dictionary, _me: Node) -> void:
	var victim: Node = ctx.victim
	if ctx.hit_player and victim.health <= victim.max_health * threshold:
		ctx.amount *= 1.0 + bonus_percent * level / 100.0


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Damage below %d%% HP" % roundi(threshold * 100.0),
			signed(bonus_percent * at_level) + "%", TONE_GOOD))
	return lines
