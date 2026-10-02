## One-shot particle and sound effect that auto-frees after playback.
extends Node3D

@export var play_on_ready: bool = true
## Time in seconds before the node is freed. Set to 0 to disable auto-free.
@export var free_after_time: float = 2

# PUBLIC METHODS

## Starts all child [GPUParticles3D] and [AudioStreamPlayer3D] nodes and schedules auto-free.
func play() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = true
		elif child is AudioStreamPlayer3D:
			child.play()

	if free_after_time > 0:
		await get_tree().create_timer(free_after_time).timeout
		queue_free()

# NODE METHODS

func _ready() -> void:
	if play_on_ready:
		play()
