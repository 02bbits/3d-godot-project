extends Modifier

## Ability: once per life, a lethal hit leaves the owner at 1 HP instead.

var _used := false


func on_respawn(_me: Node) -> void:
	_used = false


func on_damage_taken(ctx: Dictionary, me: Node) -> void:
	if _used or ctx.amount < me.health:
		return
	_used = true
	ctx.amount = maxf(me.health - 1.0, 0.0)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Lethal hit", "Survive at 1 HP", TONE_GOOD))
	lines.append(line("Charges", "Once per life"))
	return lines
