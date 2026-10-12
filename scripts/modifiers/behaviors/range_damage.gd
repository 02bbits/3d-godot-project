extends Modifier

## Stats: +bonus_percent damage per level against players hit between
## min_distance and max_distance metres away (Close Quarters, Marksman).

@export var min_distance := 0.0
@export var max_distance := 8.0
@export var bonus_percent := 12.0


func on_damage_dealt(ctx: Dictionary, _me: Node) -> void:
	if ctx.hit_player and ctx.distance >= min_distance and ctx.distance <= max_distance:
		ctx.amount *= 1.0 + bonus_percent * level / 100.0


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	var where := "beyond %d m" % roundi(min_distance) if min_distance > 0.0 \
			else "within %d m" % roundi(max_distance)
	lines.append(line("Damage " + where, signed(bonus_percent * at_level) + "%", TONE_GOOD))
	return lines
