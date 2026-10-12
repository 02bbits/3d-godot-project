extends Modifier

## Stats: every kill heals the owner.

@export var heal := 50.0


func on_kill(_ctx: Dictionary, me: Node) -> void:
	me.get_node("Health").heal(heal * level)


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Heal on kill", signed(heal * at_level) + " HP", TONE_GOOD))
	return lines
