extends Modifier

## Status (Zap Gun): freezes the victim's movement, jumps, dashes and shooting
## for `duration`, then makes them immune to new zaps for `immunity` seconds,
## so a fast-firing gun can't keep someone locked down.

@export var immunity := 1.5

var _immune_until := 0.0


func on_applied(me: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _immune_until:
		return
	me.stun(duration)
	_immune_until = now + duration + immunity


func describe(at_level: int = 1) -> Array[Dictionary]:
	var lines := super(at_level)
	lines.append(line("Immune after", "%.1f s" % immunity))
	return lines
