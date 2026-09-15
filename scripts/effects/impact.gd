extends GPUParticles3D

const SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/impactMetal_000.ogg"),
	preload("res://assets/audio/impactMetal_001.ogg"),
]

@onready var sound: AudioStreamPlayer3D = $Sound

func _ready() -> void:
	emitting = true
	sound.stream = SOUNDS.pick_random()
	sound.pitch_scale = randf_range(0.9, 1.1)
	sound.play()
	finished.connect(queue_free)
