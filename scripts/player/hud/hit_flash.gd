extends TextureRect

## Damage feedback (scenes/player/hud/hit_flash.tscn): a red vignette that
## flashes on every hit the local player takes, stronger for bigger hits.

const MIN_ALPHA := 0.3
# vignette alpha per fraction of max health lost (a 34-damage hit ≈ 0.6)
const ALPHA_PER_HEALTH := 1.8

@onready var anim: AnimationPlayer = $Anim


func flash(health_fraction: float) -> void:
	self_modulate.a = clampf(health_fraction * ALPHA_PER_HEALTH, MIN_ALPHA, 1.0)
	anim.stop()
	anim.play(&"flash")
